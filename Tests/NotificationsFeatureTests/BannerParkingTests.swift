import Foundation
import Testing
@testable import NotificationsFeature

struct BannerParkingTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    let home = CGPoint(x: 1200, y: 40)
    let delay = BannerParking.restoreDelay

    func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test func restoreDelayAndTimeoutValues() {
        #expect(BannerParking.restoreDelay == 0.35)
        #expect(BannerParking.maximumDuration == 8)
    }

    @Test func windowGoesBackOnlyRestoreDelayAfterItsBannerDisappears() {
        var parking = BannerParking()
        var restored: [Int: CGPoint] = [:]
        parking.park("a", window: 1, savedPosition: home, at: start)
        #expect(parking.isParked(window: 1))
        restored = parking.update(live: ["a": 1], at: at(1))
        #expect(restored == [:])
        // Gone: the window waits out the delay before it moves back.
        restored = parking.update(live: [:], at: at(2))
        #expect(restored == [:])
        #expect(parking.isParked(window: 1))
        #expect(parking.nextDeadline == at(2 + delay))
        restored = parking.update(live: [:], at: at(2 + delay / 2))
        #expect(restored == [:])
        restored = parking.update(live: [:], at: at(2 + delay))
        #expect(restored == [1: home])
        #expect(!parking.isParked(window: 1))
        #expect(parking.nextDeadline == nil)
    }

    @Test func tokenReappearingDuringTheDelayKeepsItParked() {
        var parking = BannerParking()
        var restored: [Int: CGPoint] = [:]
        parking.park("a", window: 1, savedPosition: home, at: start)
        restored = parking.update(live: [:], at: at(1))
        #expect(restored == [:])
        restored = parking.update(live: ["a": 1], at: at(1 + delay / 2))
        #expect(restored == [:])
        // The delay starts over from the next time it goes.
        restored = parking.update(live: [:], at: at(2))
        #expect(restored == [:])
        #expect(parking.nextDeadline == at(2 + delay))
        restored = parking.update(live: [:], at: at(2 + delay))
        #expect(restored == [1: home])
    }

    @Test func bannerArrivingDuringTheDelayJoinsTheParkedWindow() {
        var parking = BannerParking()
        var restored: [Int: CGPoint] = [:]
        parking.park("a", window: 1, savedPosition: home, at: start)
        restored = parking.update(live: [:], at: at(1))
        #expect(restored == [:])
        let joined = parking.join("b", window: 1)
        #expect(joined)
        #expect(parking.windows[1]?.parkedAt == start)
        restored = parking.update(live: ["b": 1], at: at(1 + delay))
        #expect(restored == [:])
        #expect(parking.isParked(window: 1))
    }

    @Test func timeoutStillAppliesDuringTheDelay() {
        var parking = BannerParking()
        var restored: [Int: CGPoint] = [:]
        parking.park("a", window: 1, savedPosition: home, at: start)
        restored = parking.update(live: [:], at: at(7.9))
        #expect(restored == [:])
        // The timeout comes before the end of the delay.
        #expect(parking.nextDeadline == at(8))
        restored = parking.update(live: [:], at: at(8))
        #expect(restored == [1: home])
    }

    @Test func tokenInAnotherWindowDoesNotKeepItParked() {
        var parking = BannerParking()
        var restored: [Int: CGPoint] = [:]
        parking.park("a", window: 1, savedPosition: home, at: start)
        restored = parking.update(live: ["a": 2], at: at(1))
        #expect(restored == [:])
        restored = parking.update(live: ["a": 2], at: at(1 + delay))
        #expect(restored == [1: home])
    }

    @Test func sharedWindowGoesBackOnlyWithItsLastBanner() {
        var parking = BannerParking()
        var restored: [Int: CGPoint] = [:]
        parking.park("a", window: 1, savedPosition: home, at: start)
        let joined = parking.join("b", window: 1)
        #expect(joined)
        restored = parking.update(live: ["b": 1], at: at(1))
        #expect(restored == [:])
        restored = parking.update(live: ["b": 1], at: at(2))
        #expect(restored == [:])
        #expect(parking.isParked(window: 1))
        restored = parking.update(live: [:], at: at(3))
        #expect(restored == [:])
        restored = parking.update(live: [:], at: at(3 + delay))
        #expect(restored == [1: home])
    }

    @Test func joiningKeepsTheFirstSavedPositionAndTimeout() {
        var parking = BannerParking()
        parking.park("a", window: 1, savedPosition: home, at: start)
        parking.join("b", window: 1)
        #expect(parking.windows[1]?.savedPosition == home)
        #expect(parking.nextDeadline == at(BannerParking.maximumDuration))
    }

    @Test func joiningAWindowThatIsNotParkedFails() {
        var parking = BannerParking()
        let joined = parking.join("a", window: 1)
        #expect(!joined)
        #expect(parking.windows.isEmpty)
    }

    @Test func timeoutRestoresAndBlocksParkingAgain() {
        var parking = BannerParking()
        var restored: [Int: CGPoint] = [:]
        parking.park("a", window: 1, savedPosition: home, at: start)
        #expect(parking.nextDeadline == at(8))
        restored = parking.update(live: ["a": 1], at: at(7.9))
        #expect(restored == [:])
        restored = parking.update(live: ["a": 1], at: at(8))
        #expect(restored == [1: home])
        #expect(!parking.canPark("a"))
        // Still blocked while it stays live...
        restored = parking.update(live: ["a": 1], at: at(9))
        #expect(restored == [:])
        #expect(!parking.canPark("a"))
        // ...and free again once it is gone.
        _ = parking.update(live: [:], at: at(10))
        #expect(parking.canPark("a"))
    }

    @Test func otherWindowsKeepTheirOwnTimeout() {
        var parking = BannerParking()
        var restored: [Int: CGPoint] = [:]
        parking.park("a", window: 1, savedPosition: home, at: start)
        let other = CGPoint(x: 1200, y: 120)
        parking.park("b", window: 2, savedPosition: other, at: at(5))
        restored = parking.update(live: ["a": 1, "b": 2], at: at(8))
        #expect(restored == [1: home])
        #expect(parking.canPark("b"))
        #expect(parking.nextDeadline == at(13))
        restored = parking.update(live: ["a": 1, "b": 2], at: at(13))
        #expect(restored == [2: other])
    }

    @Test func parkedWindowThatTurnsBlockedGoesBackAtOnce() {
        var parking = BannerParking()
        var restored: [Int: CGPoint] = [:]
        parking.park("a", window: 1, savedPosition: home, at: start)
        restored = parking.update(live: ["a": 1, "alert": 1], blocked: [1], at: at(1))
        #expect(restored == [1: home])
        #expect(!parking.isParked(window: 1))
    }

    @Test func blockedWindowIsNeitherParkedNorJoined() {
        var parking = BannerParking()
        let parked = parking.park("a", window: 1, savedPosition: home, at: start, blocked: [1])
        #expect(!parked)
        #expect(!parking.isParked(window: 1))
        parking.park("b", window: 2, savedPosition: home, at: start)
        let joined = parking.join("c", window: 2, blocked: [2])
        #expect(!joined)
        #expect(parking.windows[2]?.tokens == ["b"])
    }

    @Test func positionOffScreenIsNoHome() {
        var parking = BannerParking()
        #expect(!BannerParking.isHome(BannerParking.parkingPosition))
        #expect(BannerParking.isHome(home))
        let parked = parking.park("a", window: 1, savedPosition: BannerParking.parkingPosition, at: start)
        #expect(!parked)
        #expect(parking.windows.isEmpty)
    }

    @Test func latestSavedPositionIsTheLastParkedWindows() {
        var parking = BannerParking()
        #expect(parking.latestSavedPosition == nil)
        let other = CGPoint(x: 10, y: 20)
        parking.park("a", window: 1, savedPosition: home, at: start)
        parking.park("b", window: 2, savedPosition: other, at: at(1))
        #expect(parking.latestSavedPosition == other)
    }

    @Test func strandedWindowsAreThoseAtTheParkingPosition() {
        let positions: [Int: CGPoint] = [1: BannerParking.parkingPosition, 2: home, 3: BannerParking.parkingPosition]
        #expect(BannerParking.windowsToRecover(positions: positions, home: home) == [1, 3])
        #expect(BannerParking.windowsToRecover(positions: positions, home: nil) == [])
        #expect(BannerParking.windowsToRecover(positions: [2: home], home: home) == [])
    }

    @Test func restoreAllReturnsEveryWindowAtOnceAndForgetsThem() {
        var parking = BannerParking()
        var restored: [Int: CGPoint] = [:]
        let other = CGPoint(x: 10, y: 20)
        parking.park("a", window: 1, savedPosition: home, at: start)
        parking.park("b", window: 2, savedPosition: other, at: start)
        // Window 2 is waiting out its delay; it goes back too.
        _ = parking.update(live: ["a": 1], at: at(1))
        restored = parking.restoreAll()
        #expect(restored == [1: home, 2: other])
        #expect(parking.windows.isEmpty)
        #expect(parking.nextDeadline == nil)
        restored = parking.restoreAll()
        #expect(restored == [:])
    }
}
