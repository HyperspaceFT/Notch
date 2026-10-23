import HomeFeature
import NotchKit
import NotchUI
import SwiftUI

/// The Home pane: which modules the Home tab shows, in what order, and how wide.
struct HomeSettingsView: View {
    let settings: HomeLayoutSettings

    var body: some View {
        Form {
            Section {
                HomeLayoutPreview(settings: settings)
            }
            Section {
                let placements = settings.placements
                ForEach(Array(placements.enumerated()), id: \.element.id) { index, placement in
                    HomeModuleRow(
                        settings: settings,
                        placement: placement,
                        index: index,
                        isLast: index == placements.count - 1
                    )
                }
                addMenu
            } header: {
                Text(localized(en: "Modules", zh: "模块"))
            } footer: {
                Text(countNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var addMenu: some View {
        let candidates = settings.modulesNotShown
        return Menu {
            ForEach(candidates) { module in
                Button(module.title(), systemImage: module.symbol) {
                    settings.add(module.id)
                }
                .disabled(!settings.canAdd(module.id))
            }
        } label: {
            Label(localized(en: "Add Module", zh: "添加模块"), systemImage: "plus")
        }
        .disabled(candidates.isEmpty || settings.placements.count >= HomeLayoutSettings.maximumModuleCount)
    }

    /// The limit, and how many modules exist while there are fewer than that.
    private var countNote: String {
        let limit = HomeLayoutSettings.maximumModuleCount
        let available = settings.modules.count
        guard available < limit else {
            return localized(en: "Home holds up to \(limit) modules.", zh: "主页最多可以放 \(limit) 个模块。")
        }
        return localized(
            en: "Home holds up to \(limit) modules; only \(available) \(available == 1 ? "is" : "are") available so far.",
            zh: "主页最多可以放 \(limit) 个模块，目前只有 \(available) 个模块可用。"
        )
    }
}

/// One module: its name, its order and removal buttons, and its width.
private struct HomeModuleRow: View {
    let settings: HomeLayoutSettings
    let placement: HomeLayoutSettings.Placement
    let index: Int
    let isLast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: placement.module.symbol)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(placement.module.title())
                    if let detail = placement.module.detail {
                        Text(detail())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                // Up the list is left in the row, as the preview shows.
                iconButton(localized(en: "Move Up", zh: "上移"), symbol: "chevron.up") {
                    settings.move(from: index, to: index - 1)
                }
                .disabled(index == 0)
                iconButton(localized(en: "Move Down", zh: "下移"), symbol: "chevron.down") {
                    settings.move(from: index, to: index + 1)
                }
                .disabled(isLast)
                iconButton(localized(en: "Remove", zh: "移除"), symbol: "minus.circle") {
                    settings.remove(at: index)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            if placement.module.sizing.isResizable {
                let width = placement.width
                let range = placement.range
                // Disabled while the other modules leave no room to grow; a slider
                // needs a range that is not a single value.
                let hasRoom = range.upperBound - range.lowerBound > 0.001
                Slider(
                    value: Binding(get: { width }, set: { [settings, index] in settings.setWidth($0, at: index) }),
                    in: hasRoom ? range : range.lowerBound...(range.lowerBound + 0.001)
                ) {
                    Text(localized(en: "Width", zh: "长度"))
                }
                .disabled(!hasRoom)
            } else {
                Text(localized(en: "Fixed width", zh: "长度固定"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func iconButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .help(title)
    }
}

/// The Home row in miniature, drawn like the panel: each module a tile as wide as
/// it will be, free space left black. One scale for every module count, so the
/// island widens as modules join, as the panel does.
private struct HomeLayoutPreview: View {
    let settings: HomeLayoutSettings

    /// Width of the widest row, the one with the most modules.
    private static let maximumWidth: CGFloat = 340
    private static let scale = maximumWidth
        / HomeLayoutSettings.referenceRow(forModuleCount: HomeLayoutSettings.maximumModuleCount).width

    var body: some View {
        let row = settings.currentRow
        let scale = Self.scale
        let placed = settings.placedModules(in: row)
        HStack(spacing: row.spacing * scale) {
            if placed.isEmpty {
                Text(localized(en: "Home is empty", zh: "主页没有模块"))
                    .font(.caption)
                    .foregroundStyle(NotchTheme.secondaryText)
            }
            ForEach(placed) { entry in
                VStack(spacing: 4) {
                    Image(systemName: entry.module.symbol)
                        .font(.system(size: 16))
                    Text(entry.module.title())
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(NotchTheme.primaryText)
                .frame(width: entry.width * scale, height: row.height * scale)
                .background(.white.opacity(0.12), in: .rect(cornerRadius: 16 * scale, style: .continuous))
            }
        }
        .frame(width: row.width * scale, height: row.height * scale)
        .padding(12 * scale)
        .background(NotchTheme.islandColor, in: .rect(cornerRadius: 22 * scale, style: .continuous))
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.25), value: placed.map { "\($0.id):\($0.width)" })
        .accessibilityHidden(true)
    }
}
