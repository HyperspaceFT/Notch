import Foundation
import NotchKit
import SwiftUI
import Testing
@testable import HomeFeature

/// The panel's row under a 32-point notch: 456 × 134 points, 10-point gaps.
private let row = HomeRowMetrics(width: 456, height: 134, spacing: 10)
/// `row` for every module count, for the rules that do not depend on the row widening.
private func fixedRows(_ count: Int) -> HomeRowMetrics { row }
/// The panel's rows as the island widens: 520 points for one module, 120 more for
/// the second and the third, 80 more for the fourth, less the 28-point margins on
/// either side.
private func panelRow(_ count: Int) -> HomeRowMetrics {
    HomeRowMetrics(width: [492, 492, 612, 732, 812][min(count, 4)], height: 134, spacing: 10)
}
/// The clock: a square at its narrowest, 184 points at its widest.
private let clock = HomeModuleSizing.resizable(minimum: .height(1), maximum: .points(184))
/// The weather: at least a third of the row, no maximum.
private let weather = HomeModuleSizing.resizable(minimum: .fraction(1.0 / 3))
private let badge = HomeModuleSizing.fixed(.points(100))
private let sizings: [String: HomeModuleSizing] = ["time": clock, "weather": weather, "badge": badge]

/// The share of `row` a module `points` wide takes, its gap included.
private func share(_ points: CGFloat) -> Double {
    Double((points + 10) / 466)
}

private func isClose(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) < 1e-6
}

private func isClose(_ lhs: [CGFloat], _ rhs: [CGFloat]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { abs($0 - $1) < 0.01 }
}

private func isClose(_ lhs: ClosedRange<CGFloat>?, _ rhs: ClosedRange<CGFloat>) -> Bool {
    guard let lhs else { return false }
    return abs(lhs.lowerBound - rhs.lowerBound) < 0.01 && abs(lhs.upperBound - rhs.upperBound) < 0.01
}

struct HomeLayoutTests {
    @Test func standardGivesTheClockItsFullWidthAndTheWeatherTheRest() {
        let layout = HomeLayout.standard(moduleIDs: ["time", "weather"], sizings: sizings, rows: fixedRows)
        #expect(layout.items.map(\.moduleID) == ["time", "weather"])
        #expect(isClose(layout.items[0].width, share(184)))
        #expect(isClose(layout.items[1].width, 1 - share(184)))
        #expect(isClose(layout.resolvedWidths(in: row, sizings: sizings), [184, 262]))
    }

    @Test func standardSkipsModulesThatDoNotFitAndStopsAtFour() {
        var wide = sizings
        wide["half"] = .fixed(.fraction(0.5))
        let layout = HomeLayout.standard(moduleIDs: ["time", "half", "weather"], sizings: wide, rows: fixedRows)
        #expect(layout.items.map(\.moduleID) == ["time", "half"])

        let small = Dictionary(uniqueKeysWithValues: (1...5).map { ("m\($0)", HomeModuleSizing.fixed(.points(50))) })
        let many = HomeLayout.standard(moduleIDs: (1...5).map { "m\($0)" }, sizings: small, rows: fixedRows)
        #expect(many.items.map(\.moduleID) == ["m1", "m2", "m3", "m4"])
    }

    @Test func addedModulesTakeTheFreeSpace() {
        var layout = HomeLayout(items: [.init(moduleID: "time", width: share(184))])
        layout.add("weather", sizings: sizings, rows: fixedRows)
        #expect(layout.items.map(\.moduleID) == ["time", "weather"])
        #expect(isClose(layout.items[1].width, 1 - share(184)))
    }

    @Test func addedModulesNarrowTheOnesBeforeThemInAFullRow() {
        var layout = HomeLayout.standard(moduleIDs: ["time", "weather"], sizings: sizings, rows: fixedRows)
        layout.add("badge", sizings: sizings, rows: fixedRows)
        #expect(layout.items.map(\.moduleID) == ["time", "weather", "badge"])
        #expect(isClose(layout.items[0].width, share(184)))
        #expect(isClose(layout.items[1].width, 1 - share(184) - share(100)))
        #expect(isClose(layout.items[2].width, share(100)))
        #expect(isClose(layout.resolvedWidths(in: row, sizings: sizings), [184, 152, 100]))
    }

    @Test func modulesCanBeAddedOnlyOnceWhileTheirMinimumsFit() {
        var wide = sizings
        wide["half"] = .fixed(.fraction(0.5))
        let layout = HomeLayout.standard(moduleIDs: ["time", "weather"], sizings: wide, rows: fixedRows)
        #expect(!layout.canAdd("time", sizings: wide, rows: fixedRows))
        #expect(!layout.canAdd("unknown", sizings: wide, rows: fixedRows))
        #expect(!layout.canAdd("half", sizings: wide, rows: fixedRows))
        #expect(layout.canAdd("badge", sizings: wide, rows: fixedRows))

        let small = Dictionary(uniqueKeysWithValues: (1...5).map { ("m\($0)", HomeModuleSizing.fixed(.points(50))) })
        var four = HomeLayout()
        for id in ["m1", "m2", "m3", "m4"] {
            four.add(id, sizings: small, rows: fixedRows)
        }
        #expect(four.items.count == HomeLayout.maximumCount)
        #expect(!four.canAdd("m5", sizings: small, rows: fixedRows))
    }

    @Test func fixedModulesHaveOneWidth() {
        #expect(HomeLayout.bounds(of: badge, in: row) == share(100)...share(100))
        let layout = HomeLayout(items: [.init(moduleID: "badge", width: share(100))])
        #expect(layout.widthBounds(in: row, sizings: sizings) == [100...100])
    }

    @Test func modulesMoveAndGo() {
        var layout = HomeLayout.standard(moduleIDs: ["time", "weather"], sizings: sizings, rows: fixedRows)
        layout.move(from: 0, to: 1)
        #expect(layout.items.map(\.moduleID) == ["weather", "time"])
        layout.remove(at: 0, sizings: sizings, rows: fixedRows)
        #expect(layout.items.map(\.moduleID) == ["time"])
        layout.remove(at: 3, sizings: sizings, rows: fixedRows)
        #expect(layout.items.map(\.moduleID) == ["time"])
    }

    @Test func normalizingDropsUnknownAndRepeatedModulesAndFitsTheRest() {
        var layout = HomeLayout(items: [
            .init(moduleID: "gone", width: 0.5),
            .init(moduleID: "weather", width: 0.9),
            .init(moduleID: "weather", width: 0.2),
            .init(moduleID: "time", width: 0.9),
        ])
        layout.normalize(sizings: sizings, rows: fixedRows)
        #expect(layout.items.map(\.moduleID) == ["weather", "time"])
        #expect(isClose(layout.totalWidth, 1))
        // Each gives up space in proportion to its room above its minimum: the
        // clock, first held to its maximum, has 0.107 of room, the weather 0.567.
        let weatherRoom = 0.9 - 1.0 / 3
        let clockRoom = share(184) - share(134)
        let excess = 0.9 + share(184) - 1
        #expect(isClose(layout.items[0].width, 0.9 - excess * weatherRoom / (weatherRoom + clockRoom)))
        #expect(isClose(layout.items[1].width, share(184) - excess * clockRoom / (weatherRoom + clockRoom)))
    }

    @Test func aTallerRowWidensTheSquareClockAndNarrowsTheRest() {
        let layout = HomeLayout(items: [
            .init(moduleID: "time", width: share(134)),
            .init(moduleID: "weather", width: 1 - share(134)),
        ])
        #expect(isClose(layout.resolvedWidths(in: row, sizings: sizings), [134, 312]))

        let taller = HomeRowMetrics(width: 456, height: 150, spacing: 10)
        #expect(isClose(layout.resolvedWidths(in: taller, sizings: sizings), [150, 296]))
        let shorter = HomeRowMetrics(width: 456, height: 120, spacing: 10)
        #expect(isClose(layout.resolvedWidths(in: shorter, sizings: sizings), [134, 312]))
    }

    // MARK: A row that widens with the modules

    @Test func addingAModuleKeepsTheOthersWidthsAndGivesItTheAddedRoom() {
        var layout = HomeLayout(items: [.init(moduleID: "time", width: share(184))])
        layout.add("weather", sizings: sizings, rows: panelRow)
        // The 612-point row: the clock keeps 184 points, the weather takes the rest.
        #expect(isClose(layout.resolvedWidths(in: panelRow(2), sizings: sizings), [184, 418]))

        layout.add("badge", sizings: sizings, rows: panelRow)
        // The 732-point row has 110 points free after a gap; the badge takes its 100.
        #expect(layout.items.map(\.moduleID) == ["time", "weather", "badge"])
        #expect(isClose(layout.resolvedWidths(in: panelRow(3), sizings: sizings), [184, 418, 100]))
    }

    @Test func removingAModuleKeepsTheOthersWidths() {
        let full = HomeLayout(items: [
            .init(moduleID: "time", width: panelRow(3).fraction(forWidth: 184)),
            .init(moduleID: "weather", width: panelRow(3).fraction(forWidth: 418)),
            .init(moduleID: "badge", width: panelRow(3).fraction(forWidth: 100)),
        ])
        var layout = full
        layout.remove(at: 2, sizings: sizings, rows: panelRow)
        #expect(isClose(layout.resolvedWidths(in: panelRow(2), sizings: sizings), [184, 418]))
        layout.remove(at: 0, sizings: sizings, rows: panelRow)
        #expect(layout.items.map(\.moduleID) == ["weather"])
        #expect(isClose(layout.resolvedWidths(in: panelRow(1), sizings: sizings), [418]))

        var middle = full
        middle.remove(at: 1, sizings: sizings, rows: panelRow)
        #expect(middle.items.map(\.moduleID) == ["time", "badge"])
        #expect(isClose(middle.resolvedWidths(in: panelRow(2), sizings: sizings), [184, 100]))
    }

    @Test func canAddMeasuresAgainstTheRowWithTheNewModule() {
        var wide = sizings
        wide["wide"] = .fixed(.points(320))
        let layout = HomeLayout(items: [.init(moduleID: "time", width: share(184))])
        // 320 points do not fit beside the clock's minimum of 134 in today's
        // 456-point row, but they do in the 612-point row the two would share.
        #expect(!layout.canAdd("wide", sizings: wide, rows: fixedRows))
        #expect(layout.canAdd("wide", sizings: wide, rows: panelRow))

        var added = layout
        added.add("wide", sizings: wide, rows: panelRow)
        #expect(added.items.map(\.moduleID) == ["time", "wide"])
        #expect(isClose(added.resolvedWidths(in: panelRow(2), sizings: wide), [184, 320]))
    }

    @Test func standardHoldsAThirdModuleInTheThreeModuleRow() {
        var three = sizings
        three["third"] = .resizable(minimum: .fraction(1.0 / 3))
        let layout = HomeLayout.standard(moduleIDs: ["time", "weather", "third"], sizings: three, rows: panelRow)
        #expect(layout.items.map(\.moduleID) == ["time", "weather", "third"])
        // In the 732-point row a third is (732 + 10) / 3 − 10 points; the clock
        // takes its 184, the third its minimum, and the weather what is left.
        let third: CGFloat = 742.0 / 3 - 10
        #expect(isClose(layout.resolvedWidths(in: panelRow(3), sizings: three), [184, 732 - 20 - 184 - third, third]))
    }

    // MARK: Dragging

    @Test func scalingGrowsTheModulesInProportion() {
        let free: [ClosedRange<CGFloat>] = [0...1000, 0...1000]
        #expect(isClose(HomeLayout.scaled([100, 200], within: free, toTotal: 450), [150, 300]))
        #expect(isClose(HomeLayout.scaled([100, 200], within: free, toTotal: 150), [50, 100]))
        #expect(isClose(HomeLayout.scaled([100, 200], within: free, toTotal: 300), [100, 200]))
    }

    @Test func scalingHoldsAModuleAtItsMaximumWhileTheOthersGrow() {
        // The clock at its 184-point maximum stays; the weather takes all 60 points.
        let bounds: [ClosedRange<CGFloat>] = [134...184, 150...456]
        #expect(isClose(HomeLayout.scaled([184, 300], within: bounds, toTotal: 544), [184, 360]))
        // A fixed module keeps its width.
        let withBadge: [ClosedRange<CGFloat>] = [100...100, 150...456]
        #expect(isClose(HomeLayout.scaled([100, 300], within: withBadge, toTotal: 500), [100, 400]))
    }

    @Test func scalingStopsShrinkingModulesAtTheirMinimum() {
        let bounds: [ClosedRange<CGFloat>] = [134...184, 150...456]
        // In proportion while both are above their minimums: 484 to 464 points.
        let scale: CGFloat = 464.0 / 484
        #expect(isClose(HomeLayout.scaled([184, 300], within: bounds, toTotal: 464), [184 * scale, 300 * scale]))
        // To 334 points the clock would go under 134, so it stops there and the
        // weather gives up the rest.
        #expect(isClose(HomeLayout.scaled([184, 300], within: bounds, toTotal: 334), [134, 200]))
        // Past every minimum, as close as the bounds allow.
        #expect(isClose(HomeLayout.scaled([184, 300], within: bounds, toTotal: 100), [134, 150]))
    }

    @Test func aBoundaryMovesAsFarAsBothNeighboursAllow() {
        let bounds: [ClosedRange<CGFloat>] = [134...184, 150...456]
        // The clock may give 50 points to the weather but take none from it.
        #expect(HomeLayout.tradeRange([184, 300], within: bounds, at: 0) == -50...0)
        // In between, the clock's own bounds stop it first both ways.
        #expect(HomeLayout.tradeRange([150, 300], within: bounds, at: 0) == -16...34)
        // The weather stops it once it nears its minimum.
        #expect(HomeLayout.tradeRange([150, 160], within: bounds, at: 0) == -16...10)
        #expect(HomeLayout.tradeRange([184, 300], within: bounds, at: 1) == 0...0)
        #expect(HomeLayout.tradeRange([184, 300], within: bounds, at: -1) == 0...0)
    }

    @Test func aMovedModuleLandsInTheSlotNearestItsCentre() {
        // At rest the modules start at 0, 110, and 320 points; the first one's
        // centre is at 50. Moved to the second slot it would start at 210 (centre
        // 260), to the third at 270 (centre 320).
        let widths: [CGFloat] = [100, 200, 50]
        #expect(HomeLayout.reorderDestination(widths: widths, spacing: 10, index: 0, translation: 0) == 0)
        // Centre 150: 100 from its own slot, 110 from the second.
        #expect(HomeLayout.reorderDestination(widths: widths, spacing: 10, index: 0, translation: 100) == 0)
        // Centre 170: 90 from the second slot.
        #expect(HomeLayout.reorderDestination(widths: widths, spacing: 10, index: 0, translation: 120) == 1)
        // Centre 300: 20 from the third slot, 40 from the second.
        #expect(HomeLayout.reorderDestination(widths: widths, spacing: 10, index: 0, translation: 250) == 2)
        #expect(HomeLayout.reorderDestination(widths: widths, spacing: 10, index: 0, translation: 1000) == 2)
        // The last one (centre 345) dragged far to the left lands first.
        #expect(HomeLayout.reorderDestination(widths: widths, spacing: 10, index: 2, translation: -400) == 0)
        // Centre 205: the first slot (25) is 180 away, the second (135) 70, its own 140.
        #expect(HomeLayout.reorderDestination(widths: widths, spacing: 10, index: 2, translation: -140) == 1)
        #expect(HomeLayout.reorderDestination(widths: widths, spacing: 10, index: 3, translation: 50) == 3)
    }
}

@MainActor
struct HomeLayoutSettingsTests {
    private let modules = [
        NotchHomeModule(id: "time", title: { "Time" }, symbol: "clock", sizing: clock) { _ in AnyView(EmptyView()) },
        NotchHomeModule(id: "weather", title: { "Weather" }, symbol: "cloud", sizing: weather) { _ in AnyView(EmptyView()) },
    ]

    @Test func bodyWidthGrowsLessForTheFourthModule() {
        let widths = (0...5).map { HomeLayoutSettings.bodyWidth(forModuleCount: $0) }
        #expect(widths == [520, 520, 640, 760, 840, 840])
        #expect(HomeLayoutSettings.extraWidths.count == HomeLayoutSettings.maximumModuleCount - 1)
    }

    @Test func referenceRowsAreThePanelsRows() {
        for count in 0...5 {
            #expect(HomeLayoutSettings.referenceRow(forModuleCount: count) == panelRow(count))
        }
    }

    @Test func expandedWidthFollowsTheModulesShown() throws {
        let suite = "HomeLayoutSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = HomeLayoutSettings(defaults: defaults)
        settings.register(modules)
        // The standard layout fills the 612-point row, so the island is at its widest for two.
        #expect(settings.expandedWidth == 640)
        #expect(settings.currentRow == panelRow(2))

        settings.remove(at: 1)
        // The clock alone, 184 points and the margins, is under the standard width.
        #expect(settings.expandedWidth == 520)
        #expect(settings.currentRow == panelRow(1))
        // The clock keeps its width in the narrower row.
        #expect(isClose(settings.placedModules(in: panelRow(1)).map(\.width), [184]))

        settings.remove(at: 0)
        #expect(settings.expandedWidth == 520)
    }

    @Test func expandedWidthHugsTheModules() throws {
        let suite = "HomeLayoutSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(HomeLayoutSettings.margins == 28)
        // The clock's 184 points, a gap, 300 points of weather, and the margins.
        let settings = try saved(defaults, [("time", 184), ("weather", 300)])
        #expect(abs(settings.contentWidth - (184 + 10 + 300)) < 0.01)
        #expect(abs(settings.expandedWidth - (184 + 10 + 300 + 28)) < 0.01)
        // 134 and 200 points come to less than the standard width, which the island keeps.
        let short = try saved(defaults, [("time", 134), ("weather", 200)])
        #expect(short.expandedWidth == 520)
        // A full row reaches the widest island for two modules and no more.
        let full = try saved(defaults, [("time", 184), ("weather", 418)])
        #expect(abs(full.expandedWidth - HomeLayoutSettings.bodyWidth(forModuleCount: 2)) < 0.01)
    }

    /// Settings showing `widths`, in points of the reference row for their count,
    /// as if saved before.
    private func saved(
        _ defaults: UserDefaults,
        _ widths: [(String, CGFloat)],
        modules: [NotchHomeModule]? = nil
    ) throws -> HomeLayoutSettings {
        let row = panelRow(widths.count)
        let items = widths.map { HomeLayout.Item(moduleID: $0.0, width: row.fraction(forWidth: $0.1)) }
        defaults.set(try JSONEncoder().encode(items), forKey: HomeLayoutSettings.layoutKey)
        let settings = HomeLayoutSettings(defaults: defaults)
        settings.register(modules ?? self.modules)
        return settings
    }

    private func widths(_ settings: HomeLayoutSettings) -> [CGFloat] {
        settings.placedModules(in: settings.currentRow).map(\.width)
    }

    private let badgeModule = NotchHomeModule(id: "badge", title: { "Badge" }, symbol: "star", sizing: badge) { _ in
        AnyView(EmptyView())
    }

    @Test func theEdgesReachFromTheStandardWidthToTheFullRow() throws {
        let suite = "HomeLayoutSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // Two modules in the 612-point row: the minimums (134, a third of 622 less
        // a gap, and the gap) come to 341 points, under the 492 points of the
        // standard width less the margins, which is the shortest.
        let settings = try saved(defaults, [("time", 184), ("weather", 300)])
        #expect(settings.contentWidthRange == 492...612)

        // With a fixed badge, the modules at their widest come to 294 points:
        // there is nothing to scale.
        let atMaximum = try saved(defaults, [("time", 184), ("badge", 100)], modules: modules + [badgeModule])
        #expect(isClose(atMaximum.contentWidthRange, 294...294))
        #expect(atMaximum.beginResize(.trailingEdge) == nil)
        #expect(atMaximum.beginResize(.leadingEdge) == nil)

        // A row already shorter than the shortest may stay as short.
        let short = try saved(defaults, [("time", 134), ("badge", 100)], modules: modules + [badgeModule])
        #expect(isClose(short.contentWidthRange, 244...294))
        var resize = try #require(short.beginResize(.trailingEdge))
        resize.translation = 10
        short.resize(resize)
        #expect(isClose(widths(short), [154, 100]))

        defaults.removeObject(forKey: HomeLayoutSettings.layoutKey)
        let empty = HomeLayoutSettings(defaults: defaults)
        #expect(empty.contentWidthRange == 0...0)
        #expect(empty.beginResize(.trailingEdge) == nil)
    }

    @Test func draggingAnEdgeScalesTheRowByTwiceTheTranslation() throws {
        let suite = "HomeLayoutSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = try saved(defaults, [("time", 184), ("weather", 340)])
        var trailing = try #require(settings.beginResize(.trailingEdge))
        // The centered row widens on both sides: 10 points out ask for 20 more.
        // The clock is at its maximum, so the weather takes them.
        trailing.translation = 10
        settings.resize(trailing)
        #expect(isClose(widths(settings), [184, 360]))
        #expect(abs(settings.contentWidth - 554) < 0.01)
        // Inward, both narrow in proportion: 534 to 514 points, 524 to 504 of modules.
        trailing.translation = -10
        settings.resize(trailing)
        let scale: CGFloat = 504.0 / 524
        #expect(isClose(widths(settings), [184 * scale, 340 * scale]))

        // The leading edge mirrors it: out is to the left.
        var leading = try #require(settings.beginResize(.leadingEdge))
        let start = widths(settings)
        leading.translation = -10
        settings.resize(leading)
        #expect(abs(settings.contentWidth - (start.reduce(0, +) + 10 + 20)) < 0.01)
        leading.translation = 5
        settings.resize(leading)
        #expect(abs(settings.contentWidth - (start.reduce(0, +) + 10 - 10)) < 0.01)
    }

    @Test func draggingAnEdgeStopsAtTheEndsOfItsRange() throws {
        let suite = "HomeLayoutSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = try saved(defaults, [("time", 184), ("weather", 300)])
        var resize = try #require(settings.beginResize(.trailingEdge))
        // The full 612-point row, and no further.
        resize.translation = 100
        settings.resize(resize)
        #expect(isClose(widths(settings), [184, 418]))
        // 492 points, the standard width less the margins, and no shorter.
        resize.translation = -100
        settings.resize(resize)
        #expect(abs(settings.contentWidth - 492) < 0.01)
        let scale: CGFloat = 482.0 / 484
        #expect(isClose(widths(settings), [184 * scale, 300 * scale]))
    }

    @Test func draggingAnEdgeBackRestoresTheLayoutItBeganWith() throws {
        let suite = "HomeLayoutSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = try saved(defaults, [("time", 184), ("weather", 300)])
        let before = settings.layout
        var resize = try #require(settings.beginResize(.trailingEdge))
        resize.translation = -100
        settings.resize(resize)
        resize.translation = 60
        settings.resize(resize)
        resize.translation = 0
        settings.resize(resize)
        #expect(settings.layout == before)
    }

    @Test func anEdgeDragTakesItsRangeFromTheLayoutItBeganWith() throws {
        let suite = "HomeLayoutSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // 344 points, under the 492-point floor, so the range starts at 344.
        let settings = try saved(defaults, [("time", 134), ("weather", 200)])
        #expect(isClose(settings.contentWidthRange, 344...612))
        var resize = try #require(settings.beginResize(.trailingEdge))
        resize.translation = 20
        settings.resize(resize)
        #expect(abs(settings.contentWidth - 384) < 0.01)
        // The layout now starts the range at 384, but the drag keeps its own.
        resize.translation = 5
        settings.resize(resize)
        #expect(abs(settings.contentWidth - 354) < 0.01)
        resize.translation = -10
        settings.resize(resize)
        #expect(isClose(widths(settings), [134, 200]))
        let limit = try #require(settings.limit(for: resize))
        guard case .shortest(let shortest) = limit else {
            Issue.record("Expected the shortest limit, got \(limit)")
            return
        }
        #expect(abs(shortest - 344) < 0.01)
    }

    @Test func draggingABoundaryTradesWidthBetweenItsNeighbours() throws {
        let suite = "HomeLayoutSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = try saved(defaults, [("weather", 300), ("time", 184)])
        #expect(isClose(settings.boundaryRange(at: 0), 0...50))
        var resize = try #require(settings.beginResize(.boundary(0)))
        // The weather grows by the translation, the clock narrows as much.
        resize.translation = 30
        settings.resize(resize)
        #expect(isClose(widths(settings), [330, 154]))
        #expect(abs(settings.contentWidth - 494) < 0.01)
        // Until the clock reaches its minimum.
        resize.translation = 80
        settings.resize(resize)
        #expect(isClose(widths(settings), [350, 134]))
        // The clock at its maximum gives nothing the other way.
        resize.translation = -20
        settings.resize(resize)
        #expect(isClose(widths(settings), [300, 184]))
        #expect(abs(settings.contentWidth - 494) < 0.01)
    }

    @Test func draggingABoundaryBackRestoresTheLayoutItBeganWith() throws {
        let suite = "HomeLayoutSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = try saved(defaults, [("time", 160), ("weather", 300)])
        let before = settings.layout
        var resize = try #require(settings.beginResize(.boundary(0)))
        resize.translation = -100
        settings.resize(resize)
        #expect(isClose(widths(settings), [134, 326]))
        resize.translation = 0
        settings.resize(resize)
        #expect(settings.layout == before)
    }

    @Test func boundariesThatCannotMoveHaveNoResize() throws {
        let suite = "HomeLayoutSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = try saved(
            defaults,
            [("time", 150), ("badge", 100), ("weather", 300)],
            modules: modules + [badgeModule]
        )
        // The fixed badge can neither give nor take, so neither boundary beside it moves.
        #expect(settings.boundaryRange(at: 0) == nil)
        #expect(settings.beginResize(.boundary(0)) == nil)
        #expect(settings.beginResize(.boundary(1)) == nil)
        #expect(settings.beginResize(.boundary(2)) == nil)
        #expect(settings.beginResize(.boundary(-1)) == nil)
    }

    @Test func limitsNameTheEndOfTheRangeOrTheModuleThatStops() throws {
        let suite = "HomeLayoutSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // The 534 points of content: 39 points out ask for exactly the 612-point
        // row, 38 for 2 points less; 21 points in ask for exactly the 492 points
        // of the standard width less the margins, 20 for 2 points more.
        let settings = try saved(defaults, [("time", 184), ("weather", 340)])
        var edge = try #require(settings.beginResize(.trailingEdge))
        #expect(settings.limit(for: edge) == nil)
        edge.translation = 38
        #expect(settings.limit(for: edge) == nil)
        edge.translation = 39
        #expect(settings.limit(for: edge) == .longest(612))
        edge.translation = 100
        #expect(settings.limit(for: edge) == .longest(612))
        edge.translation = -10
        #expect(settings.limit(for: edge) == nil)
        edge.translation = -20
        #expect(settings.limit(for: edge) == nil)
        edge.translation = -21
        #expect(settings.limit(for: edge) == .shortest(492))
        edge.translation = -100
        #expect(settings.limit(for: edge) == .shortest(492))
        // The leading edge asks for more by going left.
        var leading = try #require(settings.beginResize(.leadingEdge))
        leading.translation = -100
        #expect(settings.limit(for: leading) == .longest(612))

        // The clock before the weather, at its maximum: dragging the boundary right
        // holds it there; left, it stops at its minimum.
        var boundary = try #require(settings.beginResize(.boundary(0)))
        boundary.translation = 10
        #expect(settings.limit(for: boundary) == .widest(index: 0, width: 184))
        boundary.translation = -20
        #expect(settings.limit(for: boundary) == nil)
        boundary.translation = -80
        #expect(settings.limit(for: boundary) == .narrowest(index: 0, width: 134))

        // The weather before the clock: the clock stops the boundary both ways.
        let swapped = try saved(defaults, [("weather", 340), ("time", 184)])
        var other = try #require(swapped.beginResize(.boundary(0)))
        other.translation = 80
        #expect(swapped.limit(for: other) == .narrowest(index: 1, width: 134))
        other.translation = -5
        #expect(swapped.limit(for: other) == .widest(index: 1, width: 184))
    }

    @Test func resizingIsIgnoredOnceTheModulesChanged() throws {
        let suite = "HomeLayoutSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = HomeLayoutSettings(defaults: defaults)
        settings.register(modules + [badgeModule])
        #expect(settings.placements.map(\.id) == ["time", "weather", "badge"])

        var edge = try #require(settings.beginResize(.leadingEdge))
        var boundary = try #require(settings.beginResize(.boundary(0)))
        settings.remove(at: 2)
        let layout = settings.layout
        edge.translation = 20
        settings.resize(edge)
        boundary.translation = -20
        settings.resize(boundary)
        #expect(settings.placements.map(\.id) == ["time", "weather"])
        #expect(settings.layout == layout)
        #expect(settings.limit(for: edge) == nil)
    }

    @Test func followsTheStandardLayoutUntilChangedThenKeepsTheChange() throws {
        let suite = "HomeLayoutSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = HomeLayoutSettings(defaults: defaults)
        settings.register(modules)
        #expect(settings.placements.map(\.id) == ["time", "weather"])
        #expect(defaults.data(forKey: HomeLayoutSettings.layoutKey) == nil)

        settings.move(from: 0, to: 1)
        let reloaded = HomeLayoutSettings(defaults: defaults)
        reloaded.register(modules)
        #expect(reloaded.placements.map(\.id) == ["weather", "time"])

        reloaded.remove(at: 0)
        reloaded.remove(at: 0)
        let emptied = HomeLayoutSettings(defaults: defaults)
        emptied.register(modules)
        #expect(emptied.placements.isEmpty)
        #expect(emptied.modulesNotShown.map(\.id) == ["time", "weather"])
    }
}

/// A module whose width follows its own state passes the difference to its
/// neighbours. Shares here are fractions of `row`, so the expected values are
/// plain sums: with neighbours on both sides each gives or takes half, with one
/// it gives or takes all, each within its bounds.
struct HomeLayoutFollowFixedWidthsTests {
    /// A resizable neighbour that may take 0.1 to 0.8 of the row.
    private let neighbour = HomeModuleSizing.resizable(minimum: .fraction(0.1), maximum: .fraction(0.8))

    private func layout(_ items: [(String, Double)]) -> HomeLayout {
        HomeLayout(items: items.map { HomeLayout.Item(moduleID: $0.0, width: $0.1) })
    }

    private func shares(_ layout: HomeLayout) -> [Double] {
        layout.items.map(\.width)
    }

    private func expectShares(_ layout: HomeLayout, _ expected: [Double]) {
        #expect(layout.items.count == expected.count)
        for (actual, value) in zip(shares(layout), expected) {
            #expect(isClose(actual, value), "\(shares(layout)) ≠ \(expected)")
        }
    }

    @Test func oneNeighbourTakesTheWholeDifference() {
        var growing = layout([("usage", 0.2), ("b", 0.5)])
        growing.followFixedWidths(sizings: ["usage": .fixed(.fraction(0.3)), "b": neighbour], rows: fixedRows)
        expectShares(growing, [0.3, 0.4])

        var narrowing = layout([("a", 0.5), ("usage", 0.2)])
        narrowing.followFixedWidths(sizings: ["usage": .fixed(.fraction(0.1)), "a": neighbour], rows: fixedRows)
        expectShares(narrowing, [0.6, 0.1])
    }

    @Test func twoNeighboursShareTheDifferenceEqually() {
        let modules = ["a": neighbour, "b": neighbour]
        var growing = layout([("a", 0.3), ("usage", 0.2), ("b", 0.3)])
        growing.followFixedWidths(sizings: modules.merging(["usage": .fixed(.fraction(0.3))]) { $1 }, rows: fixedRows)
        expectShares(growing, [0.25, 0.3, 0.25])

        var narrowing = layout([("a", 0.3), ("usage", 0.2), ("b", 0.3)])
        narrowing.followFixedWidths(sizings: modules.merging(["usage": .fixed(.fraction(0.1))]) { $1 }, rows: fixedRows)
        expectShares(narrowing, [0.35, 0.1, 0.35])
    }

    @Test func aNeighbourAtItsMinimumPassesTheRestToTheOther() {
        // 0.2 more: each is asked for 0.1; a can give only 0.02, so b gives 0.18.
        var layout = layout([("a", 0.12), ("usage", 0.2), ("b", 0.5)])
        layout.followFixedWidths(sizings: ["a": neighbour, "b": neighbour, "usage": .fixed(.fraction(0.4))], rows: fixedRows)
        expectShares(layout, [0.1, 0.4, 0.32])
    }

    @Test func withBothNeighboursAtTheirMinimumTheFreeSpaceThenTheFartherModuleGive() {
        // 0.4 more; the neighbours have nothing to give, the row has 0.3 free,
        // and x, two places away, gives the last 0.1.
        var layout = layout([("x", 0.3), ("a", 0.1), ("usage", 0.2), ("b", 0.1)])
        layout.followFixedWidths(
            sizings: ["x": neighbour, "a": neighbour, "b": neighbour, "usage": .fixed(.fraction(0.6))],
            rows: fixedRows
        )
        expectShares(layout, [0.2, 0.1, 0.6, 0.1])
    }

    @Test func freeSpaceAloneCoversWhatTheNeighboursCannotGive() {
        var layout = layout([("x", 0.3), ("a", 0.1), ("usage", 0.2)])
        layout.followFixedWidths(sizings: ["x": neighbour, "a": neighbour, "usage": .fixed(.fraction(0.4))], rows: fixedRows)
        expectShares(layout, [0.3, 0.1, 0.4])
    }

    @Test func narrowingBesideNeighboursAtTheirMaximumLeavesFreeSpace() {
        var layout = layout([("a", 0.8), ("usage", 0.2)])
        layout.followFixedWidths(sizings: ["a": neighbour, "usage": .fixed(.fraction(0.1))], rows: fixedRows)
        expectShares(layout, [0.8, 0.1])
        #expect(isClose(layout.totalWidth, 0.9))
    }

    @Test func aFixedNeighbourPassesEverythingToTheOtherSide() {
        var layout = layout([("badge", 0.2), ("usage", 0.2), ("b", 0.5)])
        layout.followFixedWidths(
            sizings: ["badge": .fixed(.fraction(0.2)), "usage": .fixed(.fraction(0.3)), "b": neighbour],
            rows: fixedRows
        )
        expectShares(layout, [0.2, 0.3, 0.4])
    }

    @Test func unchangedSharesLeaveTheLayoutAlone() {
        let original = layout([("a", 0.3), ("usage", 0.2), ("b", 0.3)])
        var layout = original
        layout.followFixedWidths(sizings: ["a": neighbour, "b": neighbour, "usage": .fixed(.fraction(0.2))], rows: fixedRows)
        #expect(layout == original)
        // Resizable modules away from their bounds start nothing either.
        var resizable = self.layout([("a", 0.25), ("b", 0.45)])
        resizable.followFixedWidths(sizings: ["a": neighbour, "b": neighbour], rows: fixedRows)
        expectShares(resizable, [0.25, 0.45])
    }

    @Test func aLoneModuleJustTakesItsWidth() {
        var layout = layout([("usage", 0.2)])
        layout.followFixedWidths(sizings: ["usage": .fixed(.fraction(0.4))], rows: fixedRows)
        expectShares(layout, [0.4])
    }
}
