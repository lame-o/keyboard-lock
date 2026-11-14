#!/bin/zsh
# Builds "Keyboard Lock.app" and installs it to /Applications.
set -euo pipefail
cd "${0:A:h}"

APP="build/Keyboard Lock.app"
BUNDLE_ID="app.keyboardlock.KeyboardLock"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 6 -target arm64-apple-macos26.0 \
  Sources/main.swift -o "$APP/Contents/MacOS/KeyboardLock"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [[ ! -f Resources/AppIcon.icns ]]; then
  swiftc -O Tools/make-icon.swift -o build/make-icon
  build/make-icon build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --options runtime --identifier "$BUNDLE_ID" "$APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x KeyboardLock 2>/dev/null || true
  # Ad-hoc signatures change on every build, so a stale Accessibility grant
  # would silently stop working. Clear it; macOS will ask again on first lock.
  tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
  rm -rf "/Applications/Keyboard Lock.app"
  cp -R "$APP" /Applications/
  open "/Applications/Keyboard Lock.app"
  echo "Installed /Applications/Keyboard Lock.app"
fi
