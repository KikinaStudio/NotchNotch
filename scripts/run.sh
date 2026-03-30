#!/bin/bash
# Build and run BoaNotch as a proper macOS app bundle
set -e

cd "$(dirname "$0")/.."

# Build
swift build

# Create .app bundle
APP_DIR=".build/BoaNotch.app/Contents"
mkdir -p "$APP_DIR/MacOS"

# Copy binary
cp .build/debug/BoaNotch "$APP_DIR/MacOS/BoaNotch"

# Copy Info.plist
cp BoaNotch/Info.plist "$APP_DIR/Info.plist"

echo "Built BoaNotch.app"
echo "Launching..."

# Launch the app
open .build/BoaNotch.app
