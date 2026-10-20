#!/bin/bash
# Builds Wheel of Tools.app and installs it to ~/Applications.
set -e
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.2}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
swift build -c release
APP="build/Wheel of Tools.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/WheelOfTools "$APP/Contents/MacOS/WheelOfTools"
[ -f scripts/AppIcon.icns ] && cp scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Wheel of Tools</string>
  <key>CFBundleDisplayName</key><string>Wheel of Tools</string>
  <key>CFBundleIdentifier</key><string>com.louisflores.wheeloftools</string>
  <key>CFBundleExecutable</key><string>WheelOfTools</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP"
DEST=/Applications; [ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
rm -rf "$DEST/Wheel of Tools.app"
cp -R "$APP" "$DEST/"
echo "Installed: $DEST/Wheel of Tools.app"
