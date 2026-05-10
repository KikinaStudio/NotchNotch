#!/bin/bash
# Détecte les hardcodes design (font sizes, white opacities, font aliases natifs)
# hors DesignSystem.swift.
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

echo
echo "🔍 Font aliases natifs SwiftUI hors DS.Text (.font(.callout/.footnote/.body/.caption/...)):"
# On ne flag que `.font(.X` ou `.font(.X.modifier)` — les usages explicites
# dans un appel `.font()`. Évite les faux positifs sur `var body: some View`,
# `\.body` (KeyPath) ou `.body)` côté struct.
find BoaNotch -name "*.swift" ! -name "DesignSystem.swift" -print0 \
  | xargs -0 grep -nE '\.font\((\.callout|\.footnote|\.body|\.caption2?|\.headline|\.subheadline|\.title2?3?|\.largeTitle)([.)])' \
  || true
