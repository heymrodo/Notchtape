#!/bin/bash
# Builds NotchSpotify.app — a bundle is required so macOS can grant Apple Events access to Spotify.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP="NotchSpotify.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp .build/release/NotchSpotify "$APP/Contents/MacOS/"
cp -R .build/release/*.bundle "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>NotchSpotify</string>
    <key>CFBundleIdentifier</key><string>jd.notchspotify</string>
    <key>CFBundleExecutable</key><string>NotchSpotify</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Controls Spotify playback from the notch.</string>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $PWD/$APP"
