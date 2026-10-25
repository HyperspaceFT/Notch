import NotchKit
import NotchUI
import SwiftUI

/// How much of the user's Claude, Codex, and Grok subscription limits is used,
/// read from the internal endpoints those websites' usage pages call, with the
/// sign-ins made in Notch's own sign-in window (Settings → Usage). A tab right
/// of the notch shows a card per provider, while at least one is shown; its
/// icon is a gauge of the highest percent. A small Home module shows the same
/// as thin bars and opens the tab. The endpoints are undocumented and may
/// change at any time; a failed read only shows as such.
@MainActor
public final class UsageFeature: NotchFeature {
    public let id = "usage"
    public var title: String { localized(en: "Usage Limits", zh: "用量限额") }
    public let symbol = "gauge.with.needle"
    public let tabPlacement = NotchTabPlacement.trailing
    /// While at least one provider is shown, or a debug sample shows.
    public var isTabAvailable: Bool { !model.displayedProviders.isEmpty }

    private let model: UsageModel
    private weak var context: (any NotchContext)?

    public init() {
        model = .shared
    }

    public func activate(context: any NotchContext) {
        self.context = context
    }

    public func deactivate() {
        model.stop()
        context = nil
    }

    public func makeExpandedView() -> AnyView? {
        AnyView(UsageTabView(model: model))
    }

    public func makeTabIcon() -> AnyView? {
        AnyView(UsageTabIcon(model: model))
    }

    public func makeHomeModules() -> [NotchHomeModule] {
        [
            NotchHomeModule(
                id: "usage",
                title: { localized(en: "Usage Limits", zh: "用量限额") },
                symbol: "gauge.with.needle",
                detail: {
                    localized(
                        en: "Claude, Codex, and Grok usage, read from their websites with the sign-ins in Settings → Usage.",
                        zh: "Claude、Codex 和 Grok 的用量，用「设置 → 用量」中的登录从网站读取。"
                    )
                },
                sizing: UsageModuleView.sizing,
                content: { [model, weak self] size in
                    AnyView(UsageModuleView(model: model, size: size) { [weak self] in
                        self?.showTab()
                    })
                }
            ),
        ]
    }

    /// Sample usage and states for the tab, its icon, and the Home module, in
    /// memory only and without any request, until "Use Real Usage" or five
    /// minutes (or an action on the real usage, such as the Settings switch).
    public var debugItems: [NotchMenuItem] {
        [
            .button(localized(en: "Show Sample Usage", zh: "显示示例用量"), symbol: "gauge.with.needle") { [model] in
                model.showSample(.reports(now: Date()))
            },
            // One card across the whole tab, its windows side by side.
            .button(localized(en: "Show One Provider", zh: "只显示一个提供方"), symbol: "rectangle") { [model] in
                model.showSample(.reports(for: [.claude], now: Date()))
            },
            .submenu(localized(en: "Status", zh: "状态"), symbol: "exclamationmark.circle", items: [
                .button(localized(en: "Loading", zh: "加载中"), symbol: "hourglass") { [model] in
                    model.showSample(.state(.loading, now: Date()))
                },
                .button(localized(en: "Not Signed In", zh: "未登录"), symbol: "person.crop.circle.badge.xmark") { [model] in
                    model.showSample(.state(.signedOut, now: Date()))
                },
                .button(localized(en: "Needs Verification", zh: "需要验证"), symbol: "checkmark.shield") { [model] in
                    model.showSample(.state(.needsVerification, now: Date()))
                },
                .button(localized(en: "Failed to Load", zh: "加载失败"), symbol: "icloud.slash") { [model] in
                    model.showSample(.state(.failed(.network), now: Date()))
                },
            ]),
            .divider,
            .button(localized(en: "Use Real Usage", zh: "恢复真实用量"), symbol: "arrow.clockwise") { [model] in
                model.useRealUsage()
            },
        ]
    }

    /// Opens the Usage tab from the Home module.
    private func showTab() {
        // The card shows only in the open panel, so this switches tabs.
        withAnimation(NotchTheme.tabSwitchAnimation) {
            context?.requestExpand()
        }
    }
}
