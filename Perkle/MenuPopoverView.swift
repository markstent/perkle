import SwiftUI
import AppKit

/// The icon (and countdown) in the menu bar.
@MainActor
struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let armsUp = state.whisperActive && state.wiggle
        HStack(spacing: 3) {
            Image(nsImage: PipIcon.menuBar(armsUp: armsUp))
            if state.whisperActive {
                Text("Stand!")
            } else if state.settings.showCountdown, !state.countdownText.isEmpty {
                Text(state.countdownText)
                    .monospacedDigit()
            }
        }
        .accessibilityLabel("\(AppInfo.name): \(state.headline.label) \(state.headline.value)")
    }
}

/// The window that drops down when you click the menu bar icon.
@MainActor
struct MenuPopoverView: View {
    @EnvironmentObject var state: AppState

    private var accent: Color { state.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if state.whisperActive {
                whisperBanner
            }
            header
            today
            comingUp
            Toggle("Stay quiet in meetings", isOn: $state.settings.quietInMeetings)
                .toggleStyle(StickerToggleStyle(accent: accent))
            actions
            footer
        }
        .padding(18)
        .frame(width: 330)
        .background(state.canvas)
        .environment(\.colorScheme, .light)
    }

    // MARK: Sections

    private var whisperBanner: some View {
        HStack(spacing: 12) {
            PipView(pose: .stretch, color: accent, bob: true)
                .frame(width: 44, height: 55)
            VStack(alignment: .leading, spacing: 8) {
                Text(PipCopy.headline(for: state.now))
                    .font(Theme.display(18))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    Button("I’m up") { state.stoodUp() }
                        .buttonStyle(StickerButtonStyle(kind: .primary, accent: accent, height: 34))
                    Button("\(state.settings.snoozeMinutes) min") { state.snooze() }
                        .buttonStyle(StickerButtonStyle(kind: .secondary, accent: accent, height: 34))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stickerCard(radius: 18, fill: Theme.cream, shadow: 3)
    }

    private var header: some View {
        let headline = state.headline
        let pose: PipView.Pose = (state.isPaused || !state.isWorkingNow) ? .sleepy : .idle
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.cream)
                Circle().strokeBorder(Theme.ink, lineWidth: Theme.outline)
                PipView(pose: pose, color: accent)
                    .frame(width: 44, height: 55)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline.label)
                    .font(Theme.body(12, .semibold))
                    .foregroundStyle(Theme.muted)
                Text(headline.value)
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(headline.detail)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var today: some View {
        let goal = state.settings.dailyGoal
        let done = state.todayCount
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today").font(Theme.body(13, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text(state.standsProgress)
                    .font(Theme.body(13, .medium))
                    .foregroundStyle(Theme.muted)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 24, maximum: 30), spacing: 6)],
                      alignment: .leading, spacing: 6) {
                ForEach(0..<goal, id: \.self) { index in
                    StandToken(filled: index < done, accent: accent, width: 24, height: 30)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.standsProgress)
        }
    }

    @ViewBuilder
    private var comingUp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Coming up")
            if !state.calendarService.hasAccess || !state.settings.useCalendars {
                Text("Connect your calendars and I’ll never nudge you mid-meeting.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button(state.calendarService.isBlocked ? "Open calendar settings" : "Connect calendars") {
                    if state.calendarService.needsPrompt {
                        Task { await state.connectCalendars() }
                    } else {
                        WindowManager.shared.showSettings(section: .calendars)
                    }
                }
                .buttonStyle(StickerButtonStyle(kind: .secondary, accent: accent, height: 32))
            } else if state.upcomingToday.isEmpty {
                Text("No more meetings today.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.ink2)
            } else {
                ForEach(Array(state.upcomingToday.prefix(3).enumerated()), id: \.offset) { _, block in
                    HStack(alignment: .top, spacing: 10) {
                        Text(block.start.formatted(date: .omitted, time: .shortened))
                            .font(Theme.body(13, .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 58, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.title)
                                .font(Theme.body(13, .semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text(meetingNote(for: block))
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.paper))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Stand now") {
                WindowManager.shared.closeAlerts()
                state.stoodUp()
            }
                .buttonStyle(StickerButtonStyle(kind: .secondary, accent: accent, fullWidth: true))
            if state.isPaused {
                Button("Resume") { state.resume() }
                    .buttonStyle(StickerButtonStyle(kind: .secondary, accent: accent, fullWidth: true))
            } else {
                Button("Pause 1 hr") { state.pause(hours: 1) }
                    .buttonStyle(StickerButtonStyle(kind: .secondary, accent: accent, fullWidth: true))
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { WindowManager.shared.showSettings() }
                .buttonStyle(.plain)
            Spacer()
            Button("Quit \(AppInfo.name)") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
        }
        .font(Theme.body(13, .medium))
        .foregroundStyle(Theme.ink2)
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 2)
        }
    }

    private func meetingNote(for block: BusyBlock) -> String {
        let source = block.calendarName.isEmpty ? "" : block.calendarName + " · "
        if block.start <= state.now { return source + "on now, I’m staying quiet" }
        return source + "I’ll wait till it ends"
    }
}
