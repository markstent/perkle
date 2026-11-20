import SwiftUI

// MARK: - Loudness

/// How hard Pip tries to get your attention.
enum Loudness: String, Codable, CaseIterable, Identifiable {
    case whisper, nudge, insist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whisper: return "Whisper"
        case .nudge: return "Nudge"
        case .insist: return "Insist"
        }
    }

    var detail: String {
        switch self {
        case .whisper: return "Menu bar icon wiggles"
        case .nudge: return "Pip pops up in the corner"
        case .insist: return "Screen dims for a short break"
        }
    }
}

// MARK: - Accent colour

enum AccentChoice: String, Codable, CaseIterable, Identifiable {
    case tangerine, mint, sky, sun

    var id: String { rawValue }

    var name: String {
        switch self {
        case .tangerine: return "Tangerine"
        case .mint: return "Mint"
        case .sky: return "Sky"
        case .sun: return "Sun"
        }
    }

    var color: Color {
        switch self {
        case .tangerine: return Color(hex: 0xFF6A3D)
        case .mint: return Color(hex: 0x3DDC97)
        case .sky: return Color(hex: 0x5B8CFF)
        case .sun: return Color(hex: 0xFFC93C)
        }
    }
}

// MARK: - Settings

/// Everything the user can change. Stored as JSON in UserDefaults.
struct AppSettings: Codable, Equatable {
    /// Minutes of sitting between nudges.
    var intervalMinutes = 45
    /// Working window, in minutes after midnight.
    var startMinutes = 9 * 60
    var endMinutes = 17 * 60 + 30
    /// `Calendar` weekday numbers (1 = Sunday … 7 = Saturday).
    var activeWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    var dailyGoal = 8
    var loudness: Loudness = .nudge
    /// Never nudge while a calendar event is in progress.
    var quietInMeetings = true
    /// If a nudge would land in a meeting, try just before it starts.
    var standBeforeMeetings = true
    /// Time away from the keyboard (minutes) that counts as a break. 0 = off.
    var idleResetMinutes = 5
    var useCalendars = true
    var excludedCalendarIDs: Set<String> = []
    var accent: AccentChoice = .tangerine
    var showCountdown = true
    var playSound = true
    var showTips = true
    var snoozeMinutes = 10
    /// How long a nudge stays up before it goes away on its own.
    var autoDismissSeconds = 60

    init() {}

    // Tolerant decoding: any key missing from an older save falls back to its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        intervalMinutes = try c.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? d.intervalMinutes
        startMinutes = try c.decodeIfPresent(Int.self, forKey: .startMinutes) ?? d.startMinutes
        endMinutes = try c.decodeIfPresent(Int.self, forKey: .endMinutes) ?? d.endMinutes
        activeWeekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .activeWeekdays) ?? d.activeWeekdays
        dailyGoal = try c.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? d.dailyGoal
        loudness = try c.decodeIfPresent(Loudness.self, forKey: .loudness) ?? d.loudness
        quietInMeetings = try c.decodeIfPresent(Bool.self, forKey: .quietInMeetings) ?? d.quietInMeetings
        standBeforeMeetings = try c.decodeIfPresent(Bool.self, forKey: .standBeforeMeetings) ?? d.standBeforeMeetings
        idleResetMinutes = try c.decodeIfPresent(Int.self, forKey: .idleResetMinutes) ?? d.idleResetMinutes
        useCalendars = try c.decodeIfPresent(Bool.self, forKey: .useCalendars) ?? d.useCalendars
        excludedCalendarIDs = try c.decodeIfPresent(Set<String>.self, forKey: .excludedCalendarIDs) ?? d.excludedCalendarIDs
        accent = try c.decodeIfPresent(AccentChoice.self, forKey: .accent) ?? d.accent
        showCountdown = try c.decodeIfPresent(Bool.self, forKey: .showCountdown) ?? d.showCountdown
        playSound = try c.decodeIfPresent(Bool.self, forKey: .playSound) ?? d.playSound
        showTips = try c.decodeIfPresent(Bool.self, forKey: .showTips) ?? d.showTips
        snoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? d.snoozeMinutes
        autoDismissSeconds = try c.decodeIfPresent(Int.self, forKey: .autoDismissSeconds) ?? d.autoDismissSeconds
    }

    var scheduleSummary: String {
        let cal = Calendar.current
        let order = [2, 3, 4, 5, 6, 7, 1]
        let days = order.filter { activeWeekdays.contains($0) }
        let dayText: String
        if days == [2, 3, 4, 5, 6] {
            dayText = "Mon–Fri"
        } else if days.count == 7 {
            dayText = "every day"
        } else if days.isEmpty {
            dayText = "no days yet"
        } else {
            dayText = days.map { cal.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
        }
        return "Every \(intervalMinutes) min · \(Self.clock(startMinutes))–\(Self.clock(endMinutes)) · \(dayText)"
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

// MARK: - Stand log

/// Count of stands per calendar day, keyed "yyyy-MM-dd".
struct StandLog: Codable, Equatable {
    var counts: [String: Int] = [:]

    static let defaultsKey = "standLog.v1"

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(for date: Date) -> String {
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    func count(on date: Date) -> Int {
        counts[Self.key(for: date)] ?? 0
    }

    mutating func add(on date: Date) {
        counts[Self.key(for: date), default: 0] += 1
        prune(before: date)
    }

    /// Keep roughly the last 90 days.
    private mutating func prune(before date: Date) {
        guard counts.count > 120,
              let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: date) else { return }
        let cutoffKey = Self.key(for: cutoff)
        counts = counts.filter { $0.key >= cutoffKey }
    }

    static func load() -> StandLog {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let log = try? JSONDecoder().decode(StandLog.self, from: data) else { return StandLog() }
        return log
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

// MARK: - Settings sections

enum SettingsSection: String, CaseIterable, Identifiable {
    case schedule, calendars, look, stats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: return "Schedule"
        case .calendars: return "Calendars"
        case .look: return "Look & sound"
        case .stats: return "Stats"
        }
    }

    var symbol: String {
        switch self {
        case .schedule: return "clock"
        case .calendars: return "calendar"
        case .look: return "paintpalette"
        case .stats: return "chart.bar"
        }
    }
}

// MARK: - Copy

enum PipCopy {
    static let headlines = [
        "Stretch o’clock!",
        "Up you get!",
        "Stand-up time!",
        "Legs, assemble!",
        "Time to stand!"
    ]

    static let tips = [
        "Doorway chest stretch, 20 seconds.",
        "Roll your shoulders back ten times.",
        "Reach up tall, then lean left and right.",
        "Squeeze your shoulder blades: 5 × 5 seconds.",
        "Walk over and grab a glass of water.",
        "Ten slow chin tucks.",
        "Fifteen calf raises while you’re up."
    ]

    static func headline(for date: Date) -> String {
        headlines[slot(date, count: headlines.count)]
    }

    static func tip(for date: Date) -> String {
        tips[slot(date, count: tips.count)]
    }

    /// Changes every half hour so consecutive nudges read differently.
    private static func slot(_ date: Date, count: Int) -> Int {
        let n = Int(date.timeIntervalSince1970 / 1800)
        return ((n % count) + count) % count
    }
}

// MARK: - App name

/// The one place the app's display name lives in code.
/// (Also change PRODUCT_NAME / the bundle display name in the project — see README.)
enum AppInfo {
    static let name = "Perkle"
}
