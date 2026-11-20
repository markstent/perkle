import SwiftUI

/// First-run window: say hello, connect calendars, confirm the schedule.
@MainActor
struct WelcomeView: View {
    static let windowSize = NSSize(width: 540, height: 600)

    @EnvironmentObject var state: AppState

    private var accent: Color { state.accent }

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(Theme.cream)
                Circle().strokeBorder(Theme.ink, lineWidth: Theme.outline)
                PipView(pose: .cheer, color: accent, bob: true)
                    .frame(width: 92, height: 115)
                    .offset(y: 4)
            }
            .frame(width: 140, height: 140)
            .padding(.top, 36)

            VStack(spacing: 8) {
                Text("Hi, I’m Pip.")
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.ink)
                Text("I’ll nudge you to stand up during your working day, and I’ll keep out of your meetings. You’ll find me in the menu bar, top right.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }

            VStack(spacing: 12) {
                stepRow(number: 1,
                        title: "Connect your calendars",
                        detail: state.calendarService.hasAccess
                            ? "Connected! I can see Google, Outlook and iCloud calendars on this Mac."
                            : "So I never pop up mid-meeting. Nothing leaves your Mac.") {
                    if state.calendarService.hasAccess {
                        Label("Done", systemImage: "checkmark")
                            .font(Theme.body(13, .semibold))
                            .foregroundStyle(Theme.good)
                    } else if state.calendarService.needsPrompt {
                        Button("Connect") { Task { await state.connectCalendars() } }
                            .buttonStyle(StickerButtonStyle(kind: .primary, accent: accent, height: 34))
                    } else {
                        Button("Settings") { WindowManager.shared.showSettings(section: .calendars) }
                            .buttonStyle(StickerButtonStyle(kind: .secondary, accent: accent, height: 34))
                    }
                }

                stepRow(number: 2,
                        title: "Check your schedule",
                        detail: state.settings.scheduleSummary) {
                    Button("Change") { WindowManager.shared.showSettings(section: .schedule) }
                        .buttonStyle(StickerButtonStyle(kind: .secondary, accent: accent, height: 34))
                }
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 0)

            Button("Let’s go") {
                state.hasOnboarded = true
                WindowManager.shared.closeWelcome()
            }
            .buttonStyle(StickerButtonStyle(kind: .primary, accent: accent, fullWidth: true, height: 48))
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(state.canvas)
        .environment(\.colorScheme, .light)
    }

    private func stepRow<Trailing: View>(number: Int,
                                         title: String,
                                         detail: String,
                                         @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(Theme.display(18))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(accent))
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.body(14, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(14)
        .stickerCard(radius: 16, shadow: 3, lineWidth: 2)
    }
}
