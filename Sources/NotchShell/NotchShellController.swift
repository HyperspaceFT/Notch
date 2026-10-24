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
    /// Whether a Debug pane action turned hover off (`debugItems`).
    private var isPinnedByDebugPane = false
    private let screenLocator = ScreenLocator()

    /// Called from the island's right-click menu to open the settings window.
    public var onOpenSettings: () -> Void = {}

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
        let hostingView = NotchHostingView(rootView: NotchRootView(model: model) { [weak self] in
            self?.onOpenSettings()
        })
        // The panel has a fixed size; the SwiftUI content must not resize it.
        hostingView.sizingOptions = []
        hostingView.safeAreaRegions = []
        panel.contentView = hostingView
        self.panel = panel

        model.onInteractivityChange = { [weak panel] interactive in
            // Collapsed/activity without hover: let clicks through to the menu bar underneath.
            panel?.ignoresMouseEvents = !interactive
            // A collapsed island must not keep the keyboard from the app the user was in.
            if !interactive {
                panel?.relinquishKeyFocus()
            }
        }
        // Hidden tabs stay mounted, so a hidden editor would keep taking keystrokes.
        model.onSelectedTabChange = { [weak panel] in
            panel?.endTextEditing()
        }

        screenLocator.onChange = { [weak self] geometry in
            self?.apply(geometry)
        }
        screenLocator.start()

        let featureHost = FeatureHost(model: model)
        featureHost.start(features: features)
        self.featureHost = featureHost

        let hoverController = HoverController(model: model)
        hoverController.isEditingText = { [weak panel] in
            panel?.isEditingText ?? false
        }
        panel.onFocusChange = { [weak hoverController] in
            hoverController?.refresh()
        }
        hoverController.onClickOutsideIsland = { [weak panel] in
            panel?.endTextEditing()
        }
        hoverController.start()
        self.hoverController = hoverController

        applyDebugState(to: model)

        // Never activates the app (accessory app + non-activating panel).
        panel.orderFrontRegardless()

        scheduleDebugSnapshot(of: hostingView)
    }

    public func stop() {
        // First, so text still being composed reaches its feature before the
        // features save on deactivation.
        panel?.endTextEditing()
        hoverController?.stop()
        hoverController = nil
        featureHost?.stop()
        featureHost = nil
        screenLocator.stop()
        screenLocator.onChange = nil
        panel?.onFocusChange = nil
        model?.onSelectedTabChange = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
        isPinnedByDebugPane = false
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

    /// Actions for the settings window's Debug pane that pin the island's own
    /// state. Pinning turns the hover controller off (as `-NotchDebugState` does),
    /// so the island stays as it is while the pointer is in the settings window;
    /// without it an island opened from there closes again about a second and a
    /// half later (`HoverController.arrivalDelay`).
    public var debugItems: [NotchMenuItem] {
        guard model != nil else { return [] }
        return [
            .button(
                localized(en: "Expand and Keep Open", zh: "展开并保持"),
                symbol: "arrow.up.left.and.arrow.down.right"
            ) { [weak self] in
                self?.pinIsland { $0.requestExpand(tabID: nil) }
            },
            .button(
                localized(en: "Hover and Keep", zh: "悬停并保持"),
                symbol: "cursorarrow.rays"
            ) { [weak self] in
                self?.pinIsland {
                    $0.setExpanded(false)
                    $0.setHovered(true)
                }
            },
            .button(
                localized(en: "Collapse and Keep", zh: "收起并保持"),
                symbol: "arrow.down.right.and.arrow.up.left"
            ) { [weak self] in
                self?.pinIsland {
                    $0.setHovered(false)
                    $0.setExpanded(false)
                }
            },
            .divider,
            .button(
                localized(en: "Follow the Pointer Again", zh: "恢复跟随鼠标"),
                symbol: "cursorarrow.motionlines"
            ) { [weak self] in
                self?.followPointer()
            },
        ]
    }

    /// Ends a pin: the island follows the pointer again, as it does without debug mode.
    public func followPointer() {
        guard let model else { return }
        isPinnedByDebugPane = false
        model.isHoverEnabled = true
        // Judge the pointer now, so a pinned hover or expansion does not
        // wait for the next mouse move to end.
        hoverController?.refresh()
    }

    /// Ends a pin made from the Debug pane, if there is one; leaves alone the
    /// pin of a `-NotchDebugState` launch, which no pane action made. A pin
    /// must not outlive the pane: a collapsed, pinned island ignores the mouse,
    /// so its right-click menu (the way back to Settings… and Quit) would be gone.
    public func endDebugPins() {
        guard isPinnedByDebugPane else { return }
        followPointer()
    }

    private func pinIsland(_ change: (NotchViewModel) -> Void) {
        guard let model else { return }
        isPinnedByDebugPane = true
        model.isHoverEnabled = false
        change(model)
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
