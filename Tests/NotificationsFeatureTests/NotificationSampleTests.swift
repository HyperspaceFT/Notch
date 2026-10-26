import Testing
@testable import NotificationsFeature

@MainActor
struct NotificationSampleTests {
    @Test func everySampleHasATitleAndABody() {
        let samples = [NotificationSample.short, NotificationSample.long] + NotificationSample.sequence
        for sample in samples {
            #expect(!sample.title.isEmpty)
            #expect(!sample.body.isEmpty)
        }
    }

    @Test func theRowPostsThreeDifferentNotifications() {
        let sequence = NotificationSample.sequence
        #expect(sequence.count == 3)
        #expect(Set(sequence.map(\.title)).count == 3)
    }
}
