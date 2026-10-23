import Foundation

/// The address of a subscribed calendar feed, as the user pastes it.
enum SubscriptionAddress {
    /// The feed URL in `text`, trimmed, with webcal://, webcals:// and http://
    /// read as https:// (App Transport Security blocks plain http, so such a
    /// feed could never load). Nil unless it is http or https with a host.
    static func url(from text: String) -> URL? {
        var address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = address.lowercased()
        for scheme in ["webcals://", "webcal://", "http://"] where lowercased.hasPrefix(scheme) {
            address = "https://" + address.dropFirst(scheme.count)
            break
        }
        guard let url = URL(string: address),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(percentEncoded: false), !host.isEmpty
        else { return nil }
        return url
    }

    /// Only the host, such as "calendar.google.com": the path of a secret
    /// address is its password and is never shown.
    static func displayHost(of url: URL) -> String {
        url.host(percentEncoded: false) ?? ""
    }
}
