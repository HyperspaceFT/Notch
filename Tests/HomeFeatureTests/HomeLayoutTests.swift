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
/// each further one, less the 32-point margins on either side.
private func panelRow(_ count: Int) -> HomeRowMetrics {
    HomeRowMetrics(width: [456, 456, 576, 696, 816][min(count, 4)], height: 134, spacing: 10)
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

    @Test func shrinkingLeavesTheSpaceFree() {
        var layout = HomeLayout.standard(moduleIDs: ["time", "weather"], sizings: sizings, rows: fixedRows)
        layout.setWidth(0, at: 0, sizings: sizings, row: row)
        #expect(isClose(layout.items[0].width, share(134)))
        #expect(isClose(layout.items[1].width, 1 - share(184)))
        #expect(isClose(layout.resolvedWidths(in: row, sizings: sizings), [134, 262]))
    }

    @Test func growingTakesTheFreeSpaceThenNarrowsTheOtherModules() {
        var layout = HomeLayout.standard(moduleIDs: ["time", "weather"], sizings: sizings, rows: fixedRows)
        // The last module grows into the one before it, which stops at its minimum.
        layout.setWidth(1, at: 1, sizings: sizings, row: row)
        #expect(isClose(layout.items[0].width, share(134)))
        #expect(isClose(layout.items[1].width, 1 - share(134)))
        // The first one grows into the one after it, up to its own maximum.
        layout.setWidth(1, at: 0, sizings: sizings, row: row)
        #expect(isClose(layout.items[0].width, share(184)))
        #expect(isClose(layout.items[1].width, 1 - share(184)))
    }

    @Test func widthRangeEndsWhereTheOthersReachTheirMinimum() throws {
        var layout = HomeLayout.standard(moduleIDs: ["time", "weather"], sizings: sizings, rows: fixedRows)
        let clockRange = try #require(layout.widthRange(at: 0, sizings: sizings, row: row))
        #expect(isClose(clockRange.lowerBound, share(134)))
        #expect(isClose(clockRange.upperBound, share(184)))
        let weatherRange = try #require(layout.widthRange(at: 1, sizings: sizings, row: row))
        #expect(isClose(weatherRange.lowerBound, 1.0 / 3))
        #expect(isClose(weatherRange.upperBound, 1 - share(134)))
        // Every value in the range is reached, so a slider over it stays in step.
        layout.setWidth(weatherRange.upperBound, at: 1, sizings: sizings, row: row)
        #expect(isClose(layout.items[1].width, weatherRange.upperBound))
        #expect(layout.widthRange(at: 2, sizings: sizings, row: row) == nil)

        let full = HomeLayout(items: [
            .init(moduleID: "weather", width: 1.0 / 3),
            .init(moduleID: "half", width: 0.5),
        ])
        var wide = sizings
        wide["half"] = .resizable(minimum: .fraction(2.0 / 3))
        let noRoom = try #require(full.widthRange(at: 0, sizings: wide, row: row))
        #expect(isClose(noRoom.lowerBound, 1.0 / 3) && isClose(noRoom.upperBound, 1.0 / 3))
    }

    @Test func growingStopsWhenTheOthersAreAtTheirMinimum() {
        var layout = HomeLayout(items: [
            .init(moduleID: "weather", width: 1.0 / 3),
            .init(moduleID: "time", width: share(184)),
        ])
        layout.setWidth(1, at: 0, sizings: sizings, row: row)
        #expect(isClose(layout.items[0].width, 1 - share(134)))
        #expect(isClose(layout.items[1].width, share(134)))
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

    @Test func fixedModulesKeepTheirWidth() {
        var layout = HomeLayout(items: [.init(moduleID: "badge", width: share(100))])
        layout.setWidth(0.8, at: 0, sizings: sizings, row: row)
        #expect(isClose(layout.items[0].width, share(100)))
        #expect(HomeLayout.bounds(of: badge, in: row) == share(100)...share(100))
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
        var layout = HomeLayout.standard(moduleIDs: ["time", "weather"], sizings: sizings, rows: fixedRows)
        layout.setWidth(0, at: 0, sizings: sizings, row: row)
        layout.setWidth(1, at: 1, sizings: sizings, row: row)
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
        // The 576-point row: the clock keeps 184 points, the weather takes the rest.
        #expect(isClose(layout.resolvedWidths(in: panelRow(2), sizings: sizings), [184, 382]))

        layout.add("badge", sizings: sizings, rows: panelRow)
        // The 696-point row has 110 points free after a gap; the badge takes its 100.
        #expect(layout.items.map(\.moduleID) == ["time", "weather", "badge"])
        #expect(isClose(layout.resolvedWidths(in: panelRow(3), sizings: sizings), [184, 382, 100]))
    }

    @Test func removingAModuleKeepsTheOthersWidths() {
        let full = HomeLayout(items: [
            .init(moduleID: "time", width: panelRow(3).fraction(forWidth: 184)),
            .init(moduleID: "weather", width: panelRow(3).fraction(forWidth: 382)),
            .init(moduleID: "badge", width: panelRow(3).fraction(forWidth: 100)),
        ])
        var layout = full
        layout.remove(at: 2, sizings: sizings, rows: panelRow)
        #expect(isClose(layout.resolvedWidths(in: panelRow(2), sizings: sizings), [184, 382]))
        layout.remove(at: 0, sizings: sizings, rows: panelRow)
        #expect(layout.items.map(\.moduleID) == ["weather"])
        #expect(isClose(layout.resolvedWidths(in: panelRow(1), sizings: sizings), [382]))

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
        // 456-point row, but they do in the 576-point row the two would share.
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
        // In the 696-point row a third is (696 + 10) / 3 − 10 points; the clock
        // takes its 184, the third its minimum, and the weather what is left.
        let third: CGFloat = 706.0 / 3 - 10
        #expect(isClose(layout.resolvedWidths(in: panelRow(3), sizings: three), [184, 696 - 20 - 184 - third, third]))
    }
}

struct TimeModuleTests {
    @Test func isASquareAtItsNarrowestAndFitsTheSecondsAtItsWidest() {
        #expect(TimeModule.sizing.minimumWidth(in: row) == 134)
        #expect(TimeModule.sizing.maximumWidth(in: row) == 184)
        #expect(TimeModule.sizing.minimumWidth(in: HomeRowMetrics(width: 456, height: 128, spacing: 10)) == 128)
    }

    @Test func showsSecondsFromTheThreshold() {
        #expect(!TimeModule.showsSeconds(width: 134))
        #expect(!TimeModule.showsSeconds(width: 159.9))
        #expect(TimeModule.showsSeconds(width: 160))
        #expect(TimeModule.showsSeconds(width: 184))
    }
}

@MainActor
struct HomeLayoutSettingsTests {
    private let modules = [
        NotchHomeModule(id: "time", title: { "Time" }, symbol: "clock", sizing: clock) { _ in AnyView(EmptyView()) },
        NotchHomeModule(id: "weather", title: { "Weather" }, symbol: "cloud", sizing: weather) { _ in AnyView(EmptyView()) },
    ]

    @Test func bodyWidthGrowsByAHundredAndTwentyPointsPerModule() {
        let widths = (0...5).map { HomeLayoutSettings.bodyWidth(forModuleCount: $0) }
        #expect(widths == [520, 520, 640, 760, 880, 880])
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
        #expect(settings.expandedWidth == 640)
        #expect(settings.currentRow == panelRow(2))

        settings.remove(at: 1)
        #expect(settings.expandedWidth == 520)
        #expect(settings.currentRow == panelRow(1))
        // The clock keeps its width in the narrower row.
        #expect(isClose(settings.placedModules(in: panelRow(1)).map(\.width), [184]))

        settings.remove(at: 0)
        #expect(settings.expandedWidth == 520)
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
