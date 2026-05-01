#!/usr/bin/env bash
# fetch-brand-icons.sh — Download official monochrome SVGs from Simple Icons
# (https://github.com/simple-icons/simple-icons, MIT) for NotchNotch's curated
# Skills catalog.
#
# Usage: bash scripts/fetch-brand-icons.sh
#
# Idempotent: re-runs overwrite the existing SVGs. Tries jsDelivr first, falls
# back to GitHub raw on failure (handles CDN block / corporate networks).
#
# When you add a new brand entry to CuratedSkillCatalog.swift, add its Simple
# Icons slug below and re-run this script. SVGs are committed to the repo —
# the build scripts only copy them, they do not refetch.

set -euo pipefail

SLUGS=(
    "spotify"
    "googlecalendar"
    "gmail"
    "googledrive"
    "notion"
    "googlemeet"
)

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/BoaNotch/Resources/BrandIcons"

CDN_BASE="https://cdn.jsdelivr.net/npm/simple-icons@latest/icons"
RAW_BASE="https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons"

mkdir -p "$TARGET_DIR"

echo "Fetching ${#SLUGS[@]} brand icons from Simple Icons..."

failures=0
for slug in "${SLUGS[@]}"; do
    target="$TARGET_DIR/$slug.svg"
    cdn_url="$CDN_BASE/$slug.svg"
    raw_url="$RAW_BASE/$slug.svg"

    if curl -fL --silent --max-time 10 "$cdn_url" -o "$target.tmp" 2>/dev/null && [ -s "$target.tmp" ]; then
        mv "$target.tmp" "$target"
        size=$(wc -c < "$target" | tr -d ' ')
        echo "  ok  $slug.svg ($size bytes via jsDelivr)"
    elif curl -fL --silent --max-time 10 "$raw_url" -o "$target.tmp" 2>/dev/null && [ -s "$target.tmp" ]; then
        mv "$target.tmp" "$target"
        size=$(wc -c < "$target" | tr -d ' ')
        echo "  ok  $slug.svg ($size bytes via raw GitHub)"
    else
        rm -f "$target.tmp"
        echo "  ERR $slug — both CDN and raw fetch failed"
        failures=$((failures + 1))
    fi
done

if [ "$failures" -gt 0 ]; then
    echo
    echo "$failures icon(s) failed to download. Check network or update slug names."
    exit 1
fi

echo
echo "Done. Icons saved to $TARGET_DIR/"
echo "Next: rebuild via 'bash scripts/run.sh' to bundle them into the .app."
