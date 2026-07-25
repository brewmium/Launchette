# Launchette

macOS app launcher, timer, and calculator replacing Spotlight. Global hotkey
(configurable, default Cmd+Space), menu bar only. One input field dispatches by
shape: `=`-prefixed input is math, durations (`20`, `1h30m`) and clock times
(`3:30pm`) are timers (timer row ranks above app results), everything else is
app search. Timer engine copied from sibling app Timerette (InputParser,
TimerStore, CountdownTimer, TimeFormat, AudioState, AlertChip) -- deliberately
copied, not shared.

## Posture: Active Development

## Stack
- Pure AppKit (no SwiftUI)
- Swift Package Manager
- Carbon API for global hotkey
- JavaScriptCore for math evaluation
- UserNotifications + NSSound + CoreAudio for the timer fire alert path

## Build
- `make build` -- compile and create .app bundle
- `make run` -- build and launch
- `make test` -- unit tests (InputParser, TimeFormat, TimerStore, persistence, MathEvaluator)
- `make install` -- copy to /Applications

## Requirements
- Disable Spotlight's Cmd+Space first (System Settings > Keyboard > Keyboard Shortcuts > Spotlight)
- macOS 13+
