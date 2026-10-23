import AppKit
import CoreGraphics
import EventKit
import Observation
import SwiftUI

/// One of the Calendar app's event calendars, from any account the Mac has
/// (iCloud, Google, Exchange, On My Mac, …).
public struct LocalCalendar: Identifiable, Equatable, Sendable {
    /// EventKit's calendar identifier.
    public let id: String
    public let title: String
    /// The account it belongs to, such as "iCloud".
    public let sourceTitle: String
    let calendarColor: CalendarColor

    public var color: Color { calendarColor.color }
}

/// The Calendar app's calendars and events through EventKit, and whether
/// Notch may read them.
@MainActor
@Observable
public final class LocalCalendars {
    public static let shared = LocalCalendars()

    public enum Access: Sendable {
        case notDetermined
        case granted
        /// Denied, restricted, or write-only, none of which can read events.
        case denied
    }

    public private(set) var access: Access
    /// Event calendars, by account title and then title; empty without access.
    public private(set) var calendars: [LocalCalendar] = []
    /// Bumped whenever EventKit's data or the access changes, so cached events
    /// are read again and views showing them redraw.
    private var revision = 0

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    @ObservationIgnored private var isRequesting = false
    @ObservationIgnored private var cache: (key: CacheKey, events: [AgendaEvent])?

    private struct CacheKey: Equatable {
        var window: DateInterval
        var hidden: Set<String>
        var revision: Int
    }

    private init() {
        access = Self.currentAccess()
        if access == .granted {
            calendars = loadCalendars()
        }
    }

    /// Follows changes to the Calendar app's data until `stop()`.
    func start() {
        guard observer == nil else { return }
        // Queue .main delivers the notification on the main thread, so the
        // block runs on the main actor.
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.storeChanged()
            }
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        cache = nil
    }

    /// Shows the system's prompt while the user has not decided yet.
    public func requestAccess() {
        guard !isRequesting else { return }
        isRequesting = true
        // The completion runs on an arbitrary queue: it only hops back to the
        // main actor, where the store lives, and re-reads the status there.
        store.requestFullAccessToEvents { @Sendable [weak self] _, _ in
            Task { @MainActor in
                self?.isRequesting = false
                self?.refreshAccess()
            }
        }
    }

    /// Reads the access again, since the user grants or revokes it in System
    /// Settings. Only a real change notifies observers.
    public func refreshAccess() {
        let current = Self.currentAccess()
        guard current != access else { return }
        access = current
        if current == .granted {
            // A store created before access was granted may not see any data.
            store.reset()
            calendars = loadCalendars()
        } else {
            calendars = []
        }
        revision += 1
    }

    /// Opens System Settings at Privacy & Security → Calendars.
    public func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Events of the calendars not in `hidden` that overlap `window`, skipping
    /// cancelled ones and those the user declined. Cached by window, hidden set,
    /// and revision, so a redraw does not query EventKit again.
    func events(in window: DateInterval, hidden: Set<String>) -> [AgendaEvent] {
        let key = CacheKey(window: window, hidden: hidden, revision: revision)
        if let cache, cache.key == key { return cache.events }
        let events = queryEvents(in: window, hidden: hidden)
        cache = (key, events)
        return events
    }

    private func queryEvents(in window: DateInterval, hidden: Set<String>) -> [AgendaEvent] {
        guard access == .granted else { return [] }
        let visible = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        // An empty list must not reach the predicate, where nil means every calendar.
        guard !visible.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: visible)
        return store.events(matching: predicate).compactMap { event in
            guard event.status != .canceled,
                  !(event.attendees ?? []).contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }),
                  let start = event.startDate, let end = event.endDate
            else { return nil }
            let calendar = event.calendar
            let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            return AgendaEvent(
                // The item identifier is shared by a recurring event's occurrences.
                id: "ek:\(event.calendarItemIdentifier):\(start.timeIntervalSince1970)",
                title: event.title ?? "",
                location: location?.isEmpty == false ? location : nil,
                start: start,
                end: end,
                isAllDay: event.isAllDay,
                color: Self.color(of: calendar?.cgColor),
                calendarTitle: calendar?.title ?? ""
            )
        }
    }

    private func storeChanged() {
        if access == .granted {
            calendars = loadCalendars()
        }
        revision += 1
    }

    private func loadCalendars() -> [LocalCalendar] {
        store.calendars(for: .event)
            .map { calendar in
                LocalCalendar(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source?.title ?? "",
                    calendarColor: Self.color(of: calendar.cgColor)
                )
            }
            .sorted { first, second in
                let sources = first.sourceTitle.localizedStandardCompare(second.sourceTitle)
                if sources != .orderedSame { return sources == .orderedAscending }
                return first.title.localizedStandardCompare(second.title) == .orderedAscending
            }
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess: .granted
        case .denied, .restricted, .writeOnly: .denied
        @unknown default: .denied
        }
    }

    /// The calendar's color in sRGB; gray when it has none or cannot convert.
    private static func color(of cgColor: CGColor?) -> CalendarColor {
        guard let cgColor,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 3
        else { return CalendarColor(red: 0.56, green: 0.56, blue: 0.58) }
        return CalendarColor(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }
}
