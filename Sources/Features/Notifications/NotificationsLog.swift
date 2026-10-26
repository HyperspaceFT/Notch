import os

extension Logger {
    /// Diagnostics for the notification path, from NotificationCenter's banners
    /// to the island, so a banner the island missed can be traced afterwards:
    ///
    ///     /usr/bin/log show --last 2h --predicate 'subsystem == "io.github.hyperspaceft.notch" AND category == "Notifications"'
    ///
    /// and set against what usernoted logged for the same minute. Notification
    /// text is never logged; app names are, to match the two. Raw Accessibility
    /// events are debug messages, which the system keeps only while streaming
    /// (`log stream --level debug`).
    static let notifications = Logger(subsystem: "io.github.hyperspaceft.notch", category: "Notifications")
}
