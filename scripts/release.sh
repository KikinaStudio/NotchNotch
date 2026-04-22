#!/bin/bash
# Build notchnotch for release: universal binary + DMG + ad-hoc codesign
set -e

cd "$(dirname "$0")/.."

VERSION=$(grep -A1 'CFBundleShortVersionString' BoaNotch/Info.plist | grep '<string>' | sed 's/.*<string>\(.*\)<\/string>/\1/')
APP_NAME="notchnotch"
SPM_TARGET="BoaNotch"   # SPM target name (unchanged to avoid breaking build)

# Try universal binary first (requires Xcode), fall back to current arch
if xcodebuild -version &>/dev/null; then
    echo "Building notchnotch v${VERSION} (universal binary: arm64 + x86_64)..."
    swift build -c release --arch arm64 --arch x86_64 2>&1
    BINARY=".build/apple/Products/Release/${SPM_TARGET}"
else
    ARCH=$(uname -m)
    echo "Building notchnotch v${VERSION} (${ARCH} — install Xcode for universal binary)..."
    swift build -c release 2>&1
    BINARY=".build/release/${SPM_TARGET}"
fi

APP_DIR=".build/${APP_NAME}.app/Contents"
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"

rm -rf ".build/${APP_NAME}.app"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

# Copy binary (rename from SPM target to app name)
cp "$BINARY" "$APP_DIR/MacOS/${APP_NAME}"

# Copy Info.plist
cp BoaNotch/Info.plist "$APP_DIR/Info.plist"

# Copy resources (icons, logo)
cp BoaNotch/Resources/*.png "$APP_DIR/Resources/" 2>/dev/null || true
cp BoaNotch/Resources/*.icns "$APP_DIR/Resources/" 2>/dev/null || true

# Note: no SPM resource bundle copy. All resources load via Bundle.main
# from Contents/Resources. Putting the SPM bundle inside the .app breaks
# either codesign (bundle root) or Bundle.module resolution (Resources/).

# Ad-hoc codesign (avoids runtime crashes on macOS 14+)
echo "Signing ${APP_NAME}.app (ad-hoc)..."
codesign --force --deep --sign - \
    --entitlements BoaNotch/BoaNotch.entitlements \
    ".build/${APP_NAME}.app"

# Verify architectures
echo ""
echo "Architecture check:"
file "$APP_DIR/MacOS/${APP_NAME}"
echo ""

# Create DMG
echo "Creating DMG..."
rm -f ".build/${DMG_NAME}"

if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "${APP_NAME}" \
        --window-size 600 400 \
        --icon-size 128 \
        --icon "${APP_NAME}.app" 180 200 \
        --app-drop-link 420 200 \
        --no-internet-enable \
        ".build/${DMG_NAME}" \
        ".build/${APP_NAME}.app"
else
    echo "create-dmg not found, using hdiutil..."
    echo "(install with: brew install create-dmg)"
    STAGING="/tmp/${APP_NAME}-dmg-staging"
    rm -rf "$STAGING"
    mkdir -p "$STAGING"
    cp -R ".build/${APP_NAME}.app" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "$STAGING" \
        -ov -format UDZO \
        ".build/${DMG_NAME}"
    rm -rf "$STAGING"
fi

echo ""
echo "========================================"
echo "  Release: notchnotch v${VERSION}"
echo "========================================"
ls -lh ".build/${DMG_NAME}"
echo ""
echo "Install:"
echo "  open .build/${DMG_NAME}"
echo ""
echo "If Gatekeeper blocks it:"
echo "  xattr -cr /Applications/${APP_NAME}.app"
