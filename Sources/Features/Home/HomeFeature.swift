import NotchKit
import NotchUI
import SwiftUI

/// Home tab, the first one in the expanded panel: a row of modules other features
/// offer (such as the clock and the weather), which the user picks, orders, and
/// sizes in the settings window. No activities.
@MainActor
public final class HomeFeature: NotchFeature {
    public let id = "home"
    public var title: String { localized(en: "Home", zh: "主页") }
    public let symbol = "house"
    /// As wide as the modules Home shows, between the standard width and the
    /// widest for their count (see `HomeLayoutSettings.expandedWidth`); follows
    /// the settings window while the island is open.
    public var expandedWidth: CGFloat? { settings.expandedWidth }

    /// Features whose `makeHomeModules()` Home shows, in this order (the standard
    /// layout's order).
    private let moduleSources: [any NotchFeature]
    private let settings: HomeLayoutSettings

    public init(moduleSources: [any NotchFeature] = []) {
        self.moduleSources = moduleSources
        settings = .shared
    }

    public func makeExpandedView() -> AnyView? {
        // The shell asks for views only after activating every feature, which is
        // when `makeHomeModules()` may be called.
        settings.register(moduleSources.flatMap { $0.makeHomeModules() })
        return AnyView(HomeExpandedView(settings: settings))
    }
}

private struct HomeExpandedView: View {
    let settings: HomeLayoutSettings

    var body: some View {
        GeometryReader { proxy in
            // The row the layout is edited against, not the panel's width: the
            // island hugs the modules, and while Home is hidden behind another tab
            // the panel takes that tab's width, yet the modules keep their widths
            // and their places relative to the center.
            let row = HomeRowMetrics(
                width: settings.currentRow.width,
                height: proxy.size.height,
                spacing: HomeLayoutSettings.spacing
            )
            let placed = settings.placedModules(in: row)
            Group {
                if placed.isEmpty {
                    NotchCard {
                        Text(localized(
                            en: "Add modules in Settings… → Home.",
                            zh: "可以在「设置… → 主页」中添加模块。"
                        ))
                        .font(.system(size: 12))
                        .foregroundStyle(NotchTheme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    // A row narrower than the panel (at the standard width) or
                    // wider (behind a narrower tab) stays centered.
                    HStack(spacing: row.spacing) {
                        ForEach(placed) { entry in
                            entry.module.content(CGSize(width: entry.width, height: row.height))
                                .frame(width: entry.width, height: row.height)
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
