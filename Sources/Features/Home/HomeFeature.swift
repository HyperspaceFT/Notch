import NotchKit
import NotchUI
import SwiftUI

/// Home tab, the first one in the expanded panel: a row of modules, its own clock
/// and those other features offer (such as the weather), which the user picks,
/// orders, and sizes in the settings window. No activities.
@MainActor
public final class HomeFeature: NotchFeature {
    public let id = "home"
    public var title: String { localized(en: "Home", zh: "主页") }
    public let symbol = "house"

    /// Features whose `makeHomeModules()` Home shows besides its clock.
    private let moduleSources: [any NotchFeature]
    private let settings: HomeLayoutSettings

    public init(moduleSources: [any NotchFeature] = []) {
        self.moduleSources = moduleSources
        settings = .shared
    }

    public func makeExpandedView() -> AnyView? {
        // The shell asks for views only after activating every feature, which is
        // when `makeHomeModules()` may be called.
        settings.register([TimeModule.makeModule()] + moduleSources.flatMap { $0.makeHomeModules() })
        return AnyView(HomeExpandedView(settings: settings))
    }
}

private struct HomeExpandedView: View {
    let settings: HomeLayoutSettings

    var body: some View {
        GeometryReader { proxy in
            let row = HomeRowMetrics(
                width: proxy.size.width,
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
                    // A row narrower than the panel stays centered.
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
