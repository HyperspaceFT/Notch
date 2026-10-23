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
                Text(localized(
                    en: "Drag the island's edges to resize the whole row, the line between two modules to trade their widths, or press and hold a module to move it.",
                    zh: "拖动两侧边缘整体缩放，拖动模块之间的分隔线调整相邻两个模块的长度，长按模块可以拖动换位置。"
                ))
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
/// or grow, as the panel does. The handles just outside the island's edges scale
/// the whole row, the lines between tiles trade width between neighbours (see
/// `HomeLayoutSettings.resize`), pressing and holding a tile lifts it to move it
/// elsewhere in the row, and the button in its corner removes it. The caption
/// under the island gives its width and range, or the limit a drag has reached.
private struct HomeLayoutPreview: View {
    let settings: HomeLayoutSettings
    /// The resize in progress; back to nil when it ends.
    @GestureState private var drag: HomeLayoutSettings.Resize?
    /// The tile being moved; back to nil, animated, when it is dropped.
    @GestureState(resetTransaction: Transaction(animation: .snappy(duration: 0.25)))
    private var reorder: Reorder?

    /// A tile lifted by a long press and the pointer's travel since, in points of
    /// the row.
    private struct Reorder: Equatable {
        let index: Int
        var translation: CGFloat
    }

    /// Width of the widest row, the one with the most modules. Leaves room in the
    /// 420-point pane for the edge handles outside the island.
    private static let maximumWidth: CGFloat = 310
    private static let scale = maximumWidth
        / HomeLayoutSettings.referenceRow(forModuleCount: HomeLayoutSettings.maximumModuleCount).width
    /// The island's padding around the row, in points of the row.
    private static let islandPadding: CGFloat = 12
    /// Below this, a width counts as at a limit.
    private static let minimumRoom: CGFloat = 0.01
    /// What one step of the accessibility adjustment moves a tile's boundary by.
    private static let accessibilityStep: CGFloat = 10
    /// What one step of the island's accessibility adjustment changes the row by.
    private static let rowAccessibilityStep: CGFloat = 20
    private static let edgeHandleWidth: CGFloat = 14
    private static let boundaryHandleWidth: CGFloat = 12
    /// How long a tile has to be held before it lifts.
    private static let liftDelay = 0.3

    var body: some View {
        let row = settings.currentRow
        let placed = settings.placedModules(in: row)
        let limit = drag.flatMap { settings.limit(for: $0) }
        VStack(spacing: 8) {
            island(placed: placed, row: row, limit: limit)
            caption(placed: placed, limit: limit)
        }
        .frame(maxWidth: .infinity)
        // Tiles follow the pointer while dragging; an animation would trail it.
        .animation(
            drag == nil && reorder == nil ? .snappy(duration: 0.25) : nil,
            value: placed.map { "\($0.id):\($0.width)" }
        )
        .sensoryFeedback(.alignment, trigger: limit) { old, new in new != nil && new != old }
        .onChange(of: drag) { _, drag in
            if let drag {
                settings.resize(drag)
            }
        }
    }

    private func island(
        placed: [HomeLayoutSettings.PlacedModule],
        row: HomeRowMetrics,
        limit: HomeLayoutSettings.ResizeLimit?
    ) -> some View {
        let scale = Self.scale
        let widths = placed.map(\.width)
        let islandContent = settings.expandedWidth - HomeLayoutSettings.margins
        // The row is centered in the island, which is wider only below the standard width.
        let inset = (islandContent - settings.contentWidth) / 2
        let destination = reorder.map {
            HomeLayoutSettings.reorderDestination(
                widths: widths,
                spacing: row.spacing,
                index: $0.index,
                translation: $0.translation
            )
        }
        let offsets = Self.offsets(widths: widths, spacing: row.spacing, reorder: reorder, destination: destination)
        let isEdgeLimit = switch limit {
        case .longest?, .shortest?: true
        default: false
        }
        return ZStack(alignment: .topLeading) {
            if placed.isEmpty {
                Text(localized(en: "Home is empty", zh: "主页没有模块"))
                    .font(.caption)
                    .foregroundStyle(NotchTheme.secondaryText)
                    .frame(width: islandContent * scale, height: row.height * scale)
            }
            ForEach(Array(placed.enumerated()), id: \.element.id) { index, entry in
                let isLifted = reorder?.index == index
                tile(entry, index: index, placed: placed, row: row, isLifted: isLifted)
                    .offset(x: (inset + offsets[index]) * scale)
                    // Others slide to open the slot; the lifted tile follows the pointer.
                    .animation(isLifted ? nil : .snappy(duration: 0.25), value: destination)
                    .zIndex(isLifted ? 1 : 0)
            }
            // Separate views above the tiles, so pressing one resizes rather than
            // lifting a tile. Hidden while a tile is lifted: the tiles are moving.
            if reorder == nil {
                ForEach(Array(placed.indices.dropLast()), id: \.self) { index in
                    if let range = settings.boundaryRange(at: index) {
                        boundaryHandle(at: index, range: range, row: row)
                            .offset(x: (inset + offsets[index] + widths[index] + row.spacing / 2) * scale
                                - Self.boundaryHandleWidth / 2)
                    }
                }
            }
        }
        .frame(width: islandContent * scale, height: row.height * scale, alignment: .topLeading)
        .padding(Self.islandPadding * scale)
        .background(NotchTheme.islandColor, in: .rect(cornerRadius: 22 * scale, style: .continuous))
        .overlay(alignment: .leading) {
            edgeHandle(.leadingEdge, row: row, isAtLimit: isEdgeLimit && drag?.handle == .leadingEdge)
                .offset(x: -Self.edgeHandleWidth)
        }
        .overlay(alignment: .trailing) {
            edgeHandle(.trailingEdge, row: row, isAtLimit: isEdgeLimit && drag?.handle == .trailingEdge)
                .offset(x: Self.edgeHandleWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized(en: "Island width", zh: "岛的长度"))
        .accessibilityValue(restingCaption(placed: placed))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: scaleRow(by: Self.rowAccessibilityStep)
            case .decrement: scaleRow(by: -Self.rowAccessibilityStep)
            @unknown default: break
            }
        }
    }

    /// Each tile's leading edge in points of the row: in layout order at rest;
    /// while a tile is lifted, the others closed up around the slot at
    /// `destination` and the lifted one where the pointer has taken it.
    private static func offsets(
        widths: [CGFloat],
        spacing: CGFloat,
        reorder: Reorder?,
        destination: Int?
    ) -> [CGFloat] {
        func leadingEdges(in order: [Int]) -> [CGFloat] {
            var edges = [CGFloat](repeating: 0, count: widths.count)
            var leading: CGFloat = 0
            for index in order {
                edges[index] = leading
                leading += widths[index] + spacing
            }
            return edges
        }
        let resting = leadingEdges(in: Array(widths.indices))
        guard let reorder, let destination, widths.indices.contains(reorder.index) else { return resting }
        var order = Array(widths.indices)
        order.remove(at: reorder.index)
        order.insert(reorder.index, at: min(destination, order.count))
        var edges = leadingEdges(in: order)
        edges[reorder.index] = resting[reorder.index] + reorder.translation
        return edges
    }

    private func tile(
        _ entry: HomeLayoutSettings.PlacedModule,
        index: Int,
        placed: [HomeLayoutSettings.PlacedModule],
        row: HomeRowMetrics,
        isLifted: Bool
    ) -> some View {
        let scale = Self.scale
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
        .background(.white.opacity(isLifted ? 0.18 : 0.12), in: .rect(cornerRadius: 16 * scale, style: .continuous))
        .contentShape(.rect)
        .gesture(reorderGesture(at: index, widths: placed.map(\.width), spacing: row.spacing), isEnabled: placed.count > 1)
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
        .scaleEffect(isLifted ? 1.05 : 1)
        .shadow(color: .black.opacity(isLifted ? 0.45 : 0), radius: 6, y: 3)
        .animation(.snappy(duration: 0.15), value: isLifted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.module.title())
        .accessibilityValue(localized(en: "\(points) points", zh: "\(points) 点"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjustWidth(at: index, count: placed.count, by: Self.accessibilityStep)
            case .decrement: adjustWidth(at: index, count: placed.count, by: -Self.accessibilityStep)
            @unknown default: break
            }
        }
        .accessibilityAction(named: Text(removeTitle)) {
            settings.remove(at: index)
        }
    }

    /// A short capsule just outside one of the island's edges.
    @ViewBuilder
    private func edgeHandle(_ handle: HomeLayoutSettings.ResizeHandle, row: HomeRowMetrics, isAtLimit: Bool) -> some View {
        let islandHeight = (row.height + 2 * Self.islandPadding) * Self.scale
        let range = settings.contentWidthRange
        let content = settings.contentWidth
        // Which way the edge can still go: out only at the shortest, in only at
        // the longest.
        let directions: FrameResizeDirection.Set = if content <= range.lowerBound + Self.minimumRoom {
            .outward
        } else if content >= range.upperBound - Self.minimumRoom {
            .inward
        } else {
            .all
        }
        if settings.beginResize(handle) != nil {
            Capsule()
                .fill(isAtLimit ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .frame(width: 4, height: islandHeight * 0.4)
                .frame(width: Self.edgeHandleWidth, height: islandHeight)
                .contentShape(.rect)
                .pointerStyle(.frameResize(position: handle == .leadingEdge ? .leading : .trailing, directions: directions))
                .gesture(resizeGesture(handle))
                .accessibilityHidden(true)
        }
    }

    /// A thin line centred on the gap after the tile at `index`.
    private func boundaryHandle(at index: Int, range: ClosedRange<CGFloat>, row: HomeRowMetrics) -> some View {
        var directions: HorizontalDirection.Set = []
        if range.lowerBound < -Self.minimumRoom {
            directions.insert(.leading)
        }
        if range.upperBound > Self.minimumRoom {
            directions.insert(.trailing)
        }
        return Capsule()
            .fill(.white.opacity(0.6))
            .frame(width: 2, height: row.height * Self.scale * 0.3)
            .frame(width: Self.boundaryHandleWidth, height: row.height * Self.scale)
            .contentShape(.rect)
            .pointerStyle(.columnResize(directions: directions))
            .gesture(resizeGesture(.boundary(index)))
            .accessibilityHidden(true)
    }

    /// One line under the island: its width and the range the edges reach at rest,
    /// or, in orange, the limit a drag has reached. Island widths, as the panel
    /// has them, for the edges; module widths for a boundary.
    private func caption(placed: [HomeLayoutSettings.PlacedModule], limit: HomeLayoutSettings.ResizeLimit?) -> some View {
        let text: String = switch limit {
        case .longest(let width)?:
            localized(
                en: "Longest for \(placed.count) \(placed.count == 1 ? "module" : "modules"): \(islandPoints(width)) pt",
                zh: "\(placed.count) 个模块时最长 \(islandPoints(width)) 点"
            )
        case .shortest(let width)?:
            localized(en: "Shortest: \(islandPoints(width)) pt", zh: "最短 \(islandPoints(width)) 点")
        case .narrowest(let index, let width)?:
            localized(
                en: "\(title(at: index, in: placed)) is at its narrowest: \(Int(width.rounded())) pt",
                zh: "\(title(at: index, in: placed))已是最窄：\(Int(width.rounded())) 点"
            )
        case .widest(let index, let width)?:
            localized(
                en: "\(title(at: index, in: placed)) is at its widest: \(Int(width.rounded())) pt",
                zh: "\(title(at: index, in: placed))已是最宽：\(Int(width.rounded())) 点"
            )
        case nil:
            restingCaption(placed: placed)
        }
        // A space keeps the line's height when there is nothing to say.
        return Text(text.isEmpty ? " " : text)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(limit == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            .frame(maxWidth: .infinity)
    }

    /// The island's width and the range its edges reach, or just the width when
    /// they cannot change it; empty without modules.
    private func restingCaption(placed: [HomeLayoutSettings.PlacedModule]) -> String {
        guard !placed.isEmpty else { return "" }
        let width = islandPoints(settings.contentWidth)
        let range = settings.contentWidthRange
        let (lower, upper) = (islandPoints(range.lowerBound), islandPoints(range.upperBound))
        guard lower < upper else { return localized(en: "\(width) pt", zh: "\(width) 点") }
        return localized(en: "\(width) pt · \(lower)–\(upper) pt", zh: "\(width) 点 · 可调 \(lower)–\(upper) 点")
    }

    /// The island's width for a content width, rounded, as
    /// `HomeLayoutSettings.expandedWidth` gives it: the content and the margins,
    /// within the standard width and the widest for the module count.
    private func islandPoints(_ contentWidth: CGFloat) -> Int {
        let width = min(
            max(contentWidth + HomeLayoutSettings.margins, NotchTheme.expandedSize.width),
            HomeLayoutSettings.bodyWidth(forModuleCount: settings.placements.count)
        )
        return Int(width.rounded())
    }

    private func title(at index: Int, in placed: [HomeLayoutSettings.PlacedModule]) -> String {
        placed.indices.contains(index) ? placed[index].module.title() : ""
    }

    /// Moves the tile's trailing boundary by `delta` points, or for the last tile
    /// its leading one by as much the other way, so that it grows by `delta`.
    private func adjustWidth(at index: Int, count: Int, by delta: CGFloat) {
        let isLast = index == count - 1
        guard var resize = settings.beginResize(.boundary(isLast ? index - 1 : index)) else { return }
        resize.translation = isLast ? -delta : delta
        settings.resize(resize)
    }

    /// Changes the row's content width by `delta` points.
    private func scaleRow(by delta: CGFloat) {
        guard var resize = settings.beginResize(.trailingEdge) else { return }
        // An edge drag changes the centered row by twice its translation.
        resize.translation = delta / 2
        settings.resize(resize)
    }

    /// Follows the pointer from where the drag began, in points of the row.
    /// Side effects stay out of `updating`; `onChange(of: drag)` applies it.
    private func resizeGesture(_ handle: HomeLayoutSettings.ResizeHandle) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($drag) { value, state, _ in
                var resize = state ?? settings.beginResize(handle)
                resize?.translation = value.translation.width / Self.scale
                state = resize
            }
    }

    /// Lifts the tile after a press of `liftDelay`, then follows the pointer; on
    /// release, the tile moves to the slot it is over.
    private func reorderGesture(at index: Int, widths: [CGFloat], spacing: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: Self.liftDelay)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($reorder) { value, state, _ in
                guard case .second(true, let drag) = value else { return }
                state = Reorder(index: index, translation: (drag?.translation.width ?? 0) / Self.scale)
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value else { return }
                let destination = HomeLayoutSettings.reorderDestination(
                    widths: widths,
                    spacing: spacing,
                    index: index,
                    translation: drag.translation.width / Self.scale
                )
                // Animated like the lift's reset, whichever transaction lands first,
                // so the tile glides from the pointer into its slot.
                withAnimation(.snappy(duration: 0.25)) {
                    settings.move(from: index, to: destination)
                }
            }
    }
}
