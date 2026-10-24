import Foundation
import Testing
@testable import NotificationsFeature

@MainActor
struct NotificationSampleTests {
    @Test func samplesComeFromAppsEveryMacHas() {
        let samples = [NotificationSample.short, NotificationSample.long] + NotificationSample.sequence
        for sample in samples {
            let item = sample.item(received: Date())
            #expect(item.bundleIdentifier == sample.bundleIdentifier)
            #expect(item.appURL != nil)
            #expect(item.appName?.isEmpty == false)
            #expect(item.appName?.hasSuffix(".app") == false)
            #expect(item.summary.headline != nil)
        }
    }

    @Test func theRowShowsThreeDifferentApps() {
        let sequence = NotificationSample.sequence
        #expect(sequence.count == 3)
        #expect(Set(sequence.map(\.bundleIdentifier)).count == 3)
    }
}
