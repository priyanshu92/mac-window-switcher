# Window Switcher for Mac

A native macOS menu bar app that replaces Command-Tab's app icon strip with a visual switcher for individual windows.

## What it does

- Hold `Command` and tap `Tab` to open a filmstrip of window previews.
- Keep tapping `Tab` to move forward or use `Shift+Tab` to move backward.
- Release `Command` to focus the selected window.
- Press `Esc` to cancel.
- Switch between multiple windows from the same app.
- Keep the switcher open while apps launch or close - its window list updates live.
- See continuously refreshed previews rather than a one-time thumbnail.
- Size previews to the display containing the current window and crop them edge to edge.
- Include minimized windows and restore them when selected.
- Press `Q` while holding `Command` to quit the selected app.
- Use the menu bar icon to preview the switcher, change behavior, manage permissions, or launch at login.

## Requirements

- macOS 13 or later
- Accessibility permission to enumerate and focus windows
- Input Monitoring permission to replace the system Command-Tab gesture
- Screen Recording permission to render window previews

The app opens its preferences window on first launch so these permissions can be granted.
macOS may require the app to be restarted after a permission is enabled.

## Build and run

```bash
swift run WindowSwitcherForMacApp
```

Launch directly into the switcher overlay while developing:

```bash
swift run WindowSwitcherForMacApp --preview
```

Run the validation suite and debug build:

```bash
./Scripts/validate.sh
```

Install a release build as `/Applications/Window Switcher.app`:

```bash
./Scripts/install.sh
open "/Applications/Window Switcher.app"
```

## Project structure

```text
Sources/
├── AppCore/                    # Settings and pure display logic
├── PlatformServices/           # Permissions, event tap, window discovery and activation
├── ValidationRunner/           # Isolated persistence and behavior assertions
└── WindowSwitcherForMacApp/    # Menu bar lifecycle, preferences, overlay and SwiftUI cards
```
