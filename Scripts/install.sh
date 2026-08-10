#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Window Switcher"
BUNDLE_ID="com.priyanshu.window-switcher"
APP_DIR="/Applications/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

echo "Building Window Switcher..."
swift build -c release --quiet

EXECUTABLE="$(swift build -c release --show-bin-path)/WindowSwitcherForMacApp"
if [ ! -f "$EXECUTABLE" ]; then
    echo "Build failed - executable not found."
    exit 1
fi

echo "Creating ${APP_DIR}..."
if [ -d "$APP_DIR" ]; then
    rm -rf "$APP_DIR"
fi

mkdir -p "$MACOS_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/WindowSwitcherForMacApp"

cat > "$CONTENTS_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>WindowSwitcherForMacApp</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - --timestamp=none "$APP_DIR"

echo "Installed to ${APP_DIR}"
echo "Launch with: open '${APP_DIR}'"
