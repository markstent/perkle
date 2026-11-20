import SwiftUI

/// The card that slides into the top-right corner when it's time to stand.
@MainActor
struct NudgeView: View {
    /// Panel size, including room for the hard shadow.
    static let panelSize = CGSize(width: 404, height: 262)

    @EnvironmentObject var state: AppState
    var preview = false

    @State private var cheering = false
    @State private var shownAt = Date()

    private var accent: Color { state.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if cheering {
                cheerContent
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                askContent
                    .transition(.opacity)
            }
        }
        .padding(18)
        .frame(width: 380, height: 240, alignment: .topLeading)
        .stickerCard(radius: 24)
        .padding(EdgeInsets(top: 6, leading: 6, bottom: 16, trailing: 18))
        .frame(width: Self.panelSize.width, height: Self.panelSize.height, alignment: .topLeading)
        .environment(\.colorScheme, .light)
    }

    // MARK: Ask

    private var askContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                pipBox(pose: .stretch, bob: true)
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("Pip says")
                    Text(PipCopy.headline(for: shownAt))
                        .font(Theme.display(26))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(preview ? "This is a preview of your nudge. Looking good!" : state.nudgeMessage(at: shownAt))
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button("I’m up") { standUp() }
                    .buttonStyle(StickerButtonStyle(kind: .primary, accent: accent, fullWidth: true, height: 44))
                    .keyboardShortcut(.defaultAction)
                Button("\(state.settings.snoozeMinutes) min") {
                    if !preview { state.snooze() }
                    WindowManager.shared.closeNudge()
                }
                .buttonStyle(StickerButtonStyle(kind: .secondary, accent: accent, height: 44))
                Button("Skip") {
                    if !preview { state.skip() }
                    WindowManager.shared.closeNudge()
                }
                .buttonStyle(StickerButtonStyle(kind: .ghost, accent: accent, height: 44))
            }

            footerLine
        }
    }

    // MARK: Cheer

    private var cheerContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                pipBox(pose: .cheer, bob: false)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nice one.")
                        .font(Theme.display(28))
                        .foregroundStyle(Theme.ink)
                    Text(state.standsProgress)
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.ink2)
                    HStack(spacing: 5) {
                        ForEach(0..<min(state.settings.dailyGoal, 12), id: \.self) { index in
                            StandToken(filled: index < state.todayCount, accent: accent)
                        }
                    }
                }
            }
            footerLine
        }
    }

    // MARK: Pieces

    private func pipBox(pose: PipView.Pose, bob: Bool) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cream)
            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.ink, lineWidth: Theme.outline)
            PipView(pose: pose, color: accent, bob: bob)
                .frame(width: 70, height: 88)
                .padding(.bottom, 6)
        }
        .frame(width: 92, height: 112)
    }

    @ViewBuilder
    private var footerLine: some View {
        if state.settings.showTips {
            Label("Try: \(PipCopy.tip(for: shownAt))", systemImage: "figure.cooldown")
                .font(Theme.body(12))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        } else if state.calendarService.hasAccess && state.settings.useCalendars {
            Label("Timed around your calendar", systemImage: "calendar")
                .font(Theme.body(12))
                .foregroundStyle(Theme.muted)
        }
    }

    private func standUp() {
        WindowManager.shared.cancelAutoDismiss()
        if !preview { state.stoodUp() }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            cheering = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            WindowManager.shared.closeNudge()
        }
    }
}

/// "Insist" mode: the screen dims for a short break.
@MainActor
struct InsistView: View {
    @EnvironmentObject var state: AppState
    var showCard: Bool
    var preview = false

    @State private var shownAt = Date()
    @State private var cheering = false

    private var accent: Color { state.accent }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            if showCard {
                card
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .light)
    }

    private var card: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.cream)
                Circle().strokeBorder(Theme.ink, lineWidth: Theme.outline)
                PipView(pose: cheering ? .cheer : .stretch, color: accent, bob: !cheering)
                    .frame(width: 110, height: 138)
                    .offset(y: 6)
            }
            .frame(width: 170, height: 170)

            Text(cheering ? "Nice one." : "Screen break")
                .font(Theme.display(36))
                .foregroundStyle(Theme.ink)

            Text(cheering
                 ? state.standsProgress
                 : "Stand up, stretch, look at something far away.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)

            if !cheering {
                if state.settings.showTips {
                    Text("Try: \(PipCopy.tip(for: shownAt))")
                        .font(Theme.body(13, .medium))
                        .foregroundStyle(Theme.muted)
                }

                TimelineView(.periodic(from: shownAt, by: 1)) { context in
                    Text(remaining(at: context.date))
                        .font(Theme.display(22, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }

                HStack(spacing: 10) {
                    Button("I’m up") { standUp() }
                        .buttonStyle(StickerButtonStyle(kind: .primary, accent: accent, fullWidth: true, height: 46))
                        .keyboardShortcut(.defaultAction)
                    Button("Not now") {
                        if !preview { state.snooze() }
                        WindowManager.shared.closeInsist()
                    }
                    .buttonStyle(StickerButtonStyle(kind: .secondary, accent: accent, height: 46))
                }
            }
        }
        .padding(32)
        .frame(width: 460)
        .stickerCard(radius: 30, shadow: 8)
    }

    private func remaining(at date: Date) -> String {
        let total = Double(max(state.settings.autoDismissSeconds, 10))
        let left = max(0, Int(ceil(total - date.timeIntervalSince(shownAt))))
        return String(format: "%d:%02d", left / 60, left % 60)
    }

    private func standUp() {
        WindowManager.shared.cancelAutoDismiss()
        if !preview { state.stoodUp() }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            cheering = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            WindowManager.shared.closeInsist()
        }
    }
}
