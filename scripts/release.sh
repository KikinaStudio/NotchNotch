#!/bin/bash
# Build notchnotch for release: universal binary (when possible) + DMG + ad-hoc codesign
#
# Output: .build/notchnotch-v<VERSION>.dmg containing:
#   - notchnotch.app
#   - Applications (symlink)
#   - INSTALL.txt   (the xattr -cr instruction, prominently visible)
#
# Universal binary requires Xcode (not just CLT) because cross-compiling
# the Yams C dependency needs xcbuild. On a CLT-only machine the build
# falls back to the host arch and the script prints a warning so you
# don't accidentally ship arm64-only.
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
    UNIVERSAL=1
else
    ARCH=$(uname -m)
    echo "Building notchnotch v${VERSION} (${ARCH} only — install Xcode for universal binary)..."
    swift build -c release 2>&1
    BINARY=".build/release/${SPM_TARGET}"
    UNIVERSAL=0
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

# Copy resources (icons, logo, bundled configs)
cp BoaNotch/Resources/*.png "$APP_DIR/Resources/" 2>/dev/null || true
cp BoaNotch/Resources/*.icns "$APP_DIR/Resources/" 2>/dev/null || true
cp BoaNotch/Resources/*.json "$APP_DIR/Resources/" 2>/dev/null || true
cp BoaNotch/Resources/*.svg "$APP_DIR/Resources/" 2>/dev/null || true

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

# Stage DMG contents (app + INSTALL.txt — Applications symlink added by create-dmg)
STAGING="/tmp/${APP_NAME}-dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R ".build/${APP_NAME}.app" "$STAGING/"

if [ "$UNIVERSAL" = "1" ]; then
    ARCH_NOTE="works on Apple Silicon and Intel Macs"
else
    ARCH_NOTE="this build is Apple Silicon only — Intel Macs need a build made on a machine with Xcode installed"
fi

cat > "$STAGING/INSTALL.txt" <<EOF
notchnotch v${VERSION}
======================

Three steps to install:

  1. Drag notchnotch.app onto the Applications folder shown next to it.

  2. Open the Terminal app (Spotlight: Cmd+Space, type "Terminal").
     Paste this line and press Return:

         xattr -cr /Applications/notchnotch.app

     (This clears macOS's quarantine flag. notchnotch is not signed
     with an Apple Developer certificate yet, so without this step
     macOS will say it's "damaged" and refuse to open it.)

  3. Open notchnotch from your Applications folder.
     On first launch it installs Hermes (the AI agent) automatically.
     Takes about a minute.


Requirements
------------
  * macOS 14 (Sonoma) or later
  * ${ARCH_NOTE}


Trouble?
--------
  * "App is damaged"          → you skipped step 2. Run xattr -cr.
  * "Can't be opened on Mac"  → you have an Intel Mac and this is an
                                Apple Silicon-only build. See the
                                release notes on GitHub.
  * Hermes won't install      → check the GitHub README for manual
                                install instructions.

  https://github.com/KikinaStudio/NotchNotch
EOF

# Create DMG
echo "Creating DMG..."
rm -f ".build/${DMG_NAME}"

if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "notchnotch v${VERSION}" \
        --window-size 640 420 \
        --icon-size 110 \
        --icon "${APP_NAME}.app" 160 180 \
        --app-drop-link 480 180 \
        --icon "INSTALL.txt" 320 340 \
        --no-internet-enable \
        ".build/${DMG_NAME}" \
        "$STAGING"
else
    echo "create-dmg not found, falling back to hdiutil (no positioned layout)..."
    echo "(install with: brew install create-dmg)"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "notchnotch v${VERSION}" \
        -srcfolder "$STAGING" \
        -ov -format UDZO \
        ".build/${DMG_NAME}"
fi

rm -rf "$STAGING"

echo ""
echo "========================================"
echo "  Release: notchnotch v${VERSION}"
echo "========================================"
ls -lh ".build/${DMG_NAME}"
echo ""
echo "DMG contents:"
echo "  - notchnotch.app"
echo "  - Applications (drop target)"
echo "  - INSTALL.txt (visible install steps)"
echo ""
echo "Local install:"
echo "  open .build/${DMG_NAME}"
echo ""
if [ "$UNIVERSAL" = "0" ]; then
    echo "⚠️  This is an Apple Silicon-only build. Intel Macs cannot run it."
    echo "   For universal: install Xcode and re-run this script."
    echo ""
fi
