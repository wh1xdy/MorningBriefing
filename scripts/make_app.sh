#!/bin/bash
# Assemble MorningBriefing.app from the SPM release build.
#   scripts/make_app.sh            -> dist/MorningBriefing.app
#   scripts/make_app.sh --install  -> also copy to /Applications (replaces old)
#
# Bundling is what unlocks notifications (UNUserNotificationCenter requires a
# bundle identifier), launch-at-login, the price alerts, and a proper icon.
set -euo pipefail
cd "$(dirname "$0")/.."

PKG="MorningBriefingApp"
DIST="dist"
APP="$DIST/MorningBriefing.app"
IDENTIFIER="se.alexanderwh.MorningBriefing"
VERSION="1.0.0"

echo "Building release binary..."
swift build -c release --package-path "$PKG"

echo "Assembling bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PKG/.build/release/MorningBriefingApp" "$APP/Contents/MacOS/MorningBriefing"

echo "Generating icon..."
swift scripts/make_icon.swift "$DIST/AppIcon.iconset"
iconutil -c icns "$DIST/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$DIST/AppIcon.iconset"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>sv</string>
    <key>CFBundleExecutable</key>
    <string>MorningBriefing</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${IDENTIFIER}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MorningBriefing</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <!-- Pure menubar app: hide from Dock and App Switcher -->
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "Installing to /Applications..."
    rm -rf /Applications/MorningBriefing.app
    cp -R "$APP" /Applications/
    echo "Installed: /Applications/MorningBriefing.app"
fi

echo "Done: $APP"
