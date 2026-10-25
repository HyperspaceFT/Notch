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
    /// punctuation such as ")" or "." is trimmed. A candidate longer than
    /// `maximumLinkLength` is not a meeting link and is skipped, and no more
    /// than `maximumCandidates` are read.
    static func first(in text: String) -> URL? {
        // Native UTF-8 storage makes the byte distances below constant-time.
        var text = text
        text.makeContiguousUTF8()
        var searchStart = text.startIndex
        var candidates = 0
        // Where the whitespace-free run containing the latest match ends: every
        // match inside that run ends there too, so the run is scanned once
        // however many "https://" it holds (a text of nothing else is a run
        // with one match per eight characters).
        var runEnd = text.startIndex
        while let range = text.range(of: "https://", options: .caseInsensitive, range: searchStart..<text.endIndex) {
            if range.upperBound > runEnd {
                runEnd = range.upperBound
                while runEnd < text.endIndex, !endsLink(text[runEnd]) {
                    runEnd = text.index(after: runEnd)
                }
            }
            let end = runEnd
            // A link is ASCII, so its UTF-8 length is its character count.
            if text.utf8.distance(from: range.lowerBound, to: end) > maximumLinkLength {
                // No match before this point can be short enough.
                let fits = text.utf8.index(end, offsetBy: -maximumLinkLength)
                searchStart = max(range.upperBound, fits)
                continue
            }
            guard candidates < maximumCandidates else { return nil }
            candidates += 1
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

    /// The longest link `first(in:)` considers, counted before trailing
    /// punctuation is trimmed. Real meeting links, Teams meetup-join and
    /// SafeLinks-wrapped ones included, are far shorter; the bound keeps one
    /// huge unbroken run of text (an invitation controls its description) from
    /// being parsed as a URL again and again.
    static let maximumLinkLength = 2_048

    /// The most candidates `first(in:)` parses as URLs in one text. Each short
    /// "https://" inside a run is a candidate of its own, so a text made of
    /// nothing else would otherwise cost about half a second per megabyte,
    /// on the main thread for a local event; an invitation's notes hold a
    /// handful of links.
    static let maximumCandidates = 256

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
