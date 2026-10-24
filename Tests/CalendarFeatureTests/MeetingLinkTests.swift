import Foundation
import Testing
@testable import CalendarFeature

private func link(url: String? = nil, conference: String? = nil, location: String? = nil, notes: String? = nil) -> String? {
    MeetingLink.detect(url: url, conference: conference, location: location, notes: notes)?.absoluteString
}

struct MeetingLinkTests {
    @Test func zoomLinkInDescriptionLosesTrailingPunctuation() {
        #expect(link(notes: "Join Zoom (https://us02web.zoom.us/j/8123456789?pwd=abc) to talk")
            == "https://us02web.zoom.us/j/8123456789?pwd=abc")
        #expect(link(notes: "Link: <https://zoom.us/j/8123456789>\nSee you")
            == "https://zoom.us/j/8123456789")
    }

    @Test func meetLinkInLocation() {
        #expect(link(location: "https://meet.google.com/abc-defg-hij") == "https://meet.google.com/abc-defg-hij")
    }

    @Test func teamsMeetupJoin() {
        let teams = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d"
        #expect(link(notes: "Microsoft Teams meeting\nJoin: \(teams)\nMeeting ID: 123") == teams)
    }

    @Test func tencentMeeting() {
        #expect(link(notes: "点击链接入会：https://meeting.tencent.com/dm/AbCdEf123。会议号：123")
            == "https://meeting.tencent.com/dm/AbCdEf123")
    }

    @Test func zoomGovAndTheWebClientAreMeetings() {
        #expect(link(notes: "https://agency.zoomgov.com/j/1612345678") == "https://agency.zoomgov.com/j/1612345678")
        #expect(link(notes: "https://zoom.us/wc/join/8123456789") == "https://zoom.us/wc/join/8123456789")
    }

    @Test func webexNeedsACompanySite() {
        #expect(link(notes: "https://www.webex.com/pricing") == nil)
        #expect(link(notes: "https://company.webex.com/meet/name") == "https://company.webex.com/meet/name")
    }

    @Test func plainHTTPIsIgnored() {
        #expect(link(notes: "http://zoom.us/j/8123456789") == nil)
    }

    @Test func unrelatedLinksAreIgnored() {
        #expect(link(location: "https://example.com/j/123", notes: "Agenda: https://docs.google.com/document/d/1") == nil)
        #expect(link(notes: "Agenda https://example.com/a then https://zoom.us/j/1") == "https://zoom.us/j/1")
    }

    @Test func explicitURLFieldComesFirst() {
        #expect(link(url: "https://meet.google.com/aaa-bbbb-ccc", notes: "https://zoom.us/j/8123456789")
            == "https://meet.google.com/aaa-bbbb-ccc")
    }

    @Test func fieldsAreCheckedInOrder() {
        #expect(link(
            conference: "https://meet.google.com/aaa-bbbb-ccc",
            location: "https://zoom.us/j/1",
            notes: "https://zoom.us/j/2"
        ) == "https://meet.google.com/aaa-bbbb-ccc")
        #expect(link(location: "https://zoom.us/j/1", notes: "https://zoom.us/j/2") == "https://zoom.us/j/1")
    }

    @Test func icsDescriptionYieldsMeetingURL() throws {
        let text = feedText(vevent(
            "UID:1",
            "DTSTART:20261022T090000Z",
            "DTEND:20261022T100000Z",
            "SUMMARY:Sync",
            #"DESCRIPTION:Join Zoom Meeting\nhttps://zoom.us/j/8123456789?pwd=xyz\n\nMeeting ID: 812"#
        ))
        let feed = ICalendar.parse(text, defaultTimeZone: .gmt)
        let event = try #require(feed.events.first)
        #expect(event.meetingURL?.absoluteString == "https://zoom.us/j/8123456789?pwd=xyz")
        let window = DateInterval(start: instant(2026, 10, 22, in: .gmt), duration: 86_400)
        #expect(feed.occurrences(overlapping: window).first?.meetingURL == event.meetingURL)
    }

    @Test func icsGoogleConferenceYieldsMeetingURL() throws {
        let text = feedText(vevent(
            "UID:2",
            "DTSTART:20261022T090000Z",
            "SUMMARY:Planning",
            "X-GOOGLE-CONFERENCE:https://meet.google.com/xyz-abcd-efg"
        ))
        let event = try #require(ICalendar.parse(text, defaultTimeZone: .gmt).events.first)
        #expect(event.meetingURL?.absoluteString == "https://meet.google.com/xyz-abcd-efg")
    }

    @Test func icsEventWithoutLinkHasNone() throws {
        let text = feedText(vevent("UID:3", "DTSTART:20261022T090000Z", "SUMMARY:Lunch", "LOCATION:Cafe"))
        #expect(try #require(ICalendar.parse(text, defaultTimeZone: .gmt).events.first).meetingURL == nil)
    }
}
