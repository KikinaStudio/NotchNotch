#!/bin/bash
# Build, sign, package, EdDSA-sign, publish a notchnotch release.
#
# This script ships an *ad-hoc-signed* build (no Apple Developer cert).
# It does NOT call notarytool or stapler. The Gatekeeper warning persists
# on every install and every update — that's expected and documented in
# docs/GATEKEEPER_FIRST_LAUNCH.md. Sparkle handles auto-update via EdDSA
# signatures, which is independent of Apple's notarization.
#
# Pipeline:
#   1. Universal binary (arm64+x86_64)         → requires Xcode
#   2. Bundle .app + ad-hoc codesign (hardened runtime)
#   3. Build DMG (create-dmg or hdiutil)
#   4. Ad-hoc codesign the DMG
#   5. EdDSA-sign the DMG with Sparkle's sign_update (private key from Keychain)
#   6. Prepend a new <item> to appcast.xml on the gh-pages branch and push
#   7. gh release create with the DMG attached
#
# Prerequisites (one-time):
#   - Sparkle SPM dep resolved (run `swift build` once to fetch sign_update)
#   - EdDSA keypair generated (`generate_keys`); public key in Info.plist
#   - gh-pages branch exists with appcast.xml; GitHub Pages serving it
#   - `gh` CLI authenticated
#   - Optional: RELEASE_NOTES.md at repo root for the release body
set -euo pipefail

cd "$(dirname "$0")/.."

# ── Read version + build number from Info.plist ────────────────────────
VERSION=$(grep -A1 'CFBundleShortVersionString' BoaNotch/Info.plist | grep '<string>' | sed 's/.*<string>\(.*\)<\/string>/\1/')
BUILD_NUMBER=$(grep -A1 'CFBundleVersion' BoaNotch/Info.plist | grep '<string>' | sed 's/.*<string>\(.*\)<\/string>/\1/')
APP_NAME="notchnotch"
SPM_TARGET="BoaNotch"
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
TAG="v${VERSION}"
REPO="KikinaStudio/NotchNotch"

# ── Sanity check: Xcode required for universal binary ──────────────────
if ! xcodebuild -version &>/dev/null; then
    echo "❌ Xcode is required for a release build (universal arm64+x86_64)."
    echo "   Install Xcode from the App Store, accept the license, and re-run."
    exit 1
fi

# ── Sanity check: tag must not already exist ───────────────────────────
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "❌ Tag $TAG already exists locally. Bump CFBundleShortVersionString first."
    exit 1
fi

# ── Build universal binary ─────────────────────────────────────────────
echo "Building notchnotch v${VERSION} (universal binary: arm64 + x86_64)..."
swift build -c release --arch arm64 --arch x86_64
BINARY=".build/apple/Products/Release/${SPM_TARGET}"

# ── Bundle .app ────────────────────────────────────────────────────────
APP_DIR=".build/${APP_NAME}.app/Contents"
rm -rf ".build/${APP_NAME}.app"
mkdir -p "$APP_DIR/MacOS" "$APP_DIR/Resources"

cp "$BINARY" "$APP_DIR/MacOS/${APP_NAME}"
cp BoaNotch/Info.plist "$APP_DIR/Info.plist"
cp BoaNotch/Resources/*.png "$APP_DIR/Resources/" 2>/dev/null || true
cp BoaNotch/Resources/*.icns "$APP_DIR/Resources/" 2>/dev/null || true
cp BoaNotch/Resources/*.json "$APP_DIR/Resources/" 2>/dev/null || true
cp BoaNotch/Resources/*.svg "$APP_DIR/Resources/" 2>/dev/null || true
cp BoaNotch/Resources/PixelIcons/*.svg "$APP_DIR/Resources/" 2>/dev/null || true

# Copy Sparkle.framework into the app bundle (Sparkle needs to ship inside Frameworks/)
SPARKLE_FRAMEWORK=$(find .build/artifacts/sparkle -name "Sparkle.framework" -type d | head -1)
if [ -z "$SPARKLE_FRAMEWORK" ]; then
    echo "❌ Sparkle.framework not found. Run 'swift build' once to fetch it."
    exit 1
fi
mkdir -p "$APP_DIR/Frameworks"
cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Frameworks/"

# swift build doesn't include @executable_path/../Frameworks in the binary's
# rpath, so dyld can't find the embedded Sparkle.framework. Add it before
# codesign — install_name_tool warns about invalidating the signature, but
# we resign right after.
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_DIR/MacOS/${APP_NAME}"

# ── Codesign app (ad-hoc, deep, hardened runtime) ──────────────────────
echo "Signing ${APP_NAME}.app (ad-hoc, hardened runtime)..."
codesign --force --deep --sign - \
    --entitlements BoaNotch/BoaNotch.entitlements \
    --options runtime \
    ".build/${APP_NAME}.app"

# ── Verify architectures ───────────────────────────────────────────────
echo ""
echo "Architecture check:"
file "$APP_DIR/MacOS/${APP_NAME}"
echo ""

# ── Stage DMG contents ─────────────────────────────────────────────────
STAGING="/tmp/${APP_NAME}-dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R ".build/${APP_NAME}.app" "$STAGING/"

cat > "$STAGING/INSTALL.txt" <<EOF
notchnotch v${VERSION}
======================

1. Drag notchnotch.app onto the Applications folder.
2. First launch: right-click notchnotch.app → Open → Open.
   (macOS blocks ad-hoc-signed apps by default. The right-click bypass
    is normal; full guide at github.com/KikinaStudio/NotchNotch/blob/master/docs/GATEKEEPER_FIRST_LAUNCH.md)
3. Hermes (the AI agent) installs automatically on first launch.

Requirements: macOS 14 (Sonoma) or later. Universal binary (Apple
Silicon + Intel).

Auto-updates: notchnotch checks for updates automatically. When one is
available, you'll get a prompt — click "Install and Relaunch". Each
update will require the same first-launch step above.
EOF

# ── Create DMG ─────────────────────────────────────────────────────────
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
    echo "create-dmg not found; falling back to hdiutil (no positioned layout)."
    echo "(install with: brew install create-dmg)"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "notchnotch v${VERSION}" \
        -srcfolder "$STAGING" \
        -ov -format UDZO \
        ".build/${DMG_NAME}"
fi

rm -rf "$STAGING"

# ── Codesign DMG (ad-hoc) ──────────────────────────────────────────────
echo "Signing DMG (ad-hoc)..."
codesign --force --sign - ".build/${DMG_NAME}"

# ── EdDSA-sign DMG with Sparkle's sign_update ──────────────────────────
SIGN_UPDATE=$(find .build/artifacts/sparkle -name sign_update -type f -path '*/bin/sign_update' | head -1)
if [ -z "$SIGN_UPDATE" ]; then
    echo "❌ Sparkle's sign_update tool not found. Run 'swift build' to fetch it."
    exit 1
fi

echo "EdDSA-signing DMG..."
SIGN_OUTPUT=$("$SIGN_UPDATE" ".build/${DMG_NAME}")
# sign_update prints e.g.: sparkle:edSignature="..." length="12345"
ED_SIG=$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
DMG_SIZE=$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')

if [ -z "$ED_SIG" ] || [ -z "$DMG_SIZE" ]; then
    echo "❌ Could not parse sign_update output: $SIGN_OUTPUT"
    exit 1
fi
echo "  edSignature: ${ED_SIG:0:32}..."
echo "  size: ${DMG_SIZE} bytes"

# ── Update appcast.xml on gh-pages (via worktree) ──────────────────────
echo ""
echo "Updating appcast.xml on gh-pages..."
WORKTREE=".build/gh-pages-release"
rm -rf "$WORKTREE"
git worktree add "$WORKTREE" gh-pages
trap 'rm -rf "$WORKTREE"; git worktree prune' EXIT

export PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
if [ -f RELEASE_NOTES.md ]; then
    export RELEASE_NOTES_BODY=$(cat RELEASE_NOTES.md)
else
    export RELEASE_NOTES_BODY="See https://github.com/${REPO}/releases/tag/${TAG} for release notes."
fi
export APPCAST_PATH="${WORKTREE}/appcast.xml"
export VERSION BUILD_NUMBER REPO TAG DMG_NAME ED_SIG DMG_SIZE

# Prepend new <item> just before </channel>. Python avoids sed-on-XML.
python3 <<'PYEOF'
import os, re
from pathlib import Path

env = os.environ
notes = env["RELEASE_NOTES_BODY"].replace("]]>", "]]]]><![CDATA[>")

item = f"""    <item>
      <title>Version {env['VERSION']}</title>
      <pubDate>{env['PUB_DATE']}</pubDate>
      <sparkle:version>{env['BUILD_NUMBER']}</sparkle:version>
      <sparkle:shortVersionString>{env['VERSION']}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
{notes}
      ]]></description>
      <enclosure url="https://github.com/{env['REPO']}/releases/download/{env['TAG']}/{env['DMG_NAME']}"
                 sparkle:edSignature="{env['ED_SIG']}"
                 length="{env['DMG_SIZE']}"
                 type="application/octet-stream"/>
    </item>
"""

p = Path(env["APPCAST_PATH"])
xml = p.read_text()
new_xml = re.sub(r'(\s*</channel>)', '\n' + item + r'\1', xml, count=1)
if new_xml == xml:
    raise SystemExit("Failed to find </channel> in appcast.xml")
p.write_text(new_xml)
print("appcast.xml updated.")
PYEOF

git -C "$WORKTREE" add appcast.xml
git -C "$WORKTREE" commit -m "appcast: ${TAG}"
git -C "$WORKTREE" push origin gh-pages

# ── Create GitHub release ──────────────────────────────────────────────
echo ""
echo "Creating GitHub release ${TAG}..."
if [ -f RELEASE_NOTES.md ]; then
    gh release create "$TAG" ".build/${DMG_NAME}" \
        --title "notchnotch ${TAG}" \
        --notes-file RELEASE_NOTES.md
else
    gh release create "$TAG" ".build/${DMG_NAME}" \
        --title "notchnotch ${TAG}" \
        --generate-notes
fi

# ── Done ───────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  Released: notchnotch ${TAG}"
echo "========================================"
ls -lh ".build/${DMG_NAME}"
echo ""
echo "  Appcast:  https://kikinastudio.github.io/NotchNotch/appcast.xml"
echo "  Release:  https://github.com/${REPO}/releases/tag/${TAG}"
echo ""
