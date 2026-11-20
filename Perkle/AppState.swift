import SwiftUI
import AppKit
import Combine
import CoreGraphics
import ServiceManagement

struct DayStat: Identifiable {
    let id: String
    let label: String
    let count: Int
    let isToday: Bool
}

/// The brain of the app: settings, the timer, idle detection and what to show.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private static let settingsKey = "settings.v1"
    private static let onboardedKey = "hasOnboarded.v1"

    // MARK: Published state

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            saveSettings()
            if settings.useCalendars != oldValue.useCalendars
                || settings.excludedCalendarIDs != oldValue.excludedCalendarIDs {
                refreshCalendar()
            } else {
                reschedule()
            }
        }
    }

    @Published private(set) var log: StandLog
    @Published private(set) var now = Date()
    @Published private(set) var nextNudge: Date?
    @Published private(set) var sittingSince = Date()
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var busy: [BusyBlock] = []
    @Published private(set) var whisperActive = false
    @Published private(set) var wiggle = false
    @Published private(set) var launchAtLogin = false
    @Published var nudgeVisible = false
    @Published var settingsSection: SettingsSection = .schedule

    let calendarService: CalendarService

    // MARK: Private

    private var tickTimer: Timer?
    private var wiggleTimer: Timer?
    private var whisperEnds: Date?
    private var awaySince: Date?
    private var lastCalendarRefresh = Date.distantPast
    private var started = false
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        calendarService = CalendarService()
        settings = AppState.loadSettings()
        log = StandLog.load()
        launchAtLogin = SMAppService.mainApp.status == .enabled

        // Re-render anything showing calendar status when it changes.
        calendarService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true

        calendarService.onChange = { [weak self] in
            self?.refreshCalendar()
        }

        sittingSince = Date()
        refreshCalendar()

        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer

        observeSleepAndLock()

        if !UserDefaults.standard.bool(forKey: Self.onboardedKey) {
            WindowManager.shared.showWelcome()
        }
    }

    var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: Self.onboardedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.onboardedKey) }
    }

    private func observeSleepAndLock() {
        let ws = NSWorkspace.shared.notificationCenter
        let away: [Notification.Name] = [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification]
        let back: [Notification.Name] = [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification]

        for name in away {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.wentAway() }
            })
        }
        for name in back {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cameBack() }
            })
        }

        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                         object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.wentAway() }
        })
        observers.append(dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"),
                                         object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cameBack() }
        })
    }

    // MARK: Timer

    private func tick() {
        let current = Date()
        now = current

        if let until = pausedUntil, current >= until {
            pausedUntil = nil
            sittingSince = current
            reschedule()
        }

        checkIdle()

        if current.timeIntervalSince(lastCalendarRefresh) > 5 * 60 {
            refreshCalendar()
        }

        guard pausedUntil == nil,
              awaySince == nil,
              !nudgeVisible,
              !whisperActive,
              let due = nextNudge,
              current >= due else { return }

        // Last-moment checks: a meeting may have been added, or hours changed.
        if settings.quietInMeetings, Scheduler.meetingNow(in: busy, now: current) != nil {
            reschedule()
            return
        }
        if !Scheduler.isWorking(current, settings: settings) {
            reschedule()
            return
        }
        fire()
    }

    private func fire() {
        if settings.playSound {
            NSSound(named: NSSound.Name("Pop"))?.play()
        }
        switch settings.loudness {
        case .whisper:
            startWhisper()
        case .nudge:
            WindowManager.shared.showNudge()
        case .insist:
            WindowManager.shared.showInsist()
        }
    }

    // MARK: Idle, sleep and lock

    private func checkIdle() {
        guard settings.idleResetMinutes > 0,
              let anyInput = CGEventType(rawValue: ~0) else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if idle >= Double(settings.idleResetMinutes * 60) {
            if awaySince == nil {
                awaySince = Date().addingTimeInterval(-idle)
            }
        } else if idle < 20, awaySince != nil {
            cameBack()
        }
    }

    private func wentAway() {
        if awaySince == nil { awaySince = Date() }
    }

    private func cameBack() {
        guard let since = awaySince else { return }
        awaySince = nil
        let minutesAway = Date().timeIntervalSince(since) / 60
        let threshold = Double(max(settings.idleResetMinutes, 2))
        guard minutesAway >= threshold else { return }

        // Time away from the desk counts as a break.
        if settings.idleResetMinutes > 0, Scheduler.isWorking(since, settings: settings) {
            log.add(on: Date())
            log.save()
        }
        stopWhisper()
        WindowManager.shared.closeAlerts()
        sittingSince = Date()
        reschedule()
    }

    // MARK: Whisper (menu bar only)

    private func startWhisper() {
        whisperActive = true
        whisperEnds = Date().addingTimeInterval(TimeInterval(settings.autoDismissSeconds))
        wiggleTimer?.invalidate()
        let timer = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.wiggle.toggle()
                if let end = self.whisperEnds, Date() >= end {
                    self.noResponse()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        wiggleTimer = timer
    }

    private func stopWhisper() {
        wiggleTimer?.invalidate()
        wiggleTimer = nil
        whisperEnds = nil
        whisperActive = false
        wiggle = false
    }

    // MARK: Actions

    /// You stood up. Counts toward today's goal and restarts the clock.
    func stoodUp() {
        log.add(on: Date())
        log.save()
        stopWhisper()
        sittingSince = Date()
        reschedule()
    }

    /// Ask again in a few minutes.
    func snooze() {
        stopWhisper()
        nextNudge = Date().addingTimeInterval(TimeInterval(settings.snoozeMinutes * 60))
    }

    /// Dismiss without credit; restart the clock.
    func skip() {
        stopWhisper()
        sittingSince = Date()
        reschedule()
    }

    /// The nudge timed out with no answer: close it and ask again after the snooze time.
    func noResponse() {
        WindowManager.shared.closeAlerts()
        snooze()
    }

    func pause(hours: Double) {
        stopWhisper()
        WindowManager.shared.closeAlerts()
        pausedUntil = Date().addingTimeInterval(hours * 3600)
        nextNudge = nil
    }

    func resume() {
        pausedUntil = nil
        sittingSince = Date()
        reschedule()
    }

    func connectCalendars() async {
        let granted = await calendarService.requestAccess()
        if granted && !settings.useCalendars {
            settings.useCalendars = true
        }
        refreshCalendar()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("\(AppInfo.name): launch at login change failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Scheduling

    func reschedule() {
        guard pausedUntil == nil else {
            nextNudge = nil
            return
        }
        nextNudge = Scheduler.nextNudge(sittingSince: sittingSince,
                                        now: Date(),
                                        settings: settings,
                                        busy: settings.quietInMeetings ? busy : [])
    }

    func refreshCalendar() {
        lastCalendarRefresh = Date()
        if settings.useCalendars, calendarService.hasAccess {
            let cal = Calendar.current
            let start = cal.startOfDay(for: Date())
            let end = cal.date(byAdding: .day, value: 4, to: start) ?? start.addingTimeInterval(4 * 86_400)
            busy = calendarService.busyBlocks(from: start, to: end, excluding: settings.excludedCalendarIDs)
        } else {
            busy = []
        }
        reschedule()
    }

    // MARK: Persistence

    private static func loadSettings() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    // MARK: Display helpers

    var accent: Color { settings.accent.color }

    var todayCount: Int { log.count(on: now) }

    var isPaused: Bool { pausedUntil != nil }

    var isWorkingNow: Bool { Scheduler.isWorking(now, settings: settings) }

    /// Remaining meetings today, for the menu.
    var upcomingToday: [BusyBlock] {
        let cal = Calendar.current
        return busy.filter { $0.end > now && cal.isDate($0.start, inSameDayAs: now) }
    }

    /// Short text next to the menu bar icon, e.g. "12m".
    var countdownText: String {
        if pausedUntil != nil { return "paused" }
        guard let next = nextNudge,
              Calendar.current.isDate(next, inSameDayAs: now),
              isWorkingNow else { return "" }
        let mins = Int(ceil(next.timeIntervalSince(now) / 60))
        if mins <= 0 { return "now" }
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }

    var sittingText: String {
        "Sitting since " + sittingSince.formatted(date: .omitted, time: .shortened)
    }

    struct Headline {
        let label: String
        let value: String
        let detail: String
    }

    var headline: Headline {
        if let until = pausedUntil {
            return Headline(label: "Paused until",
                            value: until.formatted(date: .omitted, time: .shortened),
                            detail: "No nudges till then")
        }
        if whisperActive || nudgeVisible {
            return Headline(label: "Pip says", value: "Stand up!", detail: sittingText)
        }
        guard let next = nextNudge else {
            return Headline(label: "No nudges", value: "—", detail: "Pick working days in Settings")
        }
        if !isWorkingNow || !Calendar.current.isDate(next, inSameDayAs: now) {
            return Headline(label: "Off duty",
                            value: "Relax",
                            detail: "Back " + next.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
        }
        let mins = max(0, Int(ceil(next.timeIntervalSince(now) / 60)))
        let value = mins < 60 ? "\(mins) min" : "\(mins / 60)h \(mins % 60)m"
        return Headline(label: "Next stand in", value: value, detail: sittingText)
    }

    /// The body text of a nudge.
    func nudgeMessage(at date: Date = Date()) -> String {
        let mins = max(1, Int(date.timeIntervalSince(sittingSince) / 60))
        if let meeting = Scheduler.meetingSoon(in: busy, now: date) {
            let until = max(1, Int(ceil(meeting.start.timeIntervalSince(date) / 60)))
            return "\(mins) minutes in the chair. “\(meeting.title)” starts in \(until) min — perfect window."
        }
        return "\(mins) minutes in the chair. Time to stretch those legs."
    }

    var lastSevenDays: [DayStat] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        return (0..<7).reversed().compactMap { offset -> DayStat? in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayStat(id: StandLog.key(for: day),
                           label: day.formatted(.dateTime.weekday(.abbreviated)),
                           count: log.count(on: day),
                           isToday: offset == 0)
        }
    }
}
