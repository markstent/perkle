# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Perkle is a macOS menu bar app (SwiftUI + AppKit, macOS 14+, Swift 5) where a mascot, Pip, nudges you to stand up on a schedule and avoids calendar meetings.
It is `LSUIElement` (no Dock icon), sandboxed, with only the calendars entitlement.
See `README.md` for user-facing behaviour and a per-file overview.

## Commands

There is no test target, linter or package manager; it is a single Xcode target and scheme, both named `Perkle`.

```sh
# Build (unsigned, for a compile check)
xcodebuild -project Perkle.xcodeproj -scheme Perkle -configuration Debug build CODE_SIGNING_ALLOWED=NO

# Build and run from Xcode: open Perkle.xcodeproj, then Cmd-R
```

Running the app needs calendar permission and a real menu bar, so verify UI behaviour by launching it, not just by compiling.
The project uses "Sign to Run Locally"; macOS may re-prompt for calendar access after rebuilds.

## Architecture

- **`AppState` (singleton, `@MainActor`) is the hub.** It owns settings, the stand log, calendar busy blocks, idle/sleep/lock state and `nextNudge`. Views observe it; `WindowManager.shared` calls back into it.
- **`Scheduler` is pure logic** (no state, no AppKit). `nextNudge(sittingSince:now:settings:busy:calendar:)` decides the next nudge time: clamps to working hours, moves nudges out of meetings (2 min before if you've sat at least 60% of the interval, otherwise 1 min after). It takes `calendar` and `now` as parameters so it can be tested deterministically. Put new timing rules here, not in `AppState`.
- **The clock is a 15 s `Timer` tick** in `AppState.tick()`: un-pause, idle check, calendar refresh every 5 min, then fire if `now >= nextNudge`, re-checking meeting/working-hours at the last moment. Anything that changes timing inputs should call `reschedule()` (or `refreshCalendar()` if the busy blocks change); the `settings` `didSet` already does this.
- **"Away" resets the sitting clock.** Sleep, screen lock (distributed `com.apple.screenIsLocked`) and HID idle beyond `idleResetMinutes` set `awaySince`; `cameBack()` treats a long enough absence within working hours as a stand.
- **Calendar data** comes from `CalendarService` (EventKit) as `[BusyBlock]`, fetched for today plus 4 days. It filters all-day, free, cancelled and declined events and excluded calendar IDs.
- **Loudness levels map to presentation:** whisper = menu bar icon wiggle (state in `AppState`), nudge = non-activating floating `NSPanel` (`FloatingPanel` in `WindowManager`, must never steal keyboard focus), insist = full-screen dimmed break window. Auto-dismiss is handled in `WindowManager`.
- **Persistence** is UserDefaults only: `settings.v1` (JSON-encoded `AppSettings`), the stand log, and `hasOnboarded.v1`. `AppSettings.init(from:)` decodes each key with `decodeIfPresent` and a default, so when adding a setting, add it there too or old saves will reset.
- **Styling** goes through `Theme` (colours, outlines, hard shadows, buttons, toggles); Pip and the menu bar icon are drawn in code in `PipView`. Pip's wording lives in `PipCopy` in `Models.swift`.
- **App name** is `AppInfo.name` in `Models.swift`; renaming also needs the bundle ID (`com.example.perkle`) and display name changed in the target settings.
