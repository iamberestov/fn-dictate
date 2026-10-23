#!/usr/bin/env bash
# Builds FnDictate.app next to this script (menu-bar agent) with SwiftPM; needs Swift 6.2 or newer.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/FnDictate.app
# The macOS 27 SDK makes SwiftUI's @State a macro whose plugin ships only with full Xcode,
# so with Command Line Tools alone build against the newest 26.x SDK.
if [ -z "${SDKROOT:-}" ] && [ "$(xcrun --show-sdk-version | cut -d. -f1)" -ge 27 ]; then
  pick="$(ls -d "$(xcode-select -p)"/SDKs/MacOSX26.*.sdk 2>/dev/null | sort -V | tail -n1)"
  if [ -n "$pick" ]; then export SDKROOT="$pick"; echo "building against $pick"; fi
fi
swift build -c release --product FnDictate
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --product FnDictate --show-bin-path)/FnDictate" "$APP/Contents/MacOS/FnDictate"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.igor.fndictate</string>
  <key>CFBundleName</key><string>FnDictate</string>
  <key>CFBundleExecutable</key><string>FnDictate</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Records your voice while you hold Fn.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Transcribes your dictation on device.</string>
  <key>NSAccessibilityUsageDescription</key><string>Pastes dictated text into the focused input.</string>
</dict>
</plist>
PLIST
SIGN_ID="${FNDICTATE_SIGN_ID:-FnDictate Dev}"
# A stable certificate keeps macOS privacy grants across rebuilds; ad-hoc signing resets them.
if security find-certificate -c "$SIGN_ID" >/dev/null 2>&1; then
  codesign --force --sign "$SIGN_ID" "$APP"
else
  echo "certificate \"$SIGN_ID\" not found, signing ad-hoc"
  codesign --force --sign - "$APP"
fi
echo "built $APP"
