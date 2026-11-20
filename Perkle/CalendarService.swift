import EventKit
import SwiftUI

/// Reads events from every calendar account on this Mac (Google, Microsoft 365 /
/// Exchange, iCloud…) through EventKit. Add accounts in
/// System Settings › Internet Accounts and they show up here automatically.
@MainActor
final class CalendarService: ObservableObject {
    let store = EKEventStore()

    @Published private(set) var status: EKAuthorizationStatus = .notDetermined
    @Published private(set) var calendars: [EKCalendar] = []

    /// Called whenever calendars or events change.
    var onChange: (() -> Void)?

    private var changeToken: NSObjectProtocol?

    init() {
        refreshStatus()
        changeToken = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshStatus()
                self.onChange?()
            }
        }
    }

    var hasAccess: Bool { status == .fullAccess }
    var needsPrompt: Bool { status == .notDetermined }
    var isBlocked: Bool { !hasAccess && !needsPrompt }

    var statusText: String {
        switch status {
        case .fullAccess: return "Connected"
        case .notDetermined: return "Not connected yet"
        case .writeOnly: return "\(AppInfo.name) can’t read events (write-only access)"
        case .denied: return "Access was turned off"
        case .restricted: return "Access is restricted on this Mac"
        @unknown default: return "Unknown"
        }
    }

    func refreshStatus() {
        status = EKEventStore.authorizationStatus(for: .event)
        if hasAccess {
            calendars = store.calendars(for: .event).sorted {
                let a = ($0.source?.title ?? "", $0.title)
                let b = ($1.source?.title ?? "", $1.title)
                return a < b
            }
        } else {
            calendars = []
        }
    }

    /// Shows the system permission prompt (only the first time).
    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            store.reset()
            refreshStatus()
            return granted
        } catch {
            NSLog("\(AppInfo.name): calendar access request failed: \(error.localizedDescription)")
            refreshStatus()
            return false
        }
    }

    /// Timed events that make you busy between `start` and `end`.
    /// Skips all-day events, events marked "free", cancelled events and
    /// invitations you declined.
    func busyBlocks(from start: Date, to end: Date, excluding excluded: Set<String>) -> [BusyBlock] {
        guard hasAccess else { return [] }
        let cals = store.calendars(for: .event).filter { !excluded.contains($0.calendarIdentifier) }
        guard !cals.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: cals)
        return store.events(matching: predicate)
            .compactMap { event -> BusyBlock? in
                guard let s = event.startDate, let e = event.endDate, e > s else { return nil }
                if event.isAllDay { return nil }
                if event.availability == .free { return nil }
                if event.status == .canceled { return nil }
                if let me = event.attendees?.first(where: { $0.isCurrentUser }),
                   me.participantStatus == .declined { return nil }
                return BusyBlock(start: s,
                                 end: e,
                                 title: event.title ?? "Busy",
                                 calendarName: event.calendar?.title ?? "")
            }
            .sorted { $0.start < $1.start }
    }
}
