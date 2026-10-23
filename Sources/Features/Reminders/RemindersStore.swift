import AppKit
import CoreGraphics
import EventKit
import Observation

/// The Reminders app's incomplete reminders through EventKit, whether Notch may
/// read them, and the changes the card makes to them.
@MainActor
@Observable
final class RemindersStore {
    static let shared = RemindersStore()

    enum Access: Sendable {
        case notDetermined
        case granted
        /// Denied, restricted, or write-only, none of which can read reminders.
        case denied
    }

    /// How long a ticked-off reminder waits before it is written as completed.
    static let completionDelay: Duration = .milliseconds(1500)

    private(set) var access: Access
    /// Incomplete reminders of every list, in `ReminderItem.ordered` order.
    private(set) var items: [ReminderItem] = []
    /// Whether a fetch has delivered since access was last granted.
    private(set) var hasFetched = false

    /// Observable itself, so rows redraw as reminders are ticked off.
    @ObservationIgnored private(set) lazy var completions = CompletionQueue(delay: Self.completionDelay) { [weak self] id in
        self?.complete(id)
    }

    /// Replaced when access is granted (see `apply(_:)`).
    @ObservationIgnored private var store = EKEventStore()
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    @ObservationIgnored private var isRequesting = false
    /// Bumped by every fetch, so results a newer fetch superseded are dropped.
    @ObservationIgnored private var generation = 0

    private init() {
        access = Self.currentAccess()
    }

    /// Follows changes to the Reminders app's data until `stop()`.
    func start() {
        guard observer == nil else { return }
        observeStore()
    }

    /// Writes the reminders still waiting to be completed, then stops following changes.
    func stop() {
        completions.flush()
        stopObservingStore()
    }

    private func observeStore() {
        // Queue .main delivers the notification on the main thread, so the
        // block runs on the main actor.
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fetch()
            }
        }
    }

    private func stopObservingStore() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }

    /// Shows the system's prompt while the user has not decided yet.
    func requestAccess() {
        guard !isRequesting else { return }
        isRequesting = true
        // The completion runs on an arbitrary queue: it only hops back to the
        // main actor, where the store lives, and applies the answer there.
        store.requestFullAccessToReminders { @Sendable [weak self] granted, _ in
            Task { @MainActor in
                self?.isRequesting = false
                // The prompt's answer, not the status read again: right after the
                // user allowed access, that status still said not determined, and
                // the card kept asking (macOS 26).
                self?.apply(granted ? .granted : Self.currentAccess())
            }
        }
    }

    /// Reads the access again, since the user grants or revokes it in System
    /// Settings. Only a real change notifies observers.
    func refreshAccess() {
        let current = Self.currentAccess()
        // Access never goes back to not determined by itself, so after a grant
        // that reading is the stale one `requestAccess` works around.
        guard !(current == .notDetermined && access == .granted) else { return }
        apply(current)
    }

    private func apply(_ current: Access) {
        guard current != access else { return }
        access = current
        if current == .granted {
            // Read through a new store: one made before access was granted may
            // keep answering from what it knew then, as the status above does.
            store = EKEventStore()
            if observer != nil {
                stopObservingStore()
                observeStore()
            }
            fetch()
        } else {
            generation &+= 1
            items = []
            hasFetched = false
        }
    }

    /// Opens System Settings at Privacy & Security → Reminders.
    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Opens the Reminders app.
    func openRemindersApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Fetches unless a fetch has already delivered, for a card that appears.
    func fetchIfNeeded() {
        guard !hasFetched else { return }
        fetch()
    }

    /// Reads every list's incomplete reminders again.
    func fetch() {
        guard access == .granted else { return }
        generation &+= 1
        let generation = generation
        let calendar = Calendar.current
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        // The handler runs on a background queue, and EKReminder is not Sendable:
        // the reminders become values there, and only those cross to the main actor.
        _ = store.fetchReminders(matching: predicate) { @Sendable [weak self] reminders in
            // `nil` when the fetch failed: the list stays as it was rather than
            // turning empty, and until one delivers, a card fetches again (`fetchIfNeeded`).
            guard let reminders else { return }
            let fetched = reminders.map { Self.item(from: $0, calendar: calendar) }
            Task { @MainActor in
                guard let self, self.generation == generation, self.access == .granted else { return }
                self.items = ReminderItem.ordered(fetched)
                self.hasFetched = true
            }
        }
    }

    /// Creates a reminder in the default list, without a due date. Returns its
    /// identifier, or `nil` when the title is blank or nothing was written.
    func add(title: String) -> String? {
        guard access == .granted,
              let title = ReminderItem.normalizedTitle(title),
              let calendar = store.defaultCalendarForNewReminders()
        else { return nil }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar
        do {
            try store.save(reminder, commit: true)
        } catch {
            return nil
        }
        fetch()
        return reminder.calendarItemIdentifier
    }

    /// Deletes a reminder; a completion still pending for it is dropped, not written.
    func delete(_ id: String) {
        completions.cancel(id)
        guard access == .granted,
              let reminder = store.calendarItem(withIdentifier: id) as? EKReminder
        else { return }
        do {
            try store.remove(reminder, commit: true)
            items.removeAll { $0.id == id }
        } catch {}
        fetch()
    }

    /// Writes a ticked-off reminder as completed, unless it is gone or already done.
    private func complete(_ id: String) {
        guard access == .granted else { return }
        if let reminder = store.calendarItem(withIdentifier: id) as? EKReminder, !reminder.isCompleted {
            reminder.isCompleted = true
            do {
                try store.save(reminder, commit: true)
                // Gone at once rather than unticked until the fetch below delivers.
                items.removeAll { $0.id == id }
            } catch {}
        }
        fetch()
    }

    private nonisolated static func item(from reminder: EKReminder, calendar: Calendar) -> ReminderItem {
        let list = reminder.calendar
        return ReminderItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            due: ReminderDue(components: reminder.dueDateComponents, calendar: calendar),
            created: reminder.creationDate,
            color: color(of: list?.cgColor),
            listTitle: list?.title ?? ""
        )
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: .notDetermined
        case .fullAccess: .granted
        case .denied, .restricted, .writeOnly: .denied
        @unknown default: .denied
        }
    }

    /// The list's color in sRGB; gray when it has none or cannot convert.
    private nonisolated static func color(of cgColor: CGColor?) -> ReminderColor {
        guard let cgColor,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 3
        else { return ReminderColor(red: 0.56, green: 0.56, blue: 0.58) }
        return ReminderColor(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }
}
