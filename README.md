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

## Install

1. Download the latest `Window-Switcher-*.app.zip` from the [Releases page](https://github.com/priyanshu92/mac-window-switcher/releases/latest).
2. Double-click the zip in Finder to extract it.
3. Drag `Window Switcher.app` into the Applications folder.
4. Launch the app once. If macOS blocks it, click **Done**, then open **System Settings > Privacy & Security** and click **Open Anyway**.
5. Grant Accessibility, Screen Recording, and Input Monitoring permissions when prompted.

If Gatekeeper still blocks the app, run:

```bash
xattr -dr com.apple.quarantine "/Applications/Window Switcher.app"
open "/Applications/Window Switcher.app"
```

## Development

```bash
swift run WindowSwitcherForMacApp
```

Launch directly into the switcher overlay while developing:

```bash
swift run WindowSwitcherForMacApp --preview
```

Open Preferences directly:

```bash
swift run WindowSwitcherForMacApp --preferences
```

Run the validation suite and debug build:

```bash
./Scripts/validate.sh
```

Build and install the current source:

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
