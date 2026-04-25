#!/bin/bash
# Détecte les hardcodes design (font sizes, white opacities) hors DesignSystem.swift.
# Lancer depuis n'importe où: ./scripts/lint-design.sh
# Format de sortie: fichier:ligne (cliquable dans Cursor/VS Code).

cd "$(dirname "$0")/.." || exit 1

echo "🔍 Font sizes hardcodés (.system(size:)):"
find BoaNotch -name "*.swift" ! -name "DesignSystem.swift" -print0 \
  | xargs -0 grep -nE '\.system\(size:' || true

echo
echo "🔍 White opacity hardcodés (.white.opacity()):"
find BoaNotch -name "*.swift" ! -name "DesignSystem.swift" -print0 \
  | xargs -0 grep -nE '\.white\.opacity\(' || true
