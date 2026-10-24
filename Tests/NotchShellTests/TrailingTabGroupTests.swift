import CoreGraphics
import Foundation
import NotchKit
import SwiftUI
import Testing
@testable import NotchShell

/// The header's right-side tab group: which tab its collapsed button shows, the
/// order of its open row, the remembered last right-side tab, and opening on hover.
@MainActor
struct TrailingTabGroupTests {
    private static let geometry = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        safeAreaTop: 32,
        auxiliaryTopLeftArea: CGRect(x: 0, y: 924, width: 640, height: 32),
        auxiliaryTopRightArea: CGRect(x: 830, y: 924, width: 640, height: 32)
    )

    /// Lets a test change a tab's availability or activity after it is set, as a
    /// feature's observable state would.
    private final class Flag {
        var value: Bool

        init(_ value: Bool) {
            self.value = value
        }
    }

    /// A model on its own defaults domain, removed after `body`.
    private func withModel(_ body: (UserDefaults, () -> NotchViewModel) throws -> Void) rethrows {
        let suite = "TrailingTabGroupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults) { NotchViewModel(geometry: Self.geometry, defaults: defaults) }
    }

    private func tab(
        _ id: String,
        _ placement: NotchTabPlacement,
        available: Flag = Flag(true),
        active: Flag = Flag(false)
    ) -> NotchViewModel.Tab {
        .init(
            id: id,
            title: { id },
            symbol: { "circle" },
            placement: placement,
            isAvailable: { available.value },
            isActive: { active.value },
            content: AnyView(EmptyView())
        )
    }

    @Test func aSelectedTrailingTabIsTheRepresentative() {
        withModel { _, make in
            let model = make()
            model.setTabs([
                tab("home", .leading),
                tab("timer", .trailing, active: Flag(true)),
                tab("battery", .trailing),
                tab("notes", .trailing),
            ])
            model.selectedTabID = "notes"
            // Even over an active tab.
            #expect(model.trailingRepresentative?.id == "notes")
            // The representative last, at the header's right end.
            #expect(model.trailingTabRow.map(\.id) == ["timer", "battery", "notes"])
        }
    }

    @Test func anActiveTabWinsOverTheLastUsedWhileALeadingTabIsShown() {
        withModel { _, make in
            let model = make()
            let timerActive = Flag(false)
            model.setTabs([
                tab("home", .leading),
                tab("timer", .trailing, active: timerActive),
                tab("battery", .trailing),
                tab("notes", .trailing),
            ])
            model.selectedTabID = "notes"
            model.selectedTabID = "home"
            #expect(model.trailingRepresentative?.id == "notes")

            timerActive.value = true
            #expect(model.trailingRepresentative?.id == "timer")
            #expect(model.trailingTabRow.map(\.id) == ["battery", "notes", "timer"])

            timerActive.value = false
            #expect(model.trailingRepresentative?.id == "notes")
        }
    }

    @Test func theFirstActiveTabWinsAmongSeveral() {
        withModel { _, make in
            let model = make()
            model.setTabs([
                tab("home", .leading),
                tab("battery", .trailing),
                tab("timer", .trailing, active: Flag(true)),
                tab("notes", .trailing, active: Flag(true)),
            ])
            #expect(model.trailingRepresentative?.id == "timer")
        }
    }

    @Test func withoutALastUsedTabTheFirstVisibleTrailingTabShows() {
        withModel { _, make in
            let model = make()
            model.setTabs([
                tab("home", .leading),
                tab("notifications", .trailing, available: Flag(false)),
                tab("battery", .trailing),
                tab("notes", .trailing),
            ])
            #expect(model.lastTrailingTabID == nil)
            #expect(model.trailingRepresentative?.id == "battery")
            #expect(model.trailingTabRow.map(\.id) == ["notes", "battery"])
        }
    }

    @Test func noVisibleTrailingTabsMeansNoGroup() {
        withModel { _, make in
            let model = make()
            let notifications = Flag(false)
            model.setTabs([
                tab("home", .leading),
                tab("notifications", .trailing, available: notifications),
            ])
            #expect(model.trailingRepresentative == nil)
            #expect(model.trailingTabRow.isEmpty)

            notifications.value = true
            #expect(model.trailingRepresentative?.id == "notifications")
        }
    }

    @Test func aHiddenLastUsedTabFallsBackAndReturnsWhenShown() {
        withModel { _, make in
            let model = make()
            let notifications = Flag(true)
            model.setTabs([
                tab("home", .leading),
                tab("battery", .trailing),
                tab("notes", .trailing),
                tab("notifications", .trailing, available: notifications),
            ])
            model.selectedTabID = "notifications"
            model.selectedTabID = "home"
            #expect(model.trailingRepresentative?.id == "notifications")

            notifications.value = false
            #expect(model.trailingRepresentative?.id == "battery")
            #expect(model.trailingTabRow.map(\.id) == ["notes", "battery"])
            // Still remembered, so it returns with its tab.
            #expect(model.lastTrailingTabID == "notifications")

            notifications.value = true
            #expect(model.trailingRepresentative?.id == "notifications")
            #expect(model.trailingTabRow.map(\.id) == ["battery", "notes", "notifications"])
        }
    }

    @Test func selectingALeadingTabKeepsTheRememberedTrailingTab() {
        withModel { defaults, make in
            let model = make()
            model.setTabs([
                tab("home", .leading),
                tab("files", .leading),
                tab("battery", .trailing),
                tab("notes", .trailing),
            ])
            model.selectedTabID = "battery"
            model.selectedTabID = "home"
            model.selectedTabID = "files"
            #expect(model.lastTrailingTabID == "battery")
            #expect(defaults.string(forKey: NotchViewModel.lastTrailingTabKey) == "battery")
            #expect(model.trailingRepresentative?.id == "battery")
        }
    }

    @Test func theLastUsedTrailingTabSurvivesARelaunch() {
        withModel { defaults, make in
            let first = make()
            first.setTabs([
                tab("home", .leading),
                tab("battery", .trailing),
                tab("notes", .trailing),
            ])
            first.selectedTabID = "notes"
            #expect(defaults.string(forKey: NotchViewModel.lastTrailingTabKey) == "notes")

            let second = make()
            #expect(second.lastTrailingTabID == "notes")
            second.setTabs([
                tab("home", .leading),
                tab("battery", .trailing),
                tab("notes", .trailing),
            ])
            #expect(second.selectedTab?.id == "home")
            #expect(second.trailingRepresentative?.id == "notes")
        }
    }

    @Test func aTrailingTabShownInTheSelectedOnesPlaceIsRemembered() {
        withModel { _, make in
            let model = make()
            let home = Flag(true)
            model.setTabs([
                tab("home", .leading, available: home),
                tab("battery", .trailing),
                tab("notes", .trailing),
            ])
            #expect(model.lastTrailingTabID == nil)

            // The panel reports the switch it draws (`shownTabDidChange`).
            home.value = false
            model.shownTabDidChange()
            #expect(model.selectedTab?.id == "battery")
            #expect(model.lastTrailingTabID == "battery")
        }
    }

    @Test func theRowOpensOnHoverAndClosesAfterTheDelay() async throws {
        let suite = "TrailingTabGroupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = NotchViewModel(geometry: Self.geometry, defaults: defaults)
        model.trailingTabGroupCollapseDelay = .milliseconds(50)

        // Not while the island is closed.
        model.setTrailingTabGroupHovered(true)
        #expect(!model.isTrailingTabGroupOpen)

        model.setExpanded(true)
        model.setTrailingTabGroupHovered(true)
        #expect(model.isTrailingTabGroupOpen)

        // Leaving and returning within the delay keeps it open.
        model.setTrailingTabGroupHovered(false)
        #expect(model.isTrailingTabGroupOpen)
        model.setTrailingTabGroupHovered(true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.isTrailingTabGroupOpen)

        model.setTrailingTabGroupHovered(false)
        // Polled, so a busy main actor during the parallel suite does not fail it.
        let deadline = ContinuousClock.now + .seconds(2)
        while model.isTrailingTabGroupOpen, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!model.isTrailingTabGroupOpen)
    }

    @Test func theOpenRowKeepsItsOrderWhenATabIsSelected() async throws {
        let suite = "TrailingTabGroupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = NotchViewModel(geometry: Self.geometry, defaults: defaults)
        model.trailingTabGroupCollapseDelay = .milliseconds(50)
        let notifications = Flag(false)
        model.setTabs([
            tab("home", .leading),
            tab("timer", .trailing),
            tab("battery", .trailing),
            tab("notes", .trailing),
            tab("notifications", .trailing, available: notifications),
        ])
        model.selectedTabID = "timer"
        model.setExpanded(true)
        model.setTrailingTabGroupHovered(true)
        #expect(model.trailingTabRow.map(\.id) == ["battery", "notes", "timer"])

        // Selecting the leftmost button leaves the row as it is.
        model.selectedTabID = "battery"
        #expect(model.trailingRepresentative?.id == "battery")
        #expect(model.trailingTabRow.map(\.id) == ["battery", "notes", "timer"])
        model.selectedTabID = "notes"

        // A tab that shows joins at the left end, away from the pointer; one that
        // goes away drops out.
        notifications.value = true
        #expect(model.trailingTabRow.map(\.id) == ["notifications", "battery", "notes", "timer"])
        model.setTabs([
            tab("home", .leading),
            tab("timer", .trailing),
            tab("notes", .trailing),
            tab("notifications", .trailing),
        ])
        #expect(model.trailingTabRow.map(\.id) == ["notifications", "notes", "timer"])

        // Closed after the delay, the selected tab is the right end again.
        model.setTrailingTabGroupHovered(false)
        let deadline = ContinuousClock.now + .seconds(2)
        while model.isTrailingTabGroupOpen, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!model.isTrailingTabGroupOpen)
        #expect(model.trailingTabRow.map(\.id) == ["timer", "notifications", "notes"])

        // Reopening takes the new order; closing with the island resets it too.
        model.setTrailingTabGroupHovered(true)
        #expect(model.trailingTabRow.map(\.id) == ["timer", "notifications", "notes"])
        model.selectedTabID = "timer"
        #expect(model.trailingTabRow.map(\.id) == ["timer", "notifications", "notes"])
        model.setExpanded(false)
        #expect(model.trailingTabRow.map(\.id) == ["notes", "notifications", "timer"])
    }

    @Test func theRowClosesWithTheIslandAndForADetail() {
        withModel { _, make in
            let model = make()
            model.setExpanded(true)
            model.setTrailingTabGroupHovered(true)
            model.setExpanded(false)
            #expect(!model.isTrailingTabGroupOpen)

            model.setExpanded(true)
            model.setTrailingTabGroupHovered(true)
            model.requestExpand(detail: AnyView(EmptyView()), featureID: "test")
            #expect(!model.isTrailingTabGroupOpen)
        }
    }
}
