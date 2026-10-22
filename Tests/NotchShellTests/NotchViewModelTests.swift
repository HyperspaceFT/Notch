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

        model.present(activity("a"))
        let activityWidth = 190 + NotchTheme.activityWingWidth * 2
        #expect(model.bodySize == CGSize(width: activityWidth + ring.width * 2, height: 32 + ring.height))

        model.setHovered(false)
        #expect(model.bodySize == CGSize(width: activityWidth, height: 32))
    }

    @Test func expandedIslandIgnoresHover() {
        model.setExpanded(true)
        model.setHovered(true)
        #expect(!model.isHovered)
        #expect(model.bodySize == NotchTheme.expandedSize)
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
}
