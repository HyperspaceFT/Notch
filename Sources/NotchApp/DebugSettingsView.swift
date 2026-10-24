import Foundation
import NotchKit
import Observation
import SwiftUI

/// Whether debug mode is on: the settings window then has a Debug pane whose
/// actions show the island's views at once, for checking how they look. Off by default.
@MainActor
@Observable
final class DebugSettings {
    static let shared = DebugSettings(defaults: .standard)

    static let enabledKey = "NotchDebugMode"

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? false
    }
}

/// What the Debug pane lists: the island's own actions first, then every feature's
/// that has any, in catalog order.
struct DebugSources {
    let islandItems: @MainActor () -> [NotchMenuItem]
    let features: [any NotchFeature]
}

/// The Debug pane: one section per source with actions that show something on the
/// island at once. The items are read while the pane draws, so their titles follow
/// the interface language and the features' observable state.
struct DebugSettingsView: View {
    let sources: DebugSources

    var body: some View {
        let island = sources.islandItems()
        let features = sources.features.map { (feature: $0, items: $0.debugItems) }.filter { !$0.items.isEmpty }
        Form {
            Section {
                Text(localized(
                    en: "These actions show sample content on the island and do not change your data. An island opened from this window closes again about a second and a half later because the pointer is not on it; the Island actions keep it as it is until you choose Follow the Pointer Again, close Settings, or turn Debug Mode off.",
                    zh: "这些操作会在灵动岛上显示示例内容，不会改动你的数据。从此窗口打开的岛会在约一秒半后收起，因为鼠标不在岛上；「灵动岛」中的操作可以让它保持原样，直到选择「恢复跟随鼠标」、关闭设置窗口或关闭调试模式。"
                ))
                .foregroundStyle(.secondary)
            }
            if !island.isEmpty {
                Section(localized(en: "Island", zh: "灵动岛")) {
                    DebugItemRows(items: island)
                }
            }
            ForEach(features, id: \.feature.id) { source in
                Section(source.feature.title) {
                    DebugItemRows(items: source.items)
                }
            }
        }
        .formStyle(.grouped)
        // A set height, unlike the other panes: its sections are taller than a
        // screen, so the form scrolls inside it.
        .frame(width: 420, height: 600)
    }
}

/// A section's rows: a button row per action, a pull-down menu per submenu.
private struct DebugItemRows: View {
    let items: [NotchMenuItem]

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            switch item.kind {
            case .action(let action):
                Button {
                    action()
                } label: {
                    DebugItemLabel(item: item)
                }
            case .submenu(let children):
                Menu {
                    DebugItemRows(items: children)
                } label: {
                    DebugItemLabel(item: item)
                }
            case .divider:
                Divider()
            }
        }
    }
}

private struct DebugItemLabel: View {
    let item: NotchMenuItem

    var body: some View {
        if let symbol = item.symbol {
            Label(item.title, systemImage: symbol)
        } else {
            Text(item.title)
        }
    }
}
