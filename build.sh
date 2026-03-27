#!/bin/bash
set -euo pipefail

APP_NAME="Karabasan"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Compile universal binary (Apple Silicon + Intel)
swiftc -O -target arm64-apple-macosx13.0 \
    -o "$BUILD_DIR/$APP_NAME-arm64" \
    Sources/main.swift

swiftc -O -target x86_64-apple-macosx13.0 \
    -o "$BUILD_DIR/$APP_NAME-x86_64" \
    Sources/main.swift

lipo -create \
    "$BUILD_DIR/$APP_NAME-arm64" \
    "$BUILD_DIR/$APP_NAME-x86_64" \
    -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

rm "$BUILD_DIR/$APP_NAME-arm64" "$BUILD_DIR/$APP_NAME-x86_64"

# Copy Info.plist
cp Info.plist "$APP_BUNDLE/Contents/"

# Ad-hoc code sign
codesign --force --sign - "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
echo ""
echo "To install: cp -r $APP_BUNDLE /Applications/"
echo "To run:     open $APP_BUNDLE"
