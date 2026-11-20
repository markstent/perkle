# Perkle

A menu bar app for macOS. Pip, a small cartoon mascot, reminds you to stand up on a schedule you set. It reads your calendars so it never interrupts a meeting.

## Run it

1. You need **macOS 14 (Sonoma) or later** and **Xcode 15 or later**.
2. Unzip, then double-click `Perkle.xcodeproj`.
3. Press **⌘R**. Perkle appears in the menu bar (top right). It has no Dock icon.
4. On first launch a welcome window opens. Click **Connect** and allow calendar access.

If Xcode shows a signing error, click the **Perkle** target, open **Signing & Capabilities** and pick your Apple ID under **Team**. The project is set to "Sign to Run Locally", which normally needs no team.

## Google and work calendars

Perkle reads every calendar the Mac knows about. To add more:

**System Settings › Internet Accounts**
- **Google**: add your Google account and turn on Calendars.
- **Outlook / Microsoft 365 (work)**: add a **Microsoft Exchange** account and turn on Calendars.

These accounts then show up under **Perkle Settings › Calendars**, where you can switch individual calendars off.
If your company blocks Exchange sign-in on personal Macs, ask IT, or subscribe to your work calendar in Calendar.app instead.

Nudges skip all-day events, events marked "free", cancelled events and invitations you've declined.

## How it decides when to nudge

- You get a nudge every *N* minutes of sitting (45 by default), only within your working hours and days.
- **If a nudge would land in a meeting:** when you've been sitting a while, it comes about 2 minutes before the meeting starts. Otherwise it comes about 1 minute after the meeting ends. Back-to-back meetings are handled.
- **Away from the Mac:** locking the screen, sleeping or going idle for 5+ minutes counts as a stand and restarts the clock.
- **Loudness levels:**
  - **Whisper**: the menu bar icon wiggles.
  - **Nudge**: a card in the corner that never takes the keyboard from the app you're typing in.
  - **Insist**: the screen dims for a short break.
- If you ignore a nudge, it goes away on its own (after 60 seconds by default) and asks again after the snooze time.

## Files

| File | What it does |
|---|---|
| `MainApp.swift` | App entry point and menu bar item |
| `AppState.swift` | Timer, idle/sleep detection, actions, everything the screens show |
| `Scheduler.swift` | Pure logic: when the next nudge should be |
| `CalendarService.swift` | Reads events through EventKit |
| `WindowManager.swift` | Floating nudge panel, full-screen break, Settings and welcome windows |
| `NudgeView.swift` | The corner nudge and the full-screen break |
| `MenuPopoverView.swift` | The menu bar dropdown |
| `SettingsView.swift` | Schedule, Calendars, Look & sound, Stats |
| `WelcomeView.swift` | First-run window |
| `PipView.swift` | Pip, drawn in code (4 poses), plus the menu bar icon |
| `Theme.swift` | The "Sticker" look: colours, outlines, hard shadows, buttons, toggles |
| `Models.swift` | Settings, stand log, wording and the app name |

## Renaming

The name appears in three places:
1. `AppInfo.name` in `Models.swift`.
2. The bundle ID `com.example.perkle`: change it in the target's **Signing & Capabilities**.
3. The display name: target › **Build Settings** › "Bundle Display Name".

## Notes

- Headlines use SF Pro Rounded, which ships with macOS, instead of Fredoka. To use Fredoka, add its .ttf files to the target and swap `Theme.display`.
- With "Sign to Run Locally", macOS may ask for calendar permission again after some rebuilds. Signing with your own team avoids this.
- Settings and stats are stored in UserDefaults on this Mac only.
