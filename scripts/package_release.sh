#!/bin/bash
# Builds the app and zips it for a GitHub Release: build/WheelOfTools-<version>.zip
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-1.0}"
scripts/make_app.sh
ditto -c -k --keepParent "build/Wheel of Tools.app" "build/WheelOfTools-$VERSION.zip"
shasum -a 256 "build/WheelOfTools-$VERSION.zip"
echo "Release file: build/WheelOfTools-$VERSION.zip"
