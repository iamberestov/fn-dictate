#!/usr/bin/env bash
# Builds FnDictate.app next to this script (ad-hoc signed menu-bar agent).
set -euo pipefail
cd "$(dirname "$0")"
APP=build/FnDictate.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -target arm64-apple-macosx26.0 Sources/*.swift -o "$APP/Contents/MacOS/FnDictate"
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
