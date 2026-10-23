import Foundation
import Observation
import SwiftUI

/// What the Home calendar module shows, as the settings window edits it: how
/// many days, which of the Calendar app's calendars, and the subscribed feeds.
@MainActor
@Observable
public final class CalendarSettings {
    public static let shared = CalendarSettings(defaults: .standard)

    static let dayCountKey = "NotchCalendarDayCount"
    static let hiddenCalendarsKey = "NotchCalendarHiddenCalendars"
    static let subscriptionsKey = "NotchCalendarSubscriptions"
    static let defaultDayCount = 3

    /// How many days, today included, the module may show.
    public static var dayCountRange: ClosedRange<Int> { Agenda.dayCountRange }

    /// Days the module shows, today included; kept in `dayCountRange` and saved
    /// on every change.
    public var dayCount: Int {
        get { storedDayCount }
        set {
            let clamped = min(max(newValue, Self.dayCountRange.lowerBound), Self.dayCountRange.upperBound)
            guard clamped != storedDayCount else { return }
            storedDayCount = clamped
            defaults.set(clamped, forKey: Self.dayCountKey)
        }
    }

    /// EventKit calendar identifiers the user turned off. Stored as hidden rather
    /// than shown, so a calendar added later shows by default.
    public private(set) var hiddenCalendarIDs: Set<String> {
        didSet { defaults.set(hiddenCalendarIDs.sorted(), forKey: Self.hiddenCalendarsKey) }
    }

    /// Subscribed iCalendar feeds, in the order they were added.
    public private(set) var subscriptions: [CalendarSubscription] {
        didSet {
            if let data = try? JSONEncoder().encode(subscriptions) {
                defaults.set(data, forKey: Self.subscriptionsKey)
            }
        }
    }

    private var storedDayCount: Int
    @ObservationIgnored private let defaults: UserDefaults

    /// Saved values that do not decode fall back to the defaults.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        let savedDayCount = defaults.object(forKey: Self.dayCountKey) as? Int
        storedDayCount = savedDayCount.map {
            min(max($0, Self.dayCountRange.lowerBound), Self.dayCountRange.upperBound)
        } ?? Self.defaultDayCount
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: Self.hiddenCalendarsKey) ?? [])
        subscriptions = defaults.data(forKey: Self.subscriptionsKey)
            .flatMap { try? JSONDecoder().decode([CalendarSubscription].self, from: $0) }
            ?? []
    }

    // MARK: Calendar app

    public func isCalendarShown(_ id: String) -> Bool {
        !hiddenCalendarIDs.contains(id)
    }

    public func setCalendar(_ id: String, shown: Bool) {
        if shown {
            hiddenCalendarIDs.remove(id)
        } else {
            hiddenCalendarIDs.insert(id)
        }
    }

    // MARK: Subscriptions

    /// Whether `address` is a feed address not subscribed yet.
    public func canAddSubscription(address: String) -> Bool {
        guard let url = SubscriptionAddress.url(from: address) else { return false }
        return !subscriptions.contains { $0.address == url.absoluteString }
    }

    /// Subscribes to the feed at `address` (webcal:// and http:// read as https://) under
    /// `name`, trimmed; an empty name shows the feed's own. False, and nothing
    /// added, for an invalid address or one already subscribed.
    @discardableResult
    public func addSubscription(name: String, address: String) -> Bool {
        guard canAddSubscription(address: address), let url = SubscriptionAddress.url(from: address) else {
            return false
        }
        let used = Set(subscriptions.map(\.colorIndex))
        let palette = CalendarSubscription.palette.count
        let colorIndex = (0..<palette).first { !used.contains($0) } ?? subscriptions.count % palette
        subscriptions.append(CalendarSubscription(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            address: url.absoluteString,
            isEnabled: true,
            colorIndex: colorIndex
        ))
        return true
    }

    public func removeSubscription(id: UUID) {
        subscriptions.removeAll { $0.id == id }
    }

    public func setSubscription(id: UUID, enabled: Bool) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }),
              subscriptions[index].isEnabled != enabled
        else { return }
        subscriptions[index].isEnabled = enabled
    }

    /// An empty name falls back to the feed's own.
    public func renameSubscription(id: UUID, to name: String) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A subscribed iCalendar feed, such as a Google Calendar or Outlook secret
/// address. The address is a password: only its host is ever shown.
public struct CalendarSubscription: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The user's name for it; empty to use the feed's own.
    public internal(set) var name: String
    /// The normalized feed URL (https:// for a pasted webcal:// or http:// one).
    public let address: String
    public internal(set) var isEnabled: Bool
    /// Slot in `palette`: the first one no other subscription used when added.
    public let colorIndex: Int

    /// Subscription colors, in the order new subscriptions take them.
    static let palette: [CalendarColor] = [
        CalendarColor(red: 0.0, green: 0.478, blue: 1.0),
        CalendarColor(red: 0.204, green: 0.78, blue: 0.349),
        CalendarColor(red: 1.0, green: 0.584, blue: 0.0),
        CalendarColor(red: 0.686, green: 0.322, blue: 0.871),
        CalendarColor(red: 1.0, green: 0.231, blue: 0.188),
        CalendarColor(red: 0.188, green: 0.69, blue: 0.78),
        CalendarColor(red: 1.0, green: 0.8, blue: 0.0),
        CalendarColor(red: 1.0, green: 0.176, blue: 0.333),
    ]

    var calendarColor: CalendarColor {
        let count = Self.palette.count
        return Self.palette[(colorIndex % count + count) % count]
    }

    public var color: Color { calendarColor.color }

    /// Only the host, such as "calendar.google.com".
    public var displayHost: String {
        URL(string: address).map(SubscriptionAddress.displayHost(of:)) ?? ""
    }

    /// The user's name, else the feed's X-WR-CALNAME, else the host.
    public func displayName(feedName: String?) -> String {
        if !name.isEmpty { return name }
        if let feedName = feedName?.trimmingCharacters(in: .whitespacesAndNewlines), !feedName.isEmpty {
            return feedName
        }
        return displayHost
    }

    /// The feed's occurrences as agenda events in this subscription's color and
    /// under its display name. Ids are "sub:" + subscription + UID + start; a
    /// feed may repeat a UID at one start (two masters sharing it), so repeats
    /// get a counter to stay unique.
    func agendaEvents(from occurrences: [ICalendarOccurrence], feedName: String?) -> [AgendaEvent] {
        let calendarTitle = displayName(feedName: feedName)
        var counts: [String: Int] = [:]
        return occurrences.map { occurrence in
            var eventID = "sub:\(id.uuidString):\(occurrence.uid):\(occurrence.start.timeIntervalSince1970)"
            let seen = counts[eventID, default: 0]
            counts[eventID] = seen + 1
            if seen > 0 { eventID += "#\(seen)" }
            return AgendaEvent(
                id: eventID,
                title: occurrence.title,
                location: occurrence.location,
                start: occurrence.start,
                end: occurrence.end,
                isAllDay: occurrence.isAllDay,
                color: calendarColor,
                calendarTitle: calendarTitle
            )
        }
    }
}

extension CalendarColor {
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue)
    }
}
