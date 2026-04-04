#!/bin/bash
# Build and run BoaNotch as a proper macOS app bundle
set -e

cd "$(dirname "$0")/.."

# Kill existing instance
pkill -f "BoaNotch.app" 2>/dev/null || true
sleep 0.3

# Build release
echo "Building BoaNotch..."
swift build -c release 2>&1

APP_DIR=".build/BoaNotch.app/Contents"
rm -rf ".build/BoaNotch.app"
mkdir -p "$APP_DIR/MacOS"

# Copy binary
cp .build/release/BoaNotch "$APP_DIR/MacOS/BoaNotch"

# Copy Info.plist — critical for ATS localhost exception
cp BoaNotch/Info.plist "$APP_DIR/Info.plist"

# Sign with entitlements (network.client)
codesign --force --sign - \
    --entitlements BoaNotch/BoaNotch.entitlements \
    ".build/BoaNotch.app" 2>/dev/null || true

echo "Launching BoaNotch.app..."
open .build/BoaNotch.app
