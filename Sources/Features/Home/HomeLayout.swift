import CoreGraphics
import NotchKit

/// What Home shows: which modules, in which order, and how wide each one is.
///
/// Widths are shares of the row (see `HomeRowMetrics.fraction(forWidth:)`), and
/// the layout keeps them inside each module's bounds with a total of at most 1,
/// measured against the row it is edited for. That row widens with the number of
/// modules, so editing takes `rows`, the row for a given count; a module joining
/// or leaving keeps the others at their width in points. Home resolves the shares
/// against the row it actually gets with `resolvedWidths(in:sizings:)`. Free
/// space in the row is not drawn: the island hugs its modules, up to the row's
/// width (see `HomeLayoutSettings.expandedWidth`).
struct HomeLayout: Equatable, Sendable {
    struct Item: Equatable, Codable, Sendable {
        var moduleID: String
        /// Share of the row, the gap after the module included.
        var width: Double
    }

    /// The most modules Home's row holds.
    static let maximumCount = 4
    /// Slack for rounding when shares are added up.
    private static let tolerance = 1e-9

    var items: [Item] = []

    var totalWidth: Double {
        items.reduce(0) { $0 + $1.width }
    }

    /// The shares a module may take in `row`: one value for a fixed module.
    static func bounds(of sizing: HomeModuleSizing, in row: HomeRowMetrics) -> ClosedRange<Double> {
        let minimum = row.fraction(forWidth: sizing.minimumWidth(in: row))
        let maximum = row.fraction(forWidth: sizing.maximumWidth(in: row))
        return minimum...max(minimum, maximum)
    }

    /// Every module in `moduleIDs` order that fits in the row it would join, each
    /// at its minimum, then grown one after another up to its maximum until the
    /// row for the final count is full. With a clock and the weather, the clock
    /// gets its full width and the weather the rest.
    static func standard(
        moduleIDs: [String],
        sizings: [String: HomeModuleSizing],
        rows: (Int) -> HomeRowMetrics
    ) -> HomeLayout {
        var layout = HomeLayout()
        for id in moduleIDs where layout.canAdd(id, sizings: sizings, rows: rows) {
            layout.items.append(Item(moduleID: id, width: 0))
        }
        let row = rows(layout.items.count)
        for index in layout.items.indices {
            guard let sizing = sizings[layout.items[index].moduleID] else { continue }
            layout.items[index].width = bounds(of: sizing, in: row).lowerBound
        }
        for index in layout.items.indices {
            guard let sizing = sizings[layout.items[index].moduleID] else { continue }
            let free = 1 - layout.totalWidth
            guard free > tolerance else { break }
            let upper = bounds(of: sizing, in: row).upperBound
            layout.items[index].width = min(upper, layout.items[index].width + free)
        }
        return layout
    }

    // MARK: Editing

    /// Whether `moduleID` can join: it is known and not shown yet, the row has a
    /// free place, and every module still fits at its minimum in the row the
    /// layout would have with it.
    func canAdd(_ moduleID: String, sizings: [String: HomeModuleSizing], rows: (Int) -> HomeRowMetrics) -> Bool {
        guard items.count < Self.maximumCount,
              !items.contains(where: { $0.moduleID == moduleID }),
              let sizing = sizings[moduleID]
        else { return false }
        let row = rows(items.count + 1)
        let minimums = items.reduce(Self.bounds(of: sizing, in: row).lowerBound) { total, item in
            total + (sizings[item.moduleID].map { Self.bounds(of: $0, in: row).lowerBound } ?? 0)
        }
        return minimums <= 1 + Self.tolerance
    }

    /// Appends `moduleID` at the end of the row, which widens for it. The others
    /// keep their width in points, within their bounds in the wider row; the
    /// newcomer takes the free space, within its bounds; when that is less than
    /// its minimum, the modules before it give up the difference, the nearest one
    /// first.
    mutating func add(_ moduleID: String, sizings: [String: HomeModuleSizing], rows: (Int) -> HomeRowMetrics) {
        guard canAdd(moduleID, sizings: sizings, rows: rows), let sizing = sizings[moduleID] else { return }
        let row = rows(items.count + 1)
        refit(from: rows(items.count), to: row)
        for index in items.indices {
            guard let sizing = sizings[items[index].moduleID] else { continue }
            let bounds = Self.bounds(of: sizing, in: row)
            items[index].width = min(max(items[index].width, bounds.lowerBound), bounds.upperBound)
        }
        let bounds = Self.bounds(of: sizing, in: row)
        let width = min(max(1 - totalWidth, bounds.lowerBound), bounds.upperBound)
        let excess = totalWidth + width - 1
        if excess > Self.tolerance {
            shrink(by: excess, order: Array(items.indices.reversed()), sizings: sizings, row: row)
        }
        items.append(Item(moduleID: moduleID, width: width))
    }

    /// Removes the module at `index`. The row narrows, and the others keep their
    /// width in points while they fit (see `normalize`); the space left over stays free.
    mutating func remove(at index: Int, sizings: [String: HomeModuleSizing], rows: (Int) -> HomeRowMetrics) {
        guard items.indices.contains(index) else { return }
        let row = rows(items.count)
        items.remove(at: index)
        refit(from: row, to: rows(items.count))
        normalize(sizings: sizings, rows: rows)
    }

    /// Moves the module at `source` so that it ends up at `destination`.
    mutating func move(from source: Int, to destination: Int) {
        guard items.indices.contains(source), items.indices.contains(destination) else { return }
        items.insert(items.remove(at: source), at: destination)
    }

    /// Turns the shares measured against `old` into shares of `new` that keep each
    /// module's width in points.
    private mutating func refit(from old: HomeRowMetrics, to new: HomeRowMetrics) {
        guard old != new else { return }
        for index in items.indices {
            items[index].width = new.fraction(forWidth: old.width(forFraction: items[index].width))
        }
    }

    /// Narrows the modules at `indices`, in that order, each down to its minimum,
    /// until `amount` is taken. Returns what could not be taken.
    @discardableResult
    private mutating func shrink(
        by amount: Double,
        order indices: [Int],
        sizings: [String: HomeModuleSizing],
        row: HomeRowMetrics
    ) -> Double {
        var left = amount
        for index in indices where left > Self.tolerance {
            guard let sizing = sizings[items[index].moduleID] else { continue }
            let minimum = Self.bounds(of: sizing, in: row).lowerBound
            let taken = min(left, max(items[index].width - minimum, 0))
            items[index].width -= taken
            left -= taken
        }
        return max(left, 0)
    }

    /// Brings a saved layout in line with the modules and the row for its count:
    /// drops unknown and repeated modules and any past the maximum count, keeping
    /// the others' widths in points, moves each width into its bounds, and narrows
    /// modules in proportion to their room above their minimum when the total is
    /// more than the row. Modules at the end are dropped while even the minimums
    /// do not fit.
    mutating func normalize(sizings: [String: HomeModuleSizing], rows: (Int) -> HomeRowMetrics) {
        let savedRow = rows(items.count)
        var seen = Set<String>()
        items = items.filter { sizings[$0.moduleID] != nil && seen.insert($0.moduleID).inserted }
        if items.count > Self.maximumCount {
            items.removeLast(items.count - Self.maximumCount)
        }
        var row = rows(items.count)
        var bounds = items.compactMap { item in sizings[item.moduleID].map { Self.bounds(of: $0, in: row) } }
        while bounds.reduce(0, { $0 + $1.lowerBound }) > 1 + Self.tolerance {
            items.removeLast()
            row = rows(items.count)
            bounds = items.compactMap { item in sizings[item.moduleID].map { Self.bounds(of: $0, in: row) } }
        }
        refit(from: savedRow, to: row)
        for index in items.indices {
            items[index].width = min(max(items[index].width, bounds[index].lowerBound), bounds[index].upperBound)
        }
        let excess = totalWidth - 1
        guard excess > Self.tolerance else { return }
        let room = items.indices.reduce(0) { $0 + items[$1].width - bounds[$1].lowerBound }
        guard room > 0 else { return }
        for index in items.indices {
            let share = (items[index].width - bounds[index].lowerBound) / room
            items[index].width -= excess * share
        }
    }

    // MARK: Drawing

    /// Each module's width in points in `row`, which may differ from the row the
    /// layout was edited for (the panel's height follows the notch). Widths stay
    /// within the modules' bounds in `row`; when they add up to more than the row,
    /// modules narrow in proportion to their room above their minimum, and all of
    /// them in proportion to their width if even the minimums are too wide.
    func resolvedWidths(in row: HomeRowMetrics, sizings: [String: HomeModuleSizing]) -> [CGFloat] {
        let ranges = items.map { item -> ClosedRange<CGFloat> in
            guard let sizing = sizings[item.moduleID] else { return 0...0 }
            return sizing.minimumWidth(in: row)...sizing.maximumWidth(in: row)
        }
        var widths = zip(items, ranges).map { item, range in
            min(max(row.width(forFraction: item.width), range.lowerBound), range.upperBound)
        }
        let gaps = row.spacing * CGFloat(max(widths.count - 1, 0))
        let available = row.width - gaps
        var excess = widths.reduce(0, +) - available
        guard excess > 0.01 else { return widths }

        let room = zip(widths, ranges).reduce(CGFloat(0)) { $0 + $1.0 - $1.1.lowerBound }
        if room > 0 {
            let taken = min(excess, room)
            for index in widths.indices {
                widths[index] -= taken * (widths[index] - ranges[index].lowerBound) / room
            }
            excess -= taken
        }
        let total = widths.reduce(0, +)
        if excess > 0.01, total > 0 {
            let scale = max(available, 0) / total
            widths = widths.map { $0 * scale }
        }
        return widths
    }

    // MARK: Dragging

    /// The widths in points each module may take in `row`, in layout order: one
    /// value for a fixed module, as `resolvedWidths(in:sizings:)` holds them.
    func widthBounds(in row: HomeRowMetrics, sizings: [String: HomeModuleSizing]) -> [ClosedRange<CGFloat>] {
        items.map { item in
            sizings[item.moduleID].map { $0.minimumWidth(in: row)...$0.maximumWidth(in: row) } ?? 0...0
        }
    }

    /// `widths` scaled together so that they add up to `total`: each one becomes
    /// `width × s`, held within its bounds, with the same `s` for all of them. A
    /// module that reaches a bound stays there while the others go on, and a fixed
    /// module keeps its width. When `total` is out of reach, the widths come as
    /// close to it as their bounds allow.
    static func scaled(
        _ widths: [CGFloat],
        within bounds: [ClosedRange<CGFloat>],
        toTotal total: CGFloat
    ) -> [CGFloat] {
        func scaledWidths(by scale: CGFloat) -> [CGFloat] {
            zip(widths, bounds).map { width, bounds in
                min(max(width * scale, bounds.lowerBound), bounds.upperBound)
            }
        }
        guard abs(widths.reduce(0, +) - total) > 1e-9 else { return widths }
        // The sum grows with the scale, from the minimums at 0 to the maximums
        // once every module with a width reaches its own.
        var low: CGFloat = 0
        var high = zip(widths, bounds).reduce(CGFloat(1)) { high, entry in
            entry.0 > 0 ? max(high, entry.1.upperBound / entry.0) : high
        }
        for _ in 0..<64 {
            let middle = (low + high) / 2
            if scaledWidths(by: middle).reduce(0, +) < total {
                low = middle
            } else {
                high = middle
            }
        }
        return scaledWidths(by: (low + high) / 2)
    }

    /// How far the boundary between the modules at `index` and `index + 1` can
    /// move, in points, negative toward the leading side: the module before it
    /// grows by as much as the one after it shrinks, both within their bounds.
    /// `0...0` when there is no such boundary.
    static func tradeRange(_ widths: [CGFloat], within bounds: [ClosedRange<CGFloat>], at index: Int) -> ClosedRange<CGFloat> {
        guard index >= 0, index + 1 < widths.count, widths.count == bounds.count else { return 0...0 }
        let (before, after) = (widths[index], widths[index + 1])
        let (beforeBounds, afterBounds) = (bounds[index], bounds[index + 1])
        let leading = min(before - beforeBounds.lowerBound, afterBounds.upperBound - after)
        let trailing = min(beforeBounds.upperBound - before, after - afterBounds.lowerBound)
        return min(-leading, 0)...max(trailing, 0)
    }

    /// Where the module at `index` lands when dragged `translation` points along a
    /// row of modules `widths` wide with `spacing` between them: the slot whose
    /// centre, with the others closed up around it, is nearest the dragged
    /// module's centre.
    static func reorderDestination(widths: [CGFloat], spacing: CGFloat, index: Int, translation: CGFloat) -> Int {
        guard widths.indices.contains(index) else { return index }
        let width = widths[index]
        let centre = widths[..<index].reduce(0) { $0 + $1 + spacing } + width / 2 + translation
        var others = widths
        others.remove(at: index)
        var best = index
        var bestDistance = CGFloat.infinity
        var leading: CGFloat = 0
        for destination in widths.indices {
            let distance = abs(leading + width / 2 - centre)
            if distance < bestDistance {
                best = destination
                bestDistance = distance
            }
            if others.indices.contains(destination) {
                leading += others[destination] + spacing
            }
        }
        return best
    }
}
