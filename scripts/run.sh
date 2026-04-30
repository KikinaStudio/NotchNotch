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
cp BoaNotch/Resources/*.svg "$APP_DIR/Resources/" 2>/dev/null || true
cp BoaNotch/Resources/PixelIcons/*.svg "$APP_DIR/Resources/" 2>/dev/null || true

# Note: no SPM resource bundle copy — all loads go through Bundle.main
# from Contents/Resources.

# Copy Sparkle.framework into the bundle (Sparkle ships inside Frameworks/)
SPARKLE_FRAMEWORK=$(find .build/artifacts/sparkle -name "Sparkle.framework" -type d | head -1)
if [ -z "$SPARKLE_FRAMEWORK" ]; then
    echo "❌ Sparkle.framework not found. Run 'swift build' once to fetch it."
    exit 1
fi
mkdir -p "$APP_DIR/Frameworks"
cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Frameworks/"

# swift build's binary has @loader_path but not @executable_path/../Frameworks
# in its rpath, so dyld can't find the embedded Sparkle.framework. Add it
# before codesign — install_name_tool warns about invalidating the signature,
# but we resign right after so that's fine.
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_DIR/MacOS/notchnotch"

# Sign with entitlements (network.client) — --deep traverses into Sparkle.framework
codesign --force --deep --sign - \
    --entitlements BoaNotch/BoaNotch.entitlements \
    ".build/notchnotch.app" 2>/dev/null || true

echo "Launching notchnotch.app..."
open .build/notchnotch.app
