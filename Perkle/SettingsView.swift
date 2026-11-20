import SwiftUI
import AppKit
import EventKit

@MainActor
struct SettingsView: View {
    static let windowSize = NSSize(width: 820, height: 660)

    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.line).frame(width: 2)
            ScrollView {
                Group {
                    switch state.settingsSection {
                    case .schedule: SchedulePane()
                    case .calendars: CalendarsPane()
                    case .look: LookPane()
                    case .stats: StatsPane()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 40)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(state.canvas)
        .environment(\.colorScheme, .light)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                PipView(pose: .idle, color: state.accent)
                    .frame(width: 28, height: 35)
                Text(AppInfo.name)
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)

            ForEach(SettingsSection.allCases) { section in
                let selected = state.settingsSection == section
                Button {
                    state.settingsSection = section
                } label: {
                    Label(section.title, systemImage: section.symbol)
                        .font(Theme.body(14, selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Theme.ink : Theme.ink2)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .background {
                            if selected {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(state.accent)
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Theme.ink, lineWidth: 2)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 44)
        .padding(.bottom, 20)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(state.canvasDeep)
    }
}

// MARK: - Shared pieces

private struct PaneTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Theme.display(30))
            .foregroundStyle(Theme.ink)
    }
}

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Theme.body(12))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Schedule

@MainActor
private struct SchedulePane: View {
    @EnvironmentObject var state: AppState
    private let presets = [30, 45, 60, 90]
    private let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    private var accent: Color { state.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PaneTitle("Schedule")

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Nudge me every")
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { minutes in
                        Button("\(minutes) min") { state.settings.intervalMinutes = minutes }
                            .buttonStyle(ChipButtonStyle(selected: state.settings.intervalMinutes == minutes,
                                                         accent: accent))
                    }
                    Stepper(value: $state.settings.intervalMinutes, in: 10...180, step: 5) {
                        Text("\(state.settings.intervalMinutes) min")
                            .font(Theme.body(13, .medium))
                            .foregroundStyle(Theme.ink2)
                    }
                    .padding(.leading, 6)
                }
            }

            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Between")
                    HStack(spacing: 8) {
                        DatePicker("Start", selection: timeBinding(\.startMinutes), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Text("and").font(Theme.body(13)).foregroundStyle(Theme.muted)
                        DatePicker("End", selection: timeBinding(\.endMinutes), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    if state.settings.endMinutes <= state.settings.startMinutes {
                        Note("The end time needs to be after the start time.")
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("On")
                    HStack(spacing: 6) {
                        ForEach(weekdayOrder, id: \.self) { day in
                            Button(Calendar.current.veryShortWeekdaySymbols[day - 1]) { toggle(day) }
                                .buttonStyle(ChipButtonStyle(selected: state.settings.activeWeekdays.contains(day),
                                                             accent: accent, circle: true))
                                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Daily goal")
                Stepper(value: $state.settings.dailyGoal, in: 1...16) {
                    Text("\(state.settings.dailyGoal) stands a day")
                        .font(Theme.body(13, .medium))
                        .foregroundStyle(Theme.ink2)
                }
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("How loud?")
                HStack(spacing: 12) {
                    ForEach(Loudness.allCases) { level in
                        LoudnessCard(level: level,
                                     selected: state.settings.loudness == level,
                                     accent: accent) {
                            state.settings.loudness = level
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Smart rules")
                Toggle("Stay quiet while a meeting is on", isOn: $state.settings.quietInMeetings)
                    .toggleStyle(StickerToggleStyle(accent: accent))
                Toggle("If a nudge would land in a meeting, nudge just before it starts",
                       isOn: $state.settings.standBeforeMeetings)
                    .toggleStyle(StickerToggleStyle(accent: accent))
                    .disabled(!state.settings.quietInMeetings)
                    .opacity(state.settings.quietInMeetings ? 1 : 0.5)
                Toggle("Count time away from the Mac as a break", isOn: awayBinding)
                    .toggleStyle(StickerToggleStyle(accent: accent))
                if state.settings.idleResetMinutes > 0 {
                    Stepper(value: $state.settings.idleResetMinutes, in: 2...30) {
                        Text("Away for \(state.settings.idleResetMinutes)+ min counts as a stand")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.muted)
                    }
                    .fixedSize()
                }
                Toggle("Open at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                .toggleStyle(StickerToggleStyle(accent: accent))
            }
            .frame(maxWidth: 520)

            Note(state.settings.scheduleSummary)
        }
    }

    private var awayBinding: Binding<Bool> {
        Binding(
            get: { state.settings.idleResetMinutes > 0 },
            set: { state.settings.idleResetMinutes = $0 ? 5 : 0 }
        )
    }

    private func toggle(_ day: Int) {
        if state.settings.activeWeekdays.contains(day) {
            state.settings.activeWeekdays.remove(day)
        } else {
            state.settings.activeWeekdays.insert(day)
        }
    }

    private func timeBinding(_ keyPath: WritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = state.settings[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60,
                                             second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                state.settings[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

private struct LoudnessCard: View {
    let level: Loudness
    let selected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(level.title)
                    .font(Theme.display(17, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(level.detail)
                    .font(Theme.body(12))
                    .foregroundStyle(selected ? Theme.ink2 : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 160, height: 76, alignment: .topLeading)
            .background {
                ZStack {
                    if selected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.ink).offset(x: 3, y: 3)
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cream)
                        RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.ink, lineWidth: Theme.outline)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.paper)
                        RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 2)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Calendars

@MainActor
private struct CalendarsPane: View {
    @EnvironmentObject var state: AppState

    private var service: CalendarService { state.calendarService }
    private var accent: Color { state.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PaneTitle("Calendars")
            Note("\(AppInfo.name) reads the calendars on this Mac (Google, Microsoft 365 / Outlook, iCloud), so it never nudges you mid-meeting. Nothing leaves your Mac.")
                .frame(maxWidth: 520, alignment: .leading)

            statusCard

            if service.hasAccess {
                Toggle("Use my calendars to time nudges", isOn: $state.settings.useCalendars)
                    .toggleStyle(StickerToggleStyle(accent: accent))
                    .frame(maxWidth: 520)

                if state.settings.useCalendars {
                    calendarList
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Missing your Google or work calendar?")
                Note("Add the account in System Settings › Internet Accounts (choose Google, or Microsoft Exchange for Outlook / Microsoft 365) and turn on Calendars. It will appear here automatically.")
                    .frame(maxWidth: 520, alignment: .leading)
                Button("Open Internet Accounts") {
                    openURL("x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")
                }
                .buttonStyle(StickerButtonStyle(kind: .secondary, accent: accent, height: 36))
            }
        }
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(service.hasAccess ? AccentChoice.mint.color : Theme.paper)
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text("Calendar access")
                    .font(Theme.body(14, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(service.statusText)
                    .font(Theme.body(12))
                    .foregroundStyle(service.hasAccess ? Theme.good : Theme.muted)
            }
            Spacer()
            if service.needsPrompt {
                Button("Connect") { Task { await state.connectCalendars() } }
                    .buttonStyle(StickerButtonStyle(kind: .primary, accent: accent, height: 36))
            } else if service.isBlocked {
                Button("Open Privacy Settings") {
                    openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
                }
                .buttonStyle(StickerButtonStyle(kind: .secondary, accent: accent, height: 36))
            }
        }
        .padding(14)
        .frame(maxWidth: 520)
        .stickerCard(radius: 16, shadow: 0, lineWidth: 2)
    }

    private var calendarList: some View {
        let groups = Dictionary(grouping: service.calendars) { $0.source?.title ?? "Other" }
        let sources = groups.keys.sorted()
        return VStack(alignment: .leading, spacing: 16) {
            SectionLabel("Check these calendars")
            if service.calendars.isEmpty {
                Note("No calendars found yet.")
            }
            ForEach(sources, id: \.self) { source in
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(source)
                    ForEach(groups[source] ?? [], id: \.calendarIdentifier) { calendar in
                        Toggle(isOn: includedBinding(calendar.calendarIdentifier)) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(nsColor: calendar.color ?? .gray))
                                    .frame(width: 10, height: 10)
                                Text(calendar.title)
                            }
                        }
                        .toggleStyle(StickerToggleStyle(accent: accent))
                    }
                }
            }
        }
        .frame(maxWidth: 520)
    }

    private func includedBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !state.settings.excludedCalendarIDs.contains(id) },
            set: { included in
                if included {
                    state.settings.excludedCalendarIDs.remove(id)
                } else {
                    state.settings.excludedCalendarIDs.insert(id)
                }
            }
        )
    }

    private func openURL(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Look & sound

@MainActor
private struct LookPane: View {
    @EnvironmentObject var state: AppState
    private var accent: Color { state.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PaneTitle("Look & sound")

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Pip’s colour")
                HStack(spacing: 14) {
                    ForEach(AccentChoice.allCases) { choice in
                        let selected = state.settings.accent == choice
                        Button {
                            state.settings.accent = choice
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    if selected {
                                        Circle().fill(Theme.ink).offset(x: 3, y: 3)
                                    }
                                    Circle().fill(choice.color)
                                    Circle().strokeBorder(Theme.ink, lineWidth: selected ? 3 : 2)
                                }
                                .frame(width: 40, height: 40)
                                Text(choice.name)
                                    .font(Theme.body(12, selected ? .semibold : .regular))
                                    .foregroundStyle(Theme.ink2)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 20) {
                PipView(pose: .stretch, color: accent, bob: true).frame(width: 64, height: 80)
                PipView(pose: .cheer, color: accent).frame(width: 64, height: 80)
                PipView(pose: .idle, color: accent).frame(width: 64, height: 80)
                PipView(pose: .sleepy, color: accent).frame(width: 64, height: 80)
            }
            .padding(16)
            .stickerCard(radius: 18, fill: Theme.cream, shadow: 4)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show the countdown in the menu bar", isOn: $state.settings.showCountdown)
                    .toggleStyle(StickerToggleStyle(accent: accent))
                Toggle("Play a pop sound with each nudge", isOn: $state.settings.playSound)
                    .toggleStyle(StickerToggleStyle(accent: accent))
                Toggle("Suggest a quick stretch", isOn: $state.settings.showTips)
                    .toggleStyle(StickerToggleStyle(accent: accent))
                Stepper(value: $state.settings.snoozeMinutes, in: 5...30, step: 5) {
                    Text("Snooze for \(state.settings.snoozeMinutes) min")
                        .font(Theme.body(13, .medium))
                        .foregroundStyle(Theme.ink)
                }
                .fixedSize()
                Stepper(value: $state.settings.autoDismissSeconds, in: 20...180, step: 10) {
                    Text("Nudges go away on their own after \(state.settings.autoDismissSeconds)s")
                        .font(Theme.body(13, .medium))
                        .foregroundStyle(Theme.ink)
                }
                .fixedSize()
            }
            .frame(maxWidth: 520)

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Try it")
                HStack(spacing: 10) {
                    Button("Preview nudge") { WindowManager.shared.showNudge(preview: true) }
                        .buttonStyle(StickerButtonStyle(kind: .primary, accent: accent, height: 38))
                    Button("Preview screen break") { WindowManager.shared.showInsist(preview: true) }
                        .buttonStyle(StickerButtonStyle(kind: .secondary, accent: accent, height: 38))
                }
            }
        }
    }
}

// MARK: - Stats

@MainActor
private struct StatsPane: View {
    @EnvironmentObject var state: AppState
    private var accent: Color { state.accent }

    var body: some View {
        let days = state.lastSevenDays
        let goal = state.settings.dailyGoal
        let top = max(goal, days.map(\.count).max() ?? 0, 1)
        let total = days.reduce(0) { $0 + $1.count }
        let best = days.map(\.count).max() ?? 0
        let goalDays = days.filter { $0.count >= goal }.count

        return VStack(alignment: .leading, spacing: 24) {
            PaneTitle("Stats")

            HStack(spacing: 12) {
                StatTile(value: "\(state.todayCount)", label: "today", accent: accent, highlight: true)
                StatTile(value: "\(total)", label: "last 7 days", accent: accent)
                StatTile(value: "\(best)", label: "best day", accent: accent)
                StatTile(value: "\(goalDays)/7", label: "days on goal", accent: accent)
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Stands per day")
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(days) { day in
                        VStack(spacing: 6) {
                            Text("\(day.count)")
                                .font(Theme.body(12, .semibold))
                                .foregroundStyle(Theme.ink2)
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(day.count >= goal ? accent : Theme.cream)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Theme.ink, lineWidth: 2)
                                )
                                .frame(width: 44, height: max(8, CGFloat(day.count) / CGFloat(top) * 180))
                            Text(day.label)
                                .font(Theme.body(12, day.isToday ? .bold : .regular))
                                .foregroundStyle(day.isToday ? Theme.ink : Theme.muted)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(day.label): \(day.count) stands")
                    }
                }
                .frame(height: 230, alignment: .bottom)
                .padding(18)
                .stickerCard(radius: 18, shadow: 4)
                Note("Filled bars hit your goal of \(goal) a day.")
            }
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let accent: Color
    var highlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.display(30))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(Theme.body(12, .medium))
                .foregroundStyle(Theme.ink2)
        }
        .padding(14)
        .frame(width: 120, alignment: .leading)
        .stickerCard(radius: 16, fill: highlight ? accent : Theme.paper, shadow: highlight ? 4 : 0, lineWidth: highlight ? 3 : 2)
    }
}
