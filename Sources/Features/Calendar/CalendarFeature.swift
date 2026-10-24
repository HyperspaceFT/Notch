import NotchKit
import SwiftUI

/// Offers a Home module with the coming days' events from the Calendar app
/// (through EventKit) and from subscribed iCalendar feeds, such as a Google
/// Calendar or Outlook secret address. Has no tab of its own.
///
/// Also reminds of events beside the notch before they start (and as they
/// start), as `CalendarSettings.reminderLead` says, whether or not the module
/// is on Home; a click opens the island on the events in full
/// (`EventReminderDetailView`).
@MainActor
public final class CalendarFeature: NotchFeature {
    public let id = "calendar"
    public var title: String { localized(en: "Calendar", zh: "日历") }
    public let symbol = "calendar"

    static let reminderActivityID = "event-reminder"
    /// How long a reminder's activity stays visible.
    static let reminderDuration: TimeInterval = 10
    /// The longest the reminder loop sleeps, so events added meanwhile, a
    /// changed setting, and sleep or clock changes are caught within it.
    static let reminderCheckInterval: TimeInterval = 60
    /// How old a subscribed feed may get before the reminder loop downloads it
    /// again, so its reminders stay current while the island is closed.
    static let feedRefreshInterval: TimeInterval = 30 * 60
    /// How long a shown reminder is remembered after its event started.
    static let firedRetention: TimeInterval = 60 * 60

    private let settings = CalendarSettings.shared
    private let local = LocalCalendars.shared
    private let feeds = SubscriptionFeeds.shared
    private weak var context: (any NotchContext)?
    private var reminderLoop: Task<Void, Never>?
    /// The notice of the reminder activity last presented, until it is
    /// dismissed: a reminder held on an expanded island is withdrawn once its
    /// events are over.
    private var presentedNotice: EventReminderNotice?
    /// Reminders shown since launch, with their events' starts for pruning.
    private var firedReminders: [EventReminderKey: Date] = [:]

    public init() {}

    public func activate(context: any NotchContext) {
        self.context = context
        local.start()
        startReminders()
    }

    public func deactivate() {
        reminderLoop?.cancel()
        reminderLoop = nil
        presentedNotice = nil
        context?.dismiss(activityID: Self.reminderActivityID)
        context = nil
        local.stop()
        feeds.stop()
    }

    public func makeHomeModules() -> [NotchHomeModule] {
        [
            NotchHomeModule(
                id: "calendar",
                title: { localized(en: "Calendar", zh: "日历") },
                symbol: "calendar",
                detail: {
                    localized(
                        en: "Events from the Calendar app and subscribed calendars.",
                        zh: "日程来自「日历」App 和订阅的日历。"
                    )
                },
                sizing: .resizable(minimum: .fraction(1.0 / 3), maximum: nil),
                content: { size in
                    AnyView(CalendarModuleView(
                        settings: .shared,
                        local: .shared,
                        feeds: .shared,
                        size: size
                    ))
                }
            ),
        ]
    }

    // MARK: Reminders

    private func startReminders() {
        reminderLoop?.cancel()
        reminderLoop = Task { [weak self] in
            while true {
                guard !Task.isCancelled, let delay = self?.checkReminders(now: Date()) else { return }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Shows the reminders due at `now` and returns how many seconds to wait
    /// before the next check.
    private func checkReminders(now: Date) -> TimeInterval {
        firedReminders = firedReminders.filter { now.timeIntervalSince($0.value) < Self.firedRetention }
        if let presentedNotice, presentedNotice.endsAt <= now {
            dismissReminder()
        }
        guard let lead = settings.reminderLead.minutes else { return Self.reminderCheckInterval }
        // Never asks for access: local events count only once it is granted.
        local.refreshAccess()
        // A failed download is asked for again on every pass; `CalendarRefreshPolicy`
        // spaces the retries by its retry delay.
        if settings.subscriptions.contains(where: \.isEnabled),
           feeds.needsBackgroundRefresh(maximumAge: Self.feedRefreshInterval, now: now) {
            feeds.refreshIfNeeded()
        }
        let window = EventReminderPlanner.window(now: now, leadMinutes: lead)
        // Every calendar shown in settings, whatever the card's source switch says.
        let events = local.events(in: Self.stableWindow(around: window), hidden: settings.hiddenCalendarIDs)
            + feeds.events()
        let plan = EventReminderPlanner.plan(
            events: events,
            now: now,
            leadMinutes: lead,
            fired: Set(firedReminders.keys)
        )
        if let notice = plan.notice {
            for reminder in notice.reminders {
                firedReminders[reminder.key] = reminder.event.start
            }
            present(notice)
        }
        // Also wakes when the presented reminder's events are over.
        let untilNext = [plan.nextCheck, presentedNotice?.endsAt]
            .compactMap { $0?.timeIntervalSince(now) }
            .min() ?? Self.reminderCheckInterval
        return min(max(untilNext, 1), Self.reminderCheckInterval)
    }

    /// `window` widened to whole hours, so the EventKit query it keys stays
    /// cached between checks within the hour.
    private static func stableWindow(around window: DateInterval) -> DateInterval {
        let hour: TimeInterval = 3600
        let start = (window.start.timeIntervalSinceReferenceDate / hour).rounded(.down) * hour
        let end = (window.end.timeIntervalSinceReferenceDate / hour).rounded(.up) * hour
        return DateInterval(
            start: Date(timeIntervalSinceReferenceDate: start),
            end: Date(timeIntervalSinceReferenceDate: end)
        )
    }

    private func present(_ notice: EventReminderNotice) {
        let open: @MainActor () -> Void = { [weak self] in
            self?.openDetail(of: notice)
        }
        presentedNotice = notice
        // The same id replaces an earlier reminder still showing and restarts its
        // timer. Held while the island is expanded, so it is seen once it collapses.
        context?.present(NotchActivity(
            id: Self.reminderActivityID,
            priority: .high,
            duration: Self.reminderDuration,
            wingWidth: eventReminderWingWidth,
            holdsWhileExpanded: true
        ) {
            EventReminderWingLeading(notice: notice, open: open)
        } trailing: {
            EventReminderWingTrailing(notice: notice, open: open)
        })
    }

    /// Opens the island on the due events, in place of their activity.
    private func openDetail(of notice: EventReminderNotice) {
        context?.requestExpand(detail: AnyView(EventReminderDetailView(notice: notice)))
        dismissReminder()
    }

    private func dismissReminder() {
        presentedNotice = nil
        context?.dismiss(activityID: Self.reminderActivityID)
    }
}
