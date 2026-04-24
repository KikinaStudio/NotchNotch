#!/bin/bash
# Build and run notchnotch as a proper macOS app bundle
set -e

cd "$(dirname "$0")/.."

# Kill existing instance
pkill -f "notchnotch.app" 2>/dev/null || true
sleep 0.3

# Build release
echo "Building notchnotch..."
swift build -c release 2>&1

APP_DIR=".build/notchnotch.app/Contents"
rm -rf ".build/notchnotch.app"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

# Copy binary (SPM target is still BoaNotch)
cp .build/release/BoaNotch "$APP_DIR/MacOS/notchnotch"

# Copy Info.plist — critical for ATS localhost exception
cp BoaNotch/Info.plist "$APP_DIR/Info.plist"

# Copy resources (icons, logo, bundled configs)
cp BoaNotch/Resources/*.png "$APP_DIR/Resources/" 2>/dev/null || true
cp BoaNotch/Resources/*.icns "$APP_DIR/Resources/" 2>/dev/null || true
cp BoaNotch/Resources/*.json "$APP_DIR/Resources/" 2>/dev/null || true

# Note: no SPM resource bundle copy — all loads go through Bundle.main
# from Contents/Resources.

# Sign with entitlements (network.client)
codesign --force --sign - \
    --entitlements BoaNotch/BoaNotch.entitlements \
    ".build/notchnotch.app" 2>/dev/null || true

echo "Launching notchnotch.app..."
open .build/notchnotch.app
