#!/bin/bash
# Builds the drag-to-Applications installer: build/WheelOfTools-<version>.dmg
# Needs the app built first (scripts/make_app.sh) and Automation permission for Finder (to style the window).
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-1.0}"
VOL="Wheel of Tools"
APP="build/Wheel of Tools.app"
OUT="build/WheelOfTools-$VERSION.dmg"
RW="build/rw.dmg"
STAGE="build/dmg-stage"
[ -d "$APP" ] || { echo "Build the app first: scripts/make_app.sh"; exit 1; }

rm -rf "$STAGE" "$RW" "$OUT"; mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Window background: soft gradient, an arrow between the two icons, and a hint.
magick -size 660x400 gradient:'#f5f7fa-#dfe5ee' \
  -stroke '#8a94a6' -strokewidth 6 -fill none -draw "line 285,200 365,200" \
  -fill '#8a94a6' -stroke none -draw "polygon 380,200 358,184 358,216" \
  -font /System/Library/Fonts/Helvetica.ttc -fill "#4a5568" -pointsize 22 -gravity south -annotate +0+52 "Drag Wheel of Tools to Applications" \
  "$STAGE/.background/bg.png"

hdiutil detach "/Volumes/$VOL" >/dev/null 2>&1 || true
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ -format UDRW -o "$RW" >/dev/null
hdiutil attach "$RW" -readwrite -noverify -noautoopen >/dev/null
sleep 2
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 548}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:bg.png"
    set position of item "Wheel of Tools.app" of container window to {170, 190}
    set position of item "Applications" of container window to {490, 190}
    -- Keep hidden items out of sight for people whose Finder shows dotfiles.
    try
      set position of item ".background" of container window to {1200, 1200}
    end try
    try
      set position of item ".fseventsd" of container window to {1200, 1200}
    end try
    update without registering applications
    delay 2
    set the bounds of container window to {200, 120, 860, 548}
    delay 1
    log (get bounds of container window)
    close
  end tell
end tell
APPLESCRIPT
sync
hdiutil detach "/Volumes/$VOL" >/dev/null
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -rf "$RW" "$STAGE"
shasum -a 256 "$OUT"
echo "Installer: $OUT"
