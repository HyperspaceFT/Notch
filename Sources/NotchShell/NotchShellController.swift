import AppKit
import NotchKit
import NotchUI
import SwiftUI

/// Public entry point of the shell: creates the panel, wires hover and screen
/// tracking, and hosts the features.
///
/// Debug hook: launching with `-NotchDebugState <collapsed|activity|expanded>`
/// (read from the UserDefaults argument domain) pins the island in that state
/// and disables hover, e.g.
///
///     open build/Notch.app --args -NotchDebugState expanded
///
/// `activity` additionally presents a persistent demo activity.
@MainActor
public final class NotchShellController {
    static let debugStateKey = "NotchDebugState"
    static let debugSnapshotKey = "NotchDebugSnapshot"

    private var model: NotchViewModel?
    private var panel: NotchPanel?
    private var hoverController: HoverController?
    private var featureHost: FeatureHost?
    private let screenLocator = ScreenLocator()

    public init() {}

    public func start(features: [any NotchFeature]) {
        guard model == nil else { return }

        // No attached screen is practically impossible at launch; use a plausible
        // laptop frame so the layout stays valid until the screens report in.
        let geometry = screenLocator.currentGeometry() ?? NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            safeAreaTop: 0,
            auxiliaryTopLeftArea: .zero,
            auxiliaryTopRightArea: .zero
        )
        let model = NotchViewModel(geometry: geometry)
        self.model = model

        let panel = NotchPanel(contentRect: geometry.topCenteredRect(size: NotchTheme.panelSize))
        let hostingView = NotchHostingView(rootView: NotchRootView(model: model))
        // The panel has a fixed size; the SwiftUI content must not resize it.
        hostingView.sizingOptions = []
        hostingView.safeAreaRegions = []
        panel.contentView = hostingView
        self.panel = panel

        model.onExpansionChange = { [weak panel] expanded in
            // Collapsed/activity: let clicks through to the menu bar underneath.
            panel?.ignoresMouseEvents = !expanded
        }

        screenLocator.onChange = { [weak self] geometry in
            self?.apply(geometry)
        }
        screenLocator.start()

        let featureHost = FeatureHost(model: model)
        featureHost.start(features: features)
        self.featureHost = featureHost

        let hoverController = HoverController(model: model)
        hoverController.start()
        self.hoverController = hoverController

        applyDebugState(to: model)

        // Never activates the app (accessory app + non-activating panel).
        panel.orderFrontRegardless()

        scheduleDebugSnapshot(of: hostingView)
    }

    public func stop() {
        hoverController?.stop()
        hoverController = nil
        featureHost?.stop()
        featureHost = nil
        screenLocator.stop()
        screenLocator.onChange = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    private func apply(_ geometry: NotchGeometry) {
        model?.updateGeometry(geometry)
        panel?.setFrame(geometry.topCenteredRect(size: NotchTheme.panelSize), display: true)
    }

    /// Debug hook: `-NotchDebugSnapshot <path.png>` writes the panel's own
    /// rendering to a PNG once animations have settled. It renders in-process,
    /// so it needs no Screen Recording permission. Combine it with
    /// `-NotchDebugState` to capture a specific state.
    private func scheduleDebugSnapshot(of view: NSView) {
        guard let path = UserDefaults.standard.string(forKey: Self.debugSnapshotKey) else { return }
        Task { @MainActor [weak view] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private func applyDebugState(to model: NotchViewModel) {
        guard
            let raw = UserDefaults.standard.string(forKey: Self.debugStateKey),
            let state = NotchViewModel.State(rawValue: raw)
        else { return }

        model.isHoverEnabled = false
        switch state {
        case .collapsed:
            model.setExpanded(false)
        case .activity:
            model.present(NotchActivity(id: "debug", featureID: "debug") {
                Image(systemName: "ladybug.fill")
            } trailing: {
                Text("Debug")
            })
            model.setExpanded(false)
        case .expanded:
            model.setExpanded(true)
        }
    }
}
