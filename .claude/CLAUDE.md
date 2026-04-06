# Launchette

macOS app launcher and calculator replacing Spotlight. Global hotkey (configurable, default Cmd+Space), menu bar only.

## Posture: Active Development

## Stack
- Pure AppKit (no SwiftUI)
- Swift Package Manager
- Carbon API for global hotkey
- JavaScriptCore for math evaluation

## Build
- `make build` -- compile and create .app bundle
- `make run` -- build and launch
- `make install` -- copy to /Applications

## Requirements
- Disable Spotlight's Cmd+Space first (System Settings > Keyboard > Keyboard Shortcuts > Spotlight)
- macOS 13+
