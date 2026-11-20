import Foundation

/// A stretch of time when a nudge must not appear (a calendar event).
struct BusyBlock: Equatable {
    let start: Date
    let end: Date
    let title: String
    let calendarName: String
}

/// Pure scheduling logic: given when you sat down, your settings and your
/// meetings, when should Pip nudge you next?
enum Scheduler {
    /// How early to nudge before a meeting when we move a nudge forward.
    static let preMeetingLead: TimeInterval = 2 * 60
    /// How long after a meeting ends to nudge.
    static let postMeetingDelay: TimeInterval = 60
    /// Never schedule closer than this to "now".
    static let minimumLead: TimeInterval = 30

    /// The working window on the day containing `date`, or nil if that day is off.
    static func window(on date: Date, settings: AppSettings, calendar: Calendar) -> DateInterval? {
        let weekday = calendar.component(.weekday, from: date)
        guard settings.activeWeekdays.contains(weekday) else { return nil }
        let startM = min(max(settings.startMinutes, 0), 24 * 60 - 1)
        let endM = min(max(settings.endMinutes, 0), 24 * 60 - 1)
        guard endM > startM,
              let start = calendar.date(bySettingHour: startM / 60, minute: startM % 60, second: 0, of: date),
              let end = calendar.date(bySettingHour: endM / 60, minute: endM % 60, second: 0, of: date),
              end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func isWorking(_ date: Date, settings: AppSettings, calendar: Calendar = .current) -> Bool {
        guard let w = window(on: date, settings: settings, calendar: calendar) else { return false }
        return w.start <= date && date < w.end
    }

    /// The first working window that starts after `date` (looks up to 8 days ahead).
    static func nextWindow(after date: Date, settings: AppSettings, calendar: Calendar) -> DateInterval? {
        for offset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date),
                  let w = window(on: day, settings: settings, calendar: calendar) else { continue }
            if w.start > date { return w }
        }
        return nil
    }

    /// When to nudge next.
    /// - Parameters:
    ///   - sittingSince: when the current sitting stretch began (last stand, wake, start of day).
    ///   - now: the current time.
    ///   - busy: meetings to avoid (pass [] to ignore calendars).
    /// - Returns: nil if there is no working time in the next week.
    static func nextNudge(sittingSince: Date,
                          now: Date,
                          settings: AppSettings,
                          busy: [BusyBlock],
                          calendar: Calendar = .current) -> Date? {
        let interval = TimeInterval(max(settings.intervalMinutes, 5) * 60)
        var base = sittingSince
        var candidate = max(base.addingTimeInterval(interval), now.addingTimeInterval(minimumLead))

        for _ in 0..<96 {
            // 1. Only inside working hours. Outside them, the clock restarts
            //    at the start of the next working window.
            if !isWorking(candidate, settings: settings, calendar: calendar) {
                guard let w = nextWindow(after: candidate, settings: settings, calendar: calendar) else { return nil }
                base = w.start
                let lead = min(interval, max(w.duration - 60, 60))
                candidate = max(w.start.addingTimeInterval(lead), now.addingTimeInterval(minimumLead))
                continue
            }

            // 2. Never during a meeting.
            if let block = busy.first(where: { $0.start <= candidate && candidate < $0.end }) {
                let early = block.start.addingTimeInterval(-preMeetingLead)
                if settings.standBeforeMeetings,
                   early > now.addingTimeInterval(minimumLead),
                   early >= base.addingTimeInterval(interval * 0.6),
                   !busy.contains(where: { $0.start <= early && early < $0.end }),
                   isWorking(early, settings: settings, calendar: calendar) {
                    return early
                }
                candidate = block.end.addingTimeInterval(postMeetingDelay)
                continue
            }

            return candidate
        }
        return candidate
    }

    /// The next meeting that starts within `window` seconds of `now`.
    static func meetingSoon(in busy: [BusyBlock], now: Date, within window: TimeInterval = 30 * 60) -> BusyBlock? {
        busy.first { $0.start > now && $0.start.timeIntervalSince(now) <= window }
    }

    /// A meeting in progress at `now`, if any.
    static func meetingNow(in busy: [BusyBlock], now: Date) -> BusyBlock? {
        busy.first { $0.start <= now && now < $0.end }
    }
}
