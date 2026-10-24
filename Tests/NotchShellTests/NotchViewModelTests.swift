import CoreGraphics
import Foundation
import NotchKit
import NotchUI
import SwiftUI
import Testing
@testable import NotchShell

@MainActor
struct NotchViewModelTests {
    private let model = NotchViewModel(geometry: NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        safeAreaTop: 32,
        auxiliaryTopLeftArea: CGRect(x: 0, y: 924, width: 640, height: 32),
        auxiliaryTopRightArea: CGRect(x: 830, y: 924, width: 640, height: 32)
    ))

    private func activity(
        _ id: String,
        feature: String = "test",
        priority: NotchActivity.Priority = .normal,
        duration: TimeInterval? = nil
    ) -> NotchActivity {
        NotchActivity(id: id, featureID: feature, priority: priority, duration: duration) {
            EmptyView()
        } trailing: {
            EmptyView()
        }
    }

    @Test func startsCollapsedAtNotchSize() {
        #expect(model.state == .collapsed)
        #expect(model.bodySize == CGSize(width: 190, height: 32))
        #expect(model.islandScreenFrame.maxY == 956)
    }

    @Test func menuGroupsKeepFeatureOrderAndSkipFeaturesWithoutEntries() {
        #expect(model.menuGroups.isEmpty)
        final class TimerState {
            var isRunning = false
        }
        let timer = TimerState()
        model.setMenuSources([
            { [.button("Timer") {}] + (timer.isRunning ? [.divider, .button("Cancel") {}] : []) },
            { [] },
            { [.submenu("Files", symbol: "folder", items: [.button("Clear") {}])] },
        ])
        #expect(model.menuGroups.map { $0.map(\.title) } == [["Timer"], ["Files"]])
        // Read again on every draw, so the entries follow the feature's state.
        timer.isRunning = true
        #expect(model.menuGroups.map { $0.map(\.title) } == [["Timer", "", "Cancel"], ["Files"]])
        model.setMenuSources([])
        #expect(model.menuGroups.isEmpty)
    }

    @Test func activityWingWidthSetsTheIslandWidth() {
        let wingWidth: CGFloat = 38
        model.present(NotchActivity(id: "narrow", featureID: "test", wingWidth: wingWidth) {
            EmptyView()
        } trailing: {
            EmptyView()
        })
        #expect(model.bodySize.width == 190 + wingWidth * 2)

        // A standard activity on top brings the standard width back.
        model.present(activity("wide", priority: .high))
        #expect(model.bodySize.width == 190 + NotchTheme.activityWingWidth * 2)
    }

    @Test func unequalWingsMoveTheIslandSoTheNotchStaysBetweenThem() {
        let leading: CGFloat = 36
        let trailing: CGFloat = 52
        model.present(NotchActivity(id: "timer", featureID: "test", wingWidth: trailing, leadingWingWidth: leading) {
            EmptyView()
        } trailing: {
            EmptyView()
        })
        #expect(model.bodySize.width == 190 + leading + trailing)
        #expect(model.islandOffset == 8)
        // The body (inside the ears) starts the left wing's width left of the notch
        // (640...830) and ends the right wing's width right of it.
        let body = model.islandScreenFrame.insetBy(dx: model.topCornerRadius, dy: 0)
        #expect(body.minX == 640 - leading)
        #expect(body.maxX == 830 + trailing)

        // Hovered, the island grows evenly around where it is.
        model.setHovered(true)
        #expect(model.islandOffset == 8)
        model.setHovered(false)

        // Open, it is centered again.
        model.setExpanded(true)
        #expect(model.islandOffset == 0)
        #expect(model.islandScreenFrame.midX == 735)
        model.setExpanded(false)

        // Equal wings on top center it too.
        model.present(activity("equal", priority: .high))
        #expect(model.islandOffset == 0)
        #expect(model.islandScreenFrame.midX == 735)
    }

    @Test func activityThenExpandThenCollapse() {
        model.present(activity("a"))
        #expect(model.state == .activity)
        #expect(model.bodySize.width == 190 + NotchTheme.activityWingWidth * 2)

        model.setExpanded(true)
        #expect(model.state == .expanded)
        #expect(model.bodySize == NotchTheme.expandedSize)

        // Collapsing returns to the still-queued activity.
        model.setExpanded(false)
        #expect(model.state == .activity)

        model.dismiss(activityID: "a")
        #expect(model.state == .collapsed)
    }

    @Test func interactivityCallbackFiresOnlyOnChange() {
        var calls: [Bool] = []
        model.onInteractivityChange = { calls.append($0) }
        model.setExpanded(true)
        model.setExpanded(true)
        model.setExpanded(false)
        #expect(calls == [true, false])
    }

    @Test func clickingTheHoveredIslandKeepsItInteractive() {
        var calls: [Bool] = []
        model.onInteractivityChange = { calls.append($0) }
        model.setHovered(true)
        model.setHovered(true)
        #expect(model.isInteractive)

        // Expanding replaces the hover without the panel dropping the mouse in between.
        model.setExpanded(true)
        #expect(!model.isHovered)
        #expect(model.isInteractive)

        model.setExpanded(false)
        #expect(calls == [true, false])
    }

    @Test func hoverGrowsCollapsedAndActivityIslandByARing() {
        let ring = NotchTheme.hoverGrowth
        model.setHovered(true)
        #expect(model.state == .collapsed)
        #expect(model.bodySize == CGSize(width: 190 + ring.width * 2, height: 32 + ring.height))
        #expect(model.islandScreenFrame.maxY == 956)
        // The bottom corners grow by the ring too, keeping the center of the unhovered ones.
        let collapsed = NotchTheme.collapsedBottomRadius
        #expect(model.bottomCornerRadii == CGSize(width: collapsed + ring.width, height: collapsed + ring.height))

        model.present(activity("a"))
        let activityWidth = 190 + NotchTheme.activityWingWidth * 2
        #expect(model.bodySize == CGSize(width: activityWidth + ring.width * 2, height: 32 + ring.height))
        let wings = NotchTheme.activityBottomRadius
        #expect(model.bottomCornerRadii == CGSize(width: wings + ring.width, height: wings + ring.height))

        model.setHovered(false)
        #expect(model.bodySize == CGSize(width: activityWidth, height: 32))
        #expect(model.bottomCornerRadii == CGSize(width: wings, height: wings))
    }

    @Test func expandedIslandIgnoresHover() {
        model.setExpanded(true)
        model.setHovered(true)
        #expect(!model.isHovered)
        #expect(model.bodySize == NotchTheme.expandedSize)
        let radius = NotchTheme.expandedBottomRadius
        #expect(model.bottomCornerRadii == CGSize(width: radius, height: radius))
    }

    @Test func expandedContentDropsOnceShownAndOutlivesTheCollapse() async throws {
        model.expandedContentLinger = .milliseconds(20)
        model.setExpanded(true)
        #expect(model.isExpandedContentMounted)
        // Mounted raised, so it has a pose to drop from.
        #expect(!model.isExpandedContentDropped)

        model.expandedContentDidAppear()
        #expect(model.isExpandedContentDropped)

        // Collapsing raises it at once but keeps it mounted while it rises.
        model.setExpanded(false)
        #expect(!model.isExpandedContentDropped)
        #expect(model.isExpandedContentMounted)

        try await Task.sleep(for: .milliseconds(150))
        #expect(!model.isExpandedContentMounted)
        #expect(!model.hasExpandedContentAppeared)
    }

    @Test func expandingAgainWhileTheContentRisesKeepsTheSameContent() async throws {
        model.expandedContentLinger = .milliseconds(20)
        model.setExpanded(true)
        model.expandedContentDidAppear()
        model.setExpanded(false)

        // The views still on screen drop again; there is nothing new to wait for.
        model.setExpanded(true)
        #expect(model.isExpandedContentDropped)

        try await Task.sleep(for: .milliseconds(150))
        #expect(model.isExpandedContentMounted)
        #expect(model.isExpandedContentDropped)
    }

    @Test func higherPriorityWinsThenNewestAmongEqual() {
        model.present(activity("low", priority: .low))
        model.present(activity("high", priority: .high))
        model.present(activity("normal1"))
        model.present(activity("normal2"))

        #expect(model.currentActivity?.id == "high")
        #expect(model.queuedActivityIDs == ["high", "normal2", "normal1", "low"])

        model.dismiss(activityID: "high")
        #expect(model.currentActivity?.id == "normal2")
    }

    @Test func representingMovesToFrontOfItsBand() {
        model.present(activity("x"))
        model.present(activity("y"))
        model.present(activity("x"))
        #expect(model.queuedActivityIDs == ["x", "y"])
    }

    @Test func dismissIsScopedToFeature() {
        model.present(activity("same", feature: "one"))
        model.present(activity("same", feature: "two"))
        model.dismiss(activityID: "same", featureID: "one")
        #expect(model.queuedActivityIDs == ["same"])
        #expect(model.currentActivity?.featureID == "two")
    }

    @Test func expiryRemovesOnlyDueActivitiesInOrder() {
        let start = Date()
        model.present(activity("persistent", priority: .low), now: start)
        model.present(activity("short", priority: .high, duration: 3), now: start)
        model.present(activity("long", priority: .normal, duration: 10), now: start)
        #expect(model.currentActivity?.id == "short")

        model.removeExpired(now: start.addingTimeInterval(2.9))
        #expect(model.currentActivity?.id == "short")

        model.removeExpired(now: start.addingTimeInterval(3))
        #expect(model.currentActivity?.id == "long")

        model.removeExpired(now: start.addingTimeInterval(10))
        #expect(model.currentActivity?.id == "persistent")

        model.removeExpired(now: start.addingTimeInterval(10_000))
        #expect(model.queuedActivityIDs == ["persistent"])
    }

    private func holdingActivity(_ id: String, duration: TimeInterval) -> NotchActivity {
        NotchActivity(id: id, featureID: "test", duration: duration, holdsWhileExpanded: true) {
            EmptyView()
        } trailing: {
            EmptyView()
        }
    }

    @Test func holdingActivityPresentedWhileExpandedWaitsForCollapse() {
        #expect(!activity("a").holdsWhileExpanded)
        model.setExpanded(true)
        let start = Date()
        model.present(holdingActivity("reminder", duration: 2), now: start)
        model.removeExpired(now: start.addingTimeInterval(10))
        #expect(model.queuedActivityIDs == ["reminder"])

        model.setExpanded(false)
        let collapsed = Date()
        model.removeExpired(now: collapsed.addingTimeInterval(1.5))
        #expect(model.queuedActivityIDs == ["reminder"])
        model.removeExpired(now: collapsed.addingTimeInterval(2))
        #expect(model.queuedActivityIDs.isEmpty)
    }

    @Test func holdingActivityShowingWhenExpandedRestartsOnCollapse() {
        let start = Date()
        model.present(holdingActivity("reminder", duration: 2), now: start)
        model.setExpanded(true)
        model.removeExpired(now: start.addingTimeInterval(10))
        #expect(model.queuedActivityIDs == ["reminder"])

        model.setExpanded(false)
        let collapsed = Date()
        model.removeExpired(now: collapsed.addingTimeInterval(1.5))
        #expect(model.currentActivity?.id == "reminder")
        model.removeExpired(now: collapsed.addingTimeInterval(2))
        #expect(model.currentActivity == nil)
    }

    @Test func otherActivitiesStillExpireWhileExpanded() {
        model.setExpanded(true)
        let start = Date()
        model.present(activity("volume", duration: 2), now: start)
        model.present(holdingActivity("reminder", duration: 2), now: start)
        model.removeExpired(now: start.addingTimeInterval(2))
        #expect(model.queuedActivityIDs == ["reminder"])
    }

    @Test func holdingActivityCanBeDismissedWhileExpanded() {
        model.setExpanded(true)
        model.present(holdingActivity("reminder", duration: 2))
        model.dismiss(activityID: "reminder", featureID: "test")
        #expect(model.queuedActivityIDs.isEmpty)
        model.setExpanded(false)
        #expect(model.currentActivity == nil)
    }

    @Test func holdingActivityReplacedWhileExpandedStaysHeld() {
        model.setExpanded(true)
        let start = Date()
        model.present(holdingActivity("reminder", duration: 2), now: start)
        model.present(holdingActivity("reminder", duration: 2), now: start.addingTimeInterval(1))
        model.removeExpired(now: start.addingTimeInterval(10))
        #expect(model.queuedActivityIDs == ["reminder"])
    }

    @Test func requestExpandSelectsKnownTab() {
        model.setTabs([
            .init(id: "clock", title: { "今天" }, symbol: { "clock" }, content: AnyView(EmptyView())),
            .init(id: "battery", title: { "电池" }, symbol: { "battery.75percent" }, content: AnyView(EmptyView())),
        ])
        #expect(model.selectedTab?.id == "clock")

        model.requestExpand(tabID: "battery")
        #expect(model.state == .expanded)
        #expect(model.selectedTabID == "battery")

        model.requestExpand(tabID: "unknown")
        #expect(model.selectedTabID == "battery")
    }

    @Test func dragOpensTheFirstTabThatTakesDrops() {
        model.setTabs([
            .init(id: "home", title: { "主页" }, symbol: { "house" }, content: AnyView(EmptyView())),
            .init(id: "files", title: { "文件" }, symbol: { "folder" }, opensOnDrag: true, content: AnyView(EmptyView())),
            .init(id: "shelf", title: { "架子" }, symbol: { "tray" }, opensOnDrag: true, content: AnyView(EmptyView())),
            .init(id: "battery", title: { "电池" }, symbol: { "battery.75percent" }, placement: .trailing, content: AnyView(EmptyView())),
        ])
        model.selectedTabID = "battery"

        model.expandForDrop()
        #expect(model.state == .expanded)
        #expect(model.selectedTabID == "files")
    }

    @Test func dragKeepsTheSelectedTabWhenNoneTakesDrops() {
        model.setTabs([
            .init(id: "home", title: { "主页" }, symbol: { "house" }, content: AnyView(EmptyView())),
            .init(id: "battery", title: { "电池" }, symbol: { "battery.75percent" }, placement: .trailing, content: AnyView(EmptyView())),
        ])
        model.selectedTabID = "battery"

        model.expandForDrop()
        #expect(model.state == .expanded)
        #expect(model.selectedTabID == "battery")
    }

    /// Lets a test show and hide a tab after it is set, as a feature's observable state would.
    private final class Availability {
        var isAvailable: Bool

        init(_ isAvailable: Bool) {
            self.isAvailable = isAvailable
        }
    }

    @Test func hiddenTabIsNotVisible() {
        let airPods = Availability(false)
        model.setTabs([
            .init(id: "airpods", title: { "AirPods" }, symbol: { "airpods" }, isAvailable: { airPods.isAvailable }, content: AnyView(EmptyView())),
            .init(id: "home", title: { "主页" }, symbol: { "house" }, content: AnyView(EmptyView())),
        ])
        #expect(model.visibleTabs.map(\.id) == ["home"])

        airPods.isAvailable = true
        #expect(model.visibleTabs.map(\.id) == ["airpods", "home"])
    }

    @Test func defaultSelectionSkipsAHiddenFirstTab() {
        let airPods = Availability(false)
        model.setTabs([
            .init(id: "airpods", title: { "AirPods" }, symbol: { "airpods" }, isAvailable: { airPods.isAvailable }, content: AnyView(EmptyView())),
            .init(id: "home", title: { "主页" }, symbol: { "house" }, content: AnyView(EmptyView())),
        ])
        #expect(model.selectedTabID == "home")

        // Showing up later leaves the selection where it is.
        airPods.isAvailable = true
        #expect(model.selectedTab?.id == "home")
    }

    @Test func selectionFallsBackWhileItsTabIsHiddenAndReturnsWhenShown() {
        let airPods = Availability(true)
        model.setTabs([
            .init(id: "home", title: { "主页" }, symbol: { "house" }, content: AnyView(EmptyView())),
            .init(id: "airpods", title: { "AirPods" }, symbol: { "airpods" }, isAvailable: { airPods.isAvailable }, content: AnyView(EmptyView())),
            .init(id: "battery", title: { "电池" }, symbol: { "battery.75percent" }, placement: .trailing, content: AnyView(EmptyView())),
        ])
        model.selectedTabID = "airpods"
        #expect(model.selectedTab?.id == "airpods")

        airPods.isAvailable = false
        #expect(model.selectedTab?.id == "home")
        #expect(model.selectedTabID == "airpods")

        airPods.isAvailable = true
        #expect(model.selectedTab?.id == "airpods")
    }

    @Test func requestExpandIgnoresAHiddenTab() {
        let airPods = Availability(false)
        model.setTabs([
            .init(id: "home", title: { "主页" }, symbol: { "house" }, content: AnyView(EmptyView())),
            .init(id: "airpods", title: { "AirPods" }, symbol: { "airpods" }, isAvailable: { airPods.isAvailable }, content: AnyView(EmptyView())),
        ])
        #expect(model.selectedTabID == "home")

        model.requestExpand(tabID: "airpods")
        #expect(model.state == .expanded)
        #expect(model.selectedTabID == "home")
        #expect(model.selectedTab?.id == "home")
    }

    @Test func dragSkipsAHiddenTabThatTakesDrops() {
        let files = Availability(false)
        model.setTabs([
            .init(id: "home", title: { "主页" }, symbol: { "house" }, content: AnyView(EmptyView())),
            .init(id: "files", title: { "文件" }, symbol: { "folder" }, opensOnDrag: true, isAvailable: { files.isAvailable }, content: AnyView(EmptyView())),
            .init(id: "shelf", title: { "架子" }, symbol: { "tray" }, opensOnDrag: true, content: AnyView(EmptyView())),
        ])

        model.expandForDrop()
        #expect(model.state == .expanded)
        #expect(model.selectedTabID == "shelf")
    }

    @Test func tabChangeCallbackFiresOnlyWhenTheSelectionChanges() {
        model.setTabs([
            .init(id: "home", title: { "主页" }, symbol: { "house" }, content: AnyView(EmptyView())),
            .init(id: "notes", title: { "笔记" }, symbol: { "note.text" }, content: AnyView(EmptyView())),
        ])
        var calls = 0
        model.onSelectedTabChange = { calls += 1 }

        model.selectedTabID = "notes"
        #expect(calls == 1)
        model.selectedTabID = "notes"
        #expect(calls == 1)

        model.requestExpand(tabID: "home")
        #expect(model.selectedTabID == "home")
        #expect(calls == 2)
        model.requestExpand(tabID: "home")
        #expect(calls == 2)
    }

    @Test func tabChangeCallbackStaysQuietForAHiddenTab() {
        let airPods = Availability(false)
        model.setTabs([
            .init(id: "home", title: { "主页" }, symbol: { "house" }, content: AnyView(EmptyView())),
            .init(id: "airpods", title: { "AirPods" }, symbol: { "airpods" }, isAvailable: { airPods.isAvailable }, content: AnyView(EmptyView())),
        ])
        var calls = 0
        model.onSelectedTabChange = { calls += 1 }

        model.requestExpand(tabID: "airpods")
        #expect(model.selectedTabID == "home")
        #expect(calls == 0)
    }

    /// Lets a test change the width a tab asks for after it is set, as a feature's
    /// observable state would.
    private final class Width {
        var value: CGFloat?

        init(_ value: CGFloat?) {
            self.value = value
        }
    }

    @Test func expandedWidthFollowsTheSelectedTab() {
        let home = Width(640)
        model.setTabs([
            .init(id: "home", title: { "主页" }, symbol: { "house" }, expandedWidth: { home.value }, content: AnyView(EmptyView())),
            .init(id: "files", title: { "文件" }, symbol: { "folder" }, content: AnyView(EmptyView())),
        ])
        model.setExpanded(true)
        #expect(model.bodySize == CGSize(width: 640, height: 190))

        home.value = 880
        #expect(model.bodySize.width == 880)

        // A tab that asks for nothing gets the standard width.
        model.selectedTabID = "files"
        #expect(model.bodySize == CGSize(width: 520, height: 190))

        model.selectedTabID = "home"
        home.value = nil
        #expect(model.bodySize.width == 520)
    }

    @Test func expandedWidthStaysBetweenTheStandardAndTheMaximum() {
        let home = Width(2000)
        model.setTabs([
            .init(id: "home", title: { "主页" }, symbol: { "house" }, expandedWidth: { home.value }, content: AnyView(EmptyView())),
        ])
        model.setExpanded(true)
        #expect(model.bodySize.width == 880)

        home.value = 300
        #expect(model.bodySize.width == 520)
    }

    @Test func aWideTabLeavesTheCollapsedAndActivitySizesAlone() {
        model.setTabs([
            .init(id: "home", title: { "主页" }, symbol: { "house" }, expandedWidth: { 760 }, content: AnyView(EmptyView())),
        ])
        #expect(model.bodySize == CGSize(width: 190, height: 32))

        model.present(activity("a"))
        #expect(model.bodySize == CGSize(width: 190 + NotchTheme.activityWingWidth * 2, height: 32))

        model.setExpanded(true)
        #expect(model.bodySize == CGSize(width: 760, height: 190))
        #expect(model.islandSize.width == NotchShape.frameWidth(bodyWidth: 760, topCornerRadius: NotchTheme.expandedTopRadius))

        model.setExpanded(false)
        #expect(model.bodySize == CGSize(width: 190 + NotchTheme.activityWingWidth * 2, height: 32))
    }

    @Test func requestingADetailExpandsOnIt() {
        model.requestExpand(detail: AnyView(EmptyView()), featureID: "notifications")
        #expect(model.state == .expanded)
        #expect(model.isExpandedContentMounted)
        #expect(model.detail?.featureID == "notifications")
    }

    @Test func aDetailRisesOutWithTheContentAndGoesWithIt() async throws {
        model.expandedContentLinger = .milliseconds(20)
        model.requestExpand(detail: AnyView(EmptyView()), featureID: "notifications")
        model.expandedContentDidAppear()

        model.setExpanded(false)
        #expect(model.isExpandedContentMounted)
        #expect(model.detail != nil)

        try await Task.sleep(for: .milliseconds(150))
        #expect(!model.isExpandedContentMounted)
        #expect(model.detail == nil)
    }

    @Test func clickingTheIslandWhileADetailRisesShowsTheTabs() {
        model.expandedContentLinger = .seconds(10)
        model.requestExpand(detail: AnyView(EmptyView()), featureID: "notifications")
        model.setExpanded(false)
        #expect(model.detail != nil)

        model.setExpanded(true)
        #expect(model.state == .expanded)
        #expect(model.detail == nil)
    }

    @Test func requestingATabOverADetailShowsTheTabs() {
        model.setTabs([
            .init(id: "home", title: { "主页" }, symbol: { "house" }, content: AnyView(EmptyView())),
            .init(id: "battery", title: { "电池" }, symbol: { "battery.75percent" }, content: AnyView(EmptyView())),
        ])
        model.requestExpand(detail: AnyView(EmptyView()), featureID: "notifications")
        var tabChanges = 0
        model.onSelectedTabChange = { tabChanges += 1 }

        model.requestExpand(tabID: "battery")
        #expect(model.state == .expanded)
        #expect(model.detail == nil)
        #expect(model.selectedTabID == "battery")
        #expect(tabChanges >= 1)
    }

    @Test func aDropOverADetailShowsTheTabs() {
        model.setTabs([
            .init(id: "home", title: { "主页" }, symbol: { "house" }, content: AnyView(EmptyView())),
            .init(id: "files", title: { "文件" }, symbol: { "folder" }, opensOnDrag: true, content: AnyView(EmptyView())),
        ])
        model.requestExpand(detail: AnyView(EmptyView()), featureID: "notifications")

        model.expandForDrop()
        #expect(model.detail == nil)
        #expect(model.selectedTabID == "files")
    }

    @Test func aDetailTakesTheStandardWidth() {
        model.setTabs([
            .init(id: "home", title: { "主页" }, symbol: { "house" }, expandedWidth: { 760 }, content: AnyView(EmptyView())),
        ])
        model.requestExpand(detail: AnyView(EmptyView()), featureID: "notifications")
        #expect(model.bodySize == CGSize(width: 520, height: 190))

        model.requestExpand(tabID: "home")
        #expect(model.bodySize.width == 760)
    }

    @Test func aNewDetailReplacesTheShownOne() {
        model.requestExpand(detail: AnyView(EmptyView()), featureID: "notifications")
        let first = model.detail?.sequence
        #expect(first != nil)
        var tabChanges = 0
        model.onSelectedTabChange = { tabChanges += 1 }

        model.requestExpand(detail: AnyView(EmptyView()), featureID: "notifications")
        #expect(model.state == .expanded)
        #expect(model.detail != nil)
        #expect(model.detail?.sequence != first)
        // Ends text editing as a tab switch does.
        #expect(tabChanges == 1)
    }

    @Test func activitiesDoNotMorphIntoTheirTabUnlessAsked() {
        #expect(!activity("a").morphsIntoTab)
        let morphing = NotchActivity(id: "b", featureID: "test", morphsIntoTab: true) {
            EmptyView()
        } trailing: {
            EmptyView()
        }
        #expect(morphing.morphsIntoTab)
    }

    @Test func heroesSitInTheWingsUntilTheIslandOpens() {
        let state = NotchMorphState(isExpanded: false, wingFeatureID: "music", shownTabID: "music")
        #expect(state.isSource(.wing, tabID: nil))
        #expect(!state.isSource(.tab, tabID: "music"))
        #expect(state.showsHeroes)
        // The tab, still mounted while it rises, leaves its places empty meanwhile.
        #expect(state.heroesStandIn(forTab: "music"))
        #expect(!state.heroesStandIn(forTab: "home"))
    }

    @Test func heroesFlyIntoTheirFeaturesShownTab() {
        let state = NotchMorphState(isExpanded: true, wingFeatureID: "music", shownTabID: "music")
        #expect(!state.isSource(.wing, tabID: nil))
        #expect(state.isSource(.tab, tabID: "music"))
        #expect(!state.isSource(.tab, tabID: "home"))
        #expect(state.showsHeroes)
    }

    @Test func heroesHideWhileAnotherTabIsShown() {
        let state = NotchMorphState(isExpanded: true, wingFeatureID: "music", shownTabID: "home")
        #expect(!state.isSource(.wing, tabID: nil))
        // The hidden tab still leads its heroes, so they slide and fade with it.
        #expect(state.isSource(.tab, tabID: "music"))
        #expect(!state.isSource(.tab, tabID: "home"))
        #expect(!state.showsHeroes)
    }

    @Test func morphingActivityOutlastsAHigherPriorityOne() {
        let music = NotchActivity(id: "track", featureID: "music", morphsIntoTab: true) {
            EmptyView()
        } trailing: {
            EmptyView()
        }
        model.present(music)
        model.present(activity("volume", feature: "hud", priority: .high))
        #expect(model.currentActivity?.featureID == "hud")
        #expect(model.morphingActivity?.featureID == "music")

        model.dismiss(activityID: "track", featureID: "music")
        #expect(model.morphingActivity == nil)
    }

    @Test func withoutHeroesTheTabDrawsItsOwnViews() {
        // E.g. a higher-priority activity is current, or the feature's has left.
        let state = NotchMorphState(isExpanded: true, wingFeatureID: nil, shownTabID: "music")
        #expect(!state.isSource(.tab, tabID: "music"))
        #expect(!state.heroesStandIn(forTab: "music"))
        #expect(!state.showsHeroes)
        // A tab outside the panel's tabs never stands in.
        #expect(!NotchMorphState(isExpanded: true, wingFeatureID: "music", shownTabID: nil).isSource(.tab, tabID: nil))
        #expect(!NotchMorphState(isExpanded: true, wingFeatureID: "music", shownTabID: nil).heroesStandIn(forTab: nil))
    }

    private func rimActivity(_ id: String, priority: NotchActivity.Priority = .normal) -> NotchActivity {
        NotchActivity(id: id, featureID: "test", priority: priority, rim: NotchActivityRim(color: .orange) { _ in 0.5 })
    }

    @Test func rimActivityGrowsTheIslandByTheRimThickness() {
        let thickness = NotchTheme.activityRimThickness
        model.present(rimActivity("rim"))
        #expect(model.state == .activity)
        #expect(model.bodySize == CGSize(width: 190 + thickness * 2, height: 32 + thickness))

        // Hovered, the ring the island grows by comes on top.
        let ring = NotchTheme.hoverGrowth
        model.setHovered(true)
        #expect(model.bodySize == CGSize(width: 190 + thickness * 2 + ring.width * 2, height: 32 + thickness + ring.height))
        model.setHovered(false)

        // A wings activity on top takes its wing width and the notch's height again.
        let wingWidth: CGFloat = 40
        model.present(NotchActivity(id: "wings", featureID: "test", priority: .high, wingWidth: wingWidth) {
            EmptyView()
        } trailing: {
            EmptyView()
        })
        #expect(model.bodySize == CGSize(width: 190 + wingWidth * 2, height: 32))

        model.dismiss(activityID: "wings")
        #expect(model.bodySize == CGSize(width: 190 + thickness * 2, height: 32 + thickness))
    }

    @Test func rimActivityLeavesWhileExpandedAndReturnsOnCollapse() {
        model.present(rimActivity("rim"))
        #expect(model.currentActivity?.rim != nil)
        #expect(!model.currentActivity!.morphsIntoTab)

        model.setExpanded(true)
        #expect(model.bodySize == NotchTheme.expandedSize)
        #expect(model.morphingActivity == nil)

        model.setExpanded(false)
        #expect(model.bodySize == CGSize(
            width: 190 + NotchTheme.activityRimThickness * 2,
            height: 32 + NotchTheme.activityRimThickness
        ))
    }

    @Test func wingsActivitiesHaveNoRim() {
        #expect(activity("a").rim == nil)
    }

    @Test func rimActivityOutlastsWingsOnTopAndTheOpenIsland() {
        #expect(model.rimActivity == nil)
        model.present(activity("wings", priority: .high))
        #expect(model.rimActivity == nil)

        model.present(rimActivity("low"))
        model.present(rimActivity("rim", priority: NotchActivity.Priority(60)))
        #expect(model.currentActivity?.id == "wings")
        #expect(model.rimActivity?.id == "rim")

        model.setExpanded(true)
        #expect(model.rimActivity?.id == "rim")
        model.setExpanded(false)

        model.dismiss(activityID: "rim", featureID: "test")
        #expect(model.rimActivity?.id == "low")
        model.dismiss(activityID: "low", featureID: "test")
        #expect(model.rimActivity == nil)
    }

    @Test func tabCarriesItsCustomIcon() {
        model.setTabs([
            .init(id: "home", title: { "主页" }, symbol: { "house" }, content: AnyView(EmptyView())),
            .init(id: "timer", title: { "计时器" }, symbol: { "timer" }, placement: .trailing, icon: AnyView(Circle()), content: AnyView(EmptyView())),
        ])
        #expect(model.tabs.first { $0.id == "home" }?.icon == nil)
        #expect(model.tabs.first { $0.id == "timer" }?.icon != nil)
    }

    @Test func heldWingsOverARimShowAfterCollapseThenRevealTheRim() {
        model.setExpanded(true)
        let start = Date()
        model.present(rimActivity("rim", priority: NotchActivity.Priority(60)), now: start)
        model.present(NotchActivity(
            id: "wings",
            featureID: "test",
            priority: NotchActivity.Priority(61),
            duration: 2,
            holdsWhileExpanded: true
        ) {
            EmptyView()
        } trailing: {
            EmptyView()
        }, now: start)
        model.removeExpired(now: start.addingTimeInterval(10))

        model.setExpanded(false)
        let collapsed = Date()
        #expect(model.currentActivity?.id == "wings")
        model.removeExpired(now: collapsed.addingTimeInterval(1.5))
        #expect(model.currentActivity?.id == "wings")
        model.removeExpired(now: collapsed.addingTimeInterval(2))
        #expect(model.currentActivity?.id == "rim")
        #expect(model.currentActivity?.rim != nil)
    }
}
