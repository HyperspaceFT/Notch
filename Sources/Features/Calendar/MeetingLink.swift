import Foundation

/// Finds the link that joins an event's online meeting (Zoom and ZoomGov,
/// Google Meet, Teams, Tencent Meeting, VooV, Webex, Feishu, Lark, DingTalk)
/// in the event's fields.
enum MeetingLink {
    /// The first meeting link in `url` (an explicit URL field), then
    /// `conference` (such as X-GOOGLE-CONFERENCE), `location`, and `notes`
    /// (or an iCalendar DESCRIPTION). Nil when none holds one.
    static func detect(url: String?, conference: String?, location: String?, notes: String?) -> URL? {
        for field in [url, conference, location, notes] {
            if let field, let link = first(in: field) {
                return link
            }
        }
        return nil
    }

    /// The first https:// meeting link in `text`, skipping other links. A
    /// link ends at whitespace, quotes, angle brackets, or any non-ASCII
    /// character (so Chinese text right after it is left out), and trailing
    /// punctuation such as ")" or "." is trimmed.
    static func first(in text: String) -> URL? {
        var searchStart = text.startIndex
        while let range = text.range(of: "https://", options: .caseInsensitive, range: searchStart..<text.endIndex) {
            var end = range.upperBound
            while end < text.endIndex, !endsLink(text[end]) {
                end = text.index(after: end)
            }
            var candidate = text[range.lowerBound..<end]
            while let last = candidate.last, trailingPunctuation.contains(last) {
                candidate = candidate.dropLast()
            }
            if let url = URL(string: String(candidate)), isMeeting(url) {
                return url
            }
            searchStart = range.upperBound
        }
        return nil
    }

    /// Whether `url` is an https link to a meeting on one of the known services.
    static func isMeeting(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()
        // A service's home page is not a meeting.
        guard !path.isEmpty, path != "/" else { return false }
        if matches(host, "zoom.us") || matches(host, "zoomgov.com") {
            return zoomPathPrefixes.contains { path.hasPrefix($0) }
        }
        // Meetings are on a company's site (company.webex.com); www is marketing.
        if host.hasSuffix(".webex.com") {
            return host != "www.webex.com"
        }
        if matches(host, "teams.microsoft.com") || matches(host, "teams.live.com") {
            return path.contains("/meetup-join/") || path.hasPrefix("/meet/") || path.hasPrefix("/l/meet/")
        }
        return meetingHosts.contains { matches(host, $0) }
    }

    /// Hosts where any link with a path is a meeting.
    private static let meetingHosts = [
        "meet.google.com",
        "meeting.tencent.com",
        "voovmeeting.com",
        "vc.feishu.cn",
        "vc.larksuite.com",
        "meeting.dingtalk.com",
    ]

    /// Zoom meetings, personal rooms, webinars, and the web client.
    private static let zoomPathPrefixes = ["/j/", "/my/", "/w/", "/s/", "/wc/join/"]

    private static let trailingPunctuation: Set<Character> = [")", "]", "}", ">", ".", ",", ";", ":", "!", "?", "'", "\""]

    /// `host` is `domain` or one of its subdomains.
    private static func matches(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    private static func endsLink(_ character: Character) -> Bool {
        !character.isASCII || character.isWhitespace || character == "<" || character == ">"
            || character == "\"" || character == "'"
    }
}
