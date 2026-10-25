import Foundation
import NotchKit
import NotchUI
import Observation

/// The Home tab's layout, as the settings window edits it, and the modules it can
/// hold. Saved on every change; until the user changes it, Home shows the
/// standard layout of whatever modules exist (see `HomeLayout.standard`).
@MainActor
@Observable
public final class HomeLayoutSettings {
    public static let shared = HomeLayoutSettings(defaults: .standard)

    static let layoutKey = "NotchHomeLayout"
    /// Below this many points, a handle's room counts as none.
    private static let minimumRoom: CGFloat = 0.01

    /// The most modules Home shows at once.
    public nonisolated static let maximumModuleCount = HomeLayout.maximumCount
    /// Gap between modules in Home's row.
    public nonisolated static let spacing: CGFloat = 10
    /// How much room the row gains for each module past the first, in order: the
    /// second and the third add the same, the fourth less, so a full row does not
    /// stretch the island too far. One entry per module up to `maximumModuleCount`.
    public nonisolated static let extraWidths: [CGFloat] = [120, 120, 80]
    /// What the island's body adds to Home's row: the content padding on each side
    /// (the ears at the top corners lie outside the body), so the modules sit as
    /// far from the sides as from the bottom.
    public nonisolated static let margins: CGFloat = 2 * NotchTheme.contentPadding

    /// The widest the expanded island's body gets while Home shows `count`
    /// modules, which it reaches when they fill their row: the standard width for
    /// one module or none, plus `extraWidths` for each further one, up to
    /// `maximumModuleCount`. Narrower modules give a narrower island (see
    /// `expandedWidth`).
    public nonisolated static func bodyWidth(forModuleCount count: Int) -> CGFloat {
        let extraModules = max(min(count, maximumModuleCount) - 1, 0)
        return NotchTheme.expandedSize.width + extraWidths.prefix(extraModules).reduce(0, +)
    }

    /// Home's row with `count` modules under a 32-point notch: as wide as the body at
    /// `bodyWidth(forModuleCount:)` less `margins` (as wide as the island's
    /// content), as tall as the panel's header and margins leave: the most
    /// room the modules get. Layouts are edited against the row for their own
    /// count; Home draws them in a row as wide, whose height follows the notch.
    public nonisolated static func referenceRow(forModuleCount count: Int) -> HomeRowMetrics {
        HomeRowMetrics(
            width: bodyWidth(forModuleCount: count) - margins,
            height: 134,
            spacing: spacing
        )
    }

    /// A module in the layout, with its width as a share of `currentRow`.
    public struct Placement: Identifiable {
        public let module: NotchHomeModule
        public let width: Double
        public var id: String { module.id }
    }

    /// A module at its width in points in a given row.
    public struct PlacedModule: Identifiable {
        public let module: NotchHomeModule
        public let width: CGFloat
        public var id: String { module.id }
    }

    /// What a resize drags.
    public enum ResizeHandle: Hashable, Sendable {
        /// The island's leading edge, which scales the whole row.
        case leadingEdge
        /// The island's trailing edge, which scales the whole row.
        case trailingEdge
        /// The line between the module at the index and the one after it, which
        /// trades width between the two.
        case boundary(Int)
    }

    /// A drag on a handle, from `beginResize(_:)`; `resize(_:)` applies it.
    public struct Resize: Equatable, Sendable {
        public let handle: ResizeHandle
        /// The layout when the drag began; every step starts from it.
        let start: HomeLayout
        /// How far the pointer has moved, in points of `currentRow`.
        public var translation: CGFloat
    }

    /// A limit a resize has reached (see `limit(for:)`). Widths are in points of
    /// `currentRow`; the edges' are content widths, the modules and their gaps.
    public enum ResizeLimit: Equatable, Sendable {
        /// An edge drag asks for a longer row than `contentWidthRange` allows.
        case longest(CGFloat)
        /// An edge drag asks for a shorter row than `contentWidthRange` allows.
        case shortest(CGFloat)
        /// A boundary drag holds the module at `index` at its minimum.
        case narrowest(index: Int, width: CGFloat)
        /// A boundary drag holds the module at `index` at its maximum.
        case widest(index: Int, width: CGFloat)
    }

    /// Every module Home can show, in the order Home registered them.
    public private(set) var modules: [NotchHomeModule] = []
    private(set) var layout: HomeLayout

    @ObservationIgnored private let defaults: UserDefaults
    /// False until the user first changes the layout; until then it follows
    /// `HomeLayout.standard` for the registered modules.
    @ObservationIgnored private var isCustomized: Bool

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.layoutKey),
           let items = try? JSONDecoder().decode([HomeLayout.Item].self, from: data) {
            layout = HomeLayout(items: items)
            isCustomized = true
        } else {
            layout = HomeLayout()
            isCustomized = false
        }
    }

    /// Called by `HomeFeature` once every module is known.
    func register(_ modules: [NotchHomeModule]) {
        // Ids key the saved layout; a duplicate would make two modules collide.
        assert(Set(modules.map(\.id)).count == modules.count, "Duplicate NotchHomeModule id")
        self.modules = modules
        if isCustomized {
            // A layout saved while a module had another width (or was still
            // resizable) hands the difference to that module's neighbours.
            layout.followFixedWidths(sizings: sizings, rows: Self.referenceRow(forModuleCount:))
            layout.normalize(sizings: sizings, rows: Self.referenceRow(forModuleCount:))
        } else {
            layout = .standard(moduleIDs: modules.map(\.id), sizings: sizings, rows: Self.referenceRow(forModuleCount:))
        }
        followSizings()
    }

    /// Lays the row out again whenever a module's sizing changes (a module whose
    /// width follows its own state), again after every change: a customized
    /// layout passes the difference to the neighbours (`HomeLayout.followFixedWidths`)
    /// and is saved if that changed it; one that still follows the standard
    /// layout is rebuilt from it and not saved. A Resize drag in progress is not
    /// special-cased: each of its steps starts from the layout the drag began
    /// with (see `resize(_:)`), so a change during the drag is overwritten by
    /// its next step; sizings change from the Settings window's other panes,
    /// not during a drag in the Home pane.
    private func followSizings() {
        _ = withObservationTracking {
            sizings
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sizingsChanged()
            }
        }
    }

    private func sizingsChanged() {
        if isCustomized {
            edit { $0.followFixedWidths(sizings: sizings, rows: Self.referenceRow(forModuleCount:)) }
        } else {
            layout = .standard(moduleIDs: modules.map(\.id), sizings: sizings, rows: Self.referenceRow(forModuleCount:))
        }
        followSizings()
    }

    // MARK: Reading

    /// The row the layout is edited against: the reference row for its module count.
    public var currentRow: HomeRowMetrics {
        Self.referenceRow(forModuleCount: layout.items.count)
    }

    /// Body width of the expanded island for the modules Home shows now: it hugs
    /// them, their widths in `currentRow` and the gaps between them plus
    /// `margins`, no narrower than the standard width every tab has and no wider
    /// than `bodyWidth(forModuleCount:)`.
    public var expandedWidth: CGFloat {
        let content = Self.contentWidth(of: placedModules(in: currentRow).map(\.width))
        return min(
            max(content + Self.margins, NotchTheme.expandedSize.width),
            Self.bodyWidth(forModuleCount: layout.items.count)
        )
    }

    /// The modules' widths in `currentRow` and the gaps between them.
    public var contentWidth: CGFloat {
        Self.contentWidth(of: layout.resolvedWidths(in: currentRow, sizings: sizings))
    }

    /// The content widths the edges can scale the row to (see `contentWidthRange(of:)`).
    public var contentWidthRange: ClosedRange<CGFloat> {
        contentWidthRange(of: layout)
    }

    /// How far the line after the module at `index` can move now, in points of
    /// `currentRow`, negative toward the leading side; `nil` when there is no
    /// module after it or neither neighbour can give or take width.
    public func boundaryRange(at index: Int) -> ClosedRange<CGFloat>? {
        let (widths, bounds) = widthsAndBounds(of: layout)
        guard index >= 0, index + 1 < widths.count else { return nil }
        let range = HomeLayout.tradeRange(widths, within: bounds, at: index)
        return range.upperBound - range.lowerBound > Self.minimumRoom ? range : nil
    }

    /// Where the module at `index` lands when dragged `translation` points along a
    /// row of modules `widths` wide (see `HomeLayout.reorderDestination`).
    public nonisolated static func reorderDestination(
        widths: [CGFloat],
        spacing: CGFloat,
        index: Int,
        translation: CGFloat
    ) -> Int {
        HomeLayout.reorderDestination(widths: widths, spacing: spacing, index: index, translation: translation)
    }

    public var placements: [Placement] {
        layout.items.compactMap { item in
            module(item.moduleID).map { Placement(module: $0, width: item.width) }
        }
    }

    /// The modules in the layout and their widths in `row`.
    public func placedModules(in row: HomeRowMetrics) -> [PlacedModule] {
        let widths = layout.resolvedWidths(in: row, sizings: sizings)
        return zip(layout.items, widths).compactMap { item, width in
            module(item.moduleID).map { PlacedModule(module: $0, width: width) }
        }
    }

    /// Registered modules not in the layout yet.
    public var modulesNotShown: [NotchHomeModule] {
        modules.filter { module in !layout.items.contains { $0.moduleID == module.id } }
    }

    /// Whether `moduleID` can join the layout now (see `HomeLayout.canAdd`).
    public func canAdd(_ moduleID: String) -> Bool {
        layout.canAdd(moduleID, sizings: sizings, rows: Self.referenceRow(forModuleCount:))
    }

    // MARK: Editing

    public func add(_ moduleID: String) {
        edit { $0.add(moduleID, sizings: sizings, rows: Self.referenceRow(forModuleCount:)) }
    }

    public func remove(at index: Int) {
        edit { $0.remove(at: index, sizings: sizings, rows: Self.referenceRow(forModuleCount:)) }
    }

    public func move(from source: Int, to destination: Int) {
        edit { $0.move(from: source, to: destination) }
    }

    /// Starts a drag on `handle`; `nil` when it can move nothing: no modules, a row
    /// whose content width cannot change, or no boundary there that can move.
    public func beginResize(_ handle: ResizeHandle) -> Resize? {
        guard !layout.items.isEmpty else { return nil }
        switch handle {
        case .leadingEdge, .trailingEdge:
            let range = contentWidthRange
            guard range.upperBound - range.lowerBound > Self.minimumRoom else { return nil }
        case .boundary(let index):
            guard boundaryRange(at: index) != nil else { return nil }
        }
        return Resize(handle: handle, start: layout, translation: 0)
    }

    /// Applies a drag, in a row drawn centered and as wide as its modules (as Home
    /// and the settings preview draw it), so that the dragged handle stays under
    /// the pointer.
    ///
    /// An edge scales the whole row: the row widens or narrows on both sides, so
    /// its content width changes by twice the translation, within
    /// `contentWidthRange`, and the modules scale together in proportion, each
    /// within its bounds (see `HomeLayout.scaled`). A boundary moves by the
    /// translation: the module before it grows by as much as the one after it
    /// shrinks, both within their bounds, and the row keeps its width.
    ///
    /// Every step starts from the layout the drag began with, its range included,
    /// so dragging back restores it. Ignored once the modules changed since the
    /// drag began.
    public func resize(_ resize: Resize) {
        guard resize.start.items.map(\.moduleID) == layout.items.map(\.moduleID) else { return }
        let row = currentRow
        let (startWidths, bounds) = widthsAndBounds(of: resize.start)
        var widths = startWidths
        switch resize.handle {
        case .leadingEdge, .trailingEdge:
            let range = contentWidthRange(of: resize.start)
            let target = min(max(requestedContentWidth(for: resize), range.lowerBound), range.upperBound)
            widths = HomeLayout.scaled(startWidths, within: bounds, toTotal: target - Self.gaps(widths.count))
        case .boundary(let index):
            guard index >= 0, index + 1 < widths.count else { return }
            let range = HomeLayout.tradeRange(startWidths, within: bounds, at: index)
            let shift = min(max(resize.translation, range.lowerBound), range.upperBound)
            widths[index] += shift
            widths[index + 1] -= shift
        }
        edit {
            $0 = resize.start
            for index in $0.items.indices where abs(widths[index] - startWidths[index]) > 1e-6 {
                $0.items[index].width = row.fraction(forWidth: widths[index])
            }
        }
    }

    /// The limit `resize` has reached, if any: for an edge, the end of
    /// `contentWidthRange` (from the layout the drag began with) once the drag asks
    /// for it or past it; for a boundary, the bound of whichever neighbour stops it
    /// once the drag reaches it. `nil` before the drag moves, while it moves back
    /// from a limit, and once the modules changed since it began.
    public func limit(for resize: Resize) -> ResizeLimit? {
        guard resize.translation != 0,
              resize.start.items.map(\.moduleID) == layout.items.map(\.moduleID)
        else { return nil }
        let (widths, bounds) = widthsAndBounds(of: resize.start)
        switch resize.handle {
        case .leadingEdge, .trailingEdge:
            let start = Self.contentWidth(of: widths)
            let requested = requestedContentWidth(for: resize)
            let range = contentWidthRange(of: resize.start)
            if requested > start, requested >= range.upperBound - Self.minimumRoom {
                return .longest(range.upperBound)
            }
            if requested < start, requested <= range.lowerBound + Self.minimumRoom {
                return .shortest(range.lowerBound)
            }
            return nil
        case .boundary(let index):
            guard index >= 0, index + 1 < widths.count else { return nil }
            let range = HomeLayout.tradeRange(widths, within: bounds, at: index)
            let (before, after) = (index, index + 1)
            if resize.translation > 0, resize.translation >= range.upperBound - Self.minimumRoom {
                // The module before grows and the one after shrinks: whichever has
                // less room left is the one that stops.
                return bounds[before].upperBound - widths[before] <= widths[after] - bounds[after].lowerBound
                    ? .widest(index: before, width: bounds[before].upperBound)
                    : .narrowest(index: after, width: bounds[after].lowerBound)
            }
            if resize.translation < 0, resize.translation <= range.lowerBound + Self.minimumRoom {
                return widths[before] - bounds[before].lowerBound <= bounds[after].upperBound - widths[after]
                    ? .narrowest(index: before, width: bounds[before].lowerBound)
                    : .widest(index: after, width: bounds[after].upperBound)
            }
            return nil
        }
    }

    /// The content width an edge drag asks for, before `contentWidthRange` holds it:
    /// the width it began with, plus twice the translation outward.
    private func requestedContentWidth(for resize: Resize) -> CGFloat {
        let start = Self.contentWidth(of: widthsAndBounds(of: resize.start).widths)
        let outward: CGFloat = resize.handle == .leadingEdge ? -1 : 1
        return start + 2 * outward * resize.translation
    }

    /// The content widths `layout` can be scaled to in `currentRow`: no longer than
    /// the row or the modules at their maximums, and no shorter than the modules at
    /// their minimums or the standard width less `margins` (so that the island shows
    /// no more than its margins when the modules could fill it), whichever is longer
    /// but never past the upper end. A layout already shorter than that (saved
    /// before, or left by a removal) may stay as short, so that dragging an edge
    /// inward does not widen it.
    private func contentWidthRange(of layout: HomeLayout) -> ClosedRange<CGFloat> {
        let (widths, bounds) = widthsAndBounds(of: layout)
        guard !widths.isEmpty else { return 0...0 }
        let gaps = Self.gaps(widths.count)
        let upper = min(currentRow.width, bounds.reduce(0) { $0 + $1.upperBound } + gaps)
        let floor = NotchTheme.expandedSize.width - Self.margins
        let lower = min(max(bounds.reduce(0) { $0 + $1.lowerBound } + gaps, floor), upper)
        return min(lower, Self.contentWidth(of: widths))...upper
    }

    /// `layout`'s widths in points of `currentRow` and the widths each module may take there.
    private func widthsAndBounds(of layout: HomeLayout) -> (widths: [CGFloat], bounds: [ClosedRange<CGFloat>]) {
        let sizings = sizings
        let row = currentRow
        return (layout.resolvedWidths(in: row, sizings: sizings), layout.widthBounds(in: row, sizings: sizings))
    }

    private func edit(_ change: (inout HomeLayout) -> Void) {
        var layout = layout
        change(&layout)
        guard layout != self.layout else { return }
        self.layout = layout
        isCustomized = true
        if let data = try? JSONEncoder().encode(layout.items) {
            defaults.set(data, forKey: Self.layoutKey)
        }
    }

    /// Modules `widths` points wide side by side, with the gaps between them.
    private nonisolated static func contentWidth(of widths: [CGFloat]) -> CGFloat {
        widths.reduce(0, +) + gaps(widths.count)
    }

    /// The gaps between `count` modules side by side.
    private nonisolated static func gaps(_ count: Int) -> CGFloat {
        spacing * CGFloat(max(count - 1, 0))
    }

    private var sizings: [String: HomeModuleSizing] {
        Dictionary(modules.map { ($0.id, $0.sizing) }, uniquingKeysWith: { first, _ in first })
    }

    private func module(_ id: String) -> NotchHomeModule? {
        modules.first { $0.id == id }
    }
}
