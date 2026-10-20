#!/bin/bash
# Builds the app and the release files: build/WheelOfTools-<version>.dmg (drag-to-Applications installer) and .zip
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-1.2}"
export VERSION
scripts/make_app.sh
ditto -c -k --keepParent "build/Wheel of Tools.app" "build/WheelOfTools-$VERSION.zip"
shasum -a 256 "build/WheelOfTools-$VERSION.zip"
scripts/make_dmg.sh "$VERSION"
echo "Release files: build/WheelOfTools-$VERSION.dmg and .zip"
