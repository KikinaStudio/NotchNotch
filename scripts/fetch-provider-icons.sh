#!/usr/bin/env bash
# scripts/fetch-provider-icons.sh
# Downloads lobehub mono SVG icons for the LLM providers we expose in NotchNotch.
# Files are written flat into BoaNotch/Resources/ as provider_<slug>.svg —
# matches the existing call_bell.svg pattern picked up by run.sh / release.sh.
# Idempotent: skip files that already exist unless --force.
set -euo pipefail

DEST="$(cd "$(dirname "$0")/.." && pwd)/BoaNotch/Resources"
BASE="https://unpkg.com/@lobehub/icons-static-svg@latest/icons"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

# slug list — must stay in sync with ProviderIconCatalog.swift
SLUGS=(openai claude gemini minimax openrouter huggingface zai kimi nousresearch)

for slug in "${SLUGS[@]}"; do
  out="$DEST/provider_${slug}.svg"
  if [[ -f "$out" && $FORCE -eq 0 ]]; then
    echo "skip  provider_${slug}.svg (use --force to re-fetch)"
    continue
  fi
  echo "fetch provider_${slug}.svg"
  curl -sSL --fail "$BASE/${slug}.svg" -o "$out"
  # NSImage(contentsOf:) cannot resolve `width="1em"` to a pixel size, so the
  # icon renders invisibly. Rewrite to `width="24" height="24"` (matching the
  # viewBox) — same convention as the bundled call.bell.svg.
  /usr/bin/sed -i '' -E 's/width="1em"/width="24"/; s/height="1em"/height="24"/' "$out"
done

echo
echo "Done. Provider icons in $DEST:"
ls -1 "$DEST" | grep "^provider_"
