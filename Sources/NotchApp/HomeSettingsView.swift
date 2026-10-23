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
            } footer: {
                Text(localized(en: "Drag a module sideways to change its width.", zh: "左右拖动模块可以调整长度。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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

/// One module: its name and its order buttons. Its width and removal are edited
/// in the preview.
private struct HomeModuleRow: View {
    let settings: HomeLayoutSettings
    let placement: HomeLayoutSettings.Placement
    let index: Int
    let isLast: Bool

    var body: some View {
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
                if !placement.module.sizing.isResizable {
                    Text(localized(en: "Fixed width", zh: "长度固定"))
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
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.vertical, 2)
    }

    private func iconButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .help(title)
    }
}

/// The Home row in miniature, drawn like the panel and edited in place: each
/// module a tile as wide as it will be, in an island that hugs them as the panel
/// does. One scale for every module count, so the island widens as modules join
/// or grow, as the panel does. Dragging a resizable tile sideways moves its
/// trailing edge (see `HomeLayoutSettings.resize`); the button in its corner
/// removes it.
private struct HomeLayoutPreview: View {
    let settings: HomeLayoutSettings
    /// The drag in progress; back to nil when it ends.
    @GestureState private var drag: HomeLayoutSettings.Resize?

    /// Width of the widest row, the one with the most modules.
    private static let maximumWidth: CGFloat = 340
    private static let scale = maximumWidth
        / HomeLayoutSettings.referenceRow(forModuleCount: HomeLayoutSettings.maximumModuleCount).width
    /// Below this, a module's width range counts as a single value.
    private static let minimumRoom = 0.001
    /// What one step of the accessibility adjustment changes a width by.
    private static let accessibilityStep: CGFloat = 10

    var body: some View {
        let row = settings.currentRow
        let scale = Self.scale
        let placed = settings.placedModules(in: row)
        let placements = settings.placements
        HStack(spacing: row.spacing * scale) {
            if placed.isEmpty {
                Text(localized(en: "Home is empty", zh: "主页没有模块"))
                    .font(.caption)
                    .foregroundStyle(NotchTheme.secondaryText)
            }
            ForEach(Array(placed.enumerated()), id: \.element.id) { index, entry in
                if placements.indices.contains(index) {
                    tile(entry, placement: placements[index], index: index, row: row)
                }
            }
        }
        .frame(width: (settings.expandedWidth - HomeLayoutSettings.margins) * scale, height: row.height * scale)
        .padding(12 * scale)
        .background(NotchTheme.islandColor, in: .rect(cornerRadius: 22 * scale, style: .continuous))
        .frame(maxWidth: .infinity)
        // Tiles follow the pointer while dragging; an animation would trail it.
        .animation(drag == nil ? .snappy(duration: 0.25) : nil, value: placed.map { "\($0.id):\($0.width)" })
        .onChange(of: drag) { _, drag in
            if let drag {
                settings.resize(drag)
            }
        }
    }

    private func tile(
        _ entry: HomeLayoutSettings.PlacedModule,
        placement: HomeLayoutSettings.Placement,
        index: Int,
        row: HomeRowMetrics
    ) -> some View {
        let scale = Self.scale
        let range = placement.range
        let isResizable = entry.module.sizing.isResizable && range.upperBound - range.lowerBound > Self.minimumRoom
        // Which way the trailing edge can still go: out only at the minimum, in
        // only at the maximum.
        let directions: FrameResizeDirection.Set = if placement.width <= range.lowerBound + Self.minimumRoom {
            .outward
        } else if placement.width >= range.upperBound - Self.minimumRoom {
            .inward
        } else {
            .all
        }
        let removeTitle = localized(en: "Remove", zh: "移除")
        let points = Int(entry.width.rounded())
        return VStack(spacing: 4) {
            Image(systemName: entry.module.symbol)
                .font(.system(size: 16))
            Text(entry.module.title())
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(NotchTheme.primaryText)
        .frame(width: entry.width * scale, height: row.height * scale)
        .background(.white.opacity(0.12), in: .rect(cornerRadius: 16 * scale, style: .continuous))
        .overlay(alignment: .trailing) {
            if isResizable {
                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(width: 2, height: row.height * scale * 0.3)
                    .padding(.trailing, 3)
            }
        }
        .contentShape(.rect)
        .pointerStyle(isResizable ? .frameResize(position: .trailing, directions: directions) : nil)
        .gesture(resizeGesture(at: index), isEnabled: isResizable)
        .overlay(alignment: .topTrailing) {
            Button {
                settings.remove(at: index)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(white: 0.4))
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help(removeTitle)
            .padding(3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.module.title())
        .accessibilityValue(localized(en: "\(points) points", zh: "\(points) 点"))
        .accessibilityAdjustableAction { direction in
            let step = row.fraction(forWidth: Self.accessibilityStep) - row.fraction(forWidth: 0)
            switch direction {
            case .increment: settings.setWidth(placement.width + step, at: index)
            case .decrement: settings.setWidth(placement.width - step, at: index)
            @unknown default: break
            }
        }
        .accessibilityAction(named: Text(removeTitle)) {
            settings.remove(at: index)
        }
    }

    /// Follows the pointer from where the drag began, in points of the row.
    /// Side effects stay out of `updating`; `onChange(of: drag)` applies it.
    private func resizeGesture(at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($drag) { value, state, _ in
                var resize = state ?? settings.beginResize(at: index)
                resize?.translation = value.translation.width / Self.scale
                state = resize
            }
    }
}
