# Launchette

You just want a Cmd+Space app launcher like you used to have before macOS 26.4, and you want one that sucks less. Launchette is the answer.

No AI. No suggestions. No "enhanced search." No Siri. Type a name, launch the app. Do math, get the answer. That's it.

## Features

- **App launcher** -- type to search, Enter to launch or bring to front. Running apps ranked higher. Frequently launched apps bubble to the top.
- **Calculator** -- auto-detects math expressions inline. `2+2`, `300x5`, `sqrt(144)`, `2^10`. Enter copies the result.
- **Configurable hotkey** -- defaults to Cmd+Space. Change it from the menu bar.
- **Custom apps** -- manually add apps that live in weird places.
- **Hide apps** -- right-click any result to hide it permanently. Restore from Manage Apps.
- **App details** -- version and path shown for each result, so you can tell your three Android Studios apart.
- **Three sizes** -- Small, Medium, or Large. Icons, text, and row height all scale.
- **Multi-monitor** -- choose whether the panel opens on the mouse cursor's screen or the front window's screen.
- **Launch at Login** -- one-click toggle in the menu bar.
- **Menu bar only** -- no dock icon, no window, just the search bar when you need it.

## Requirements

- macOS 13+
- Disable Spotlight's Cmd+Space: **System Settings > Keyboard > Keyboard Shortcuts > Spotlight** (uncheck "Show Spotlight search")

## Install

### Build from source

```
git clone https://github.com/brewmium/Launchette.git
cd Launchette
make install
```

This compiles and copies `Launchette.app` to `/Applications/`.

### Run without installing

```
make run
```

## Usage

- **Cmd+Space** (or your configured hotkey) to open
- Start typing an app name -- results appear instantly
- **Arrow keys** to navigate, **Enter** to launch, **Esc** to dismiss
- Type math (`100 x 3`, `2^16`, `sqrt(2)`) and the answer appears inline -- Enter copies it
- **Right-click** a result to hide it from future searches
- Click the menu bar icon for settings: change hotkey, size, screen mode, add custom apps, manage hidden/recent apps, toggle launch at login

## Stack

Pure AppKit. No SwiftUI, no dependencies, no package manager bloat. Carbon API for the global hotkey (same mechanism Alfred and LaunchBar use). JavaScriptCore for math evaluation.

## License

Free for personal use. See [LICENSE.md](LICENSE.md) for details.
