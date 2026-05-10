# Third-Party Licenses

NotchNotch bundles the following MIT-licensed assets:

## Pixelarticons (MIT)
- Files: `BoaNotch/Resources/PixelIcons/*.svg`
- Source: https://github.com/halfmage/pixelarticons
- Copyright (c) 2020 Gerrit Halfmann
- Subset bundled (toast icons): `alert`, `chat`, `clock`, `notification`, `pacman` (the last is the pack's `bookmark` glyph renamed; the free pack has no pacman).
- Loaded via `PixelIcon.image(_:fallback:)` with SF Symbol fallbacks.

## Simple Icons (MIT)
- Files: `BoaNotch/Resources/BrandIcons/*.svg`
- Source: https://github.com/simple-icons/simple-icons
- Copyright (c) 2017-present The Simple Icons contributors
- Subset bundled (brand glyphs for the Tools tab Apps section): `gmail`, `googlecalendar`, `googledrive`, `googlemeet`, `notion`, `spotify`.
- Refresh: edit the `SLUGS` array in `scripts/fetch-brand-icons.sh` and run it manually.
- Rendered as template images so `BrandIconView` can tint via `foregroundStyle`. Brand colors with luminance < 0.18 are substituted with `.primary` so they remain visible on the panel's near-black background (Notion's `#000000` is the canonical case).

## Sparkle (MIT)
- Source: https://github.com/sparkle-project/Sparkle
- Copyright (c) Andy Matuschak and the Sparkle Project Authors
- Linked as a Swift Package Manager dependency (see `Package.swift`); `Sparkle.framework` is copied into `Contents/Frameworks/` at release time by `scripts/release.sh`. Drives the in-app auto-update flow with EdDSA-signed appcasts.

## Lobe Icons (MIT)
- Files: `BoaNotch/Resources/provider_*.svg`
- Source: https://github.com/lobehub/lobe-icons
- Copyright (c) 2023 LobeHub
- Subset bundled (mono / `currentColor` template variants):
  openai, claude, gemini, minimax, openrouter, huggingface, zai, kimi,
  nousresearch.
- Refresh: `bash scripts/fetch-provider-icons.sh --force`

## Yams (MIT)
- Source: https://github.com/jpsim/Yams
- Copyright (c) 2016-present Norio Nomura and other Yams contributors
- Linked as a Swift Package Manager dependency (see `Package.swift`).

The MIT license text in full:

```
Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
```
