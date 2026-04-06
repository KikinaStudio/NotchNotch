# NotchNotch — Claude Code Project Guide

## What is this

A native macOS SwiftUI app that lives in the MacBook notch, providing instant access to a [Hermes](https://github.com/NousResearch/hermes-agent) AI agent. Built with Swift 5.9 / SwiftUI, no Xcode required (Command Line Tools only).

## Before every session

**Read the Hermes agent docs first.** NotchNotch is a thin client over Hermes — understanding Hermes is essential to avoid incorrect assumptions about capabilities.

1. Fetch the latest Hermes README and features: `https://github.com/NousResearch/hermes-agent`
2. Check latest releases for new API features: `https://github.com/NousResearch/hermes-agent/releases`
3. Check local Hermes config for current state: `~/.hermes/config.yaml`
4. Check Hermes DB schema for data model: `sqlite3 ~/.hermes/state.db ".schema"`

Hermes is a full AI agent platform with: sessions, persistent memory (`~/.hermes/memories/`), skills (`~/.hermes/skills/`), cron jobs, multi-platform messaging (Telegram, Discord, Slack, WhatsApp, Signal, Email), tool execution, checkpoints, context compression, SOUL.md personas, hindsight, and 6 pluggable external memory providers. Do NOT underestimate its capabilities.

## Build & Run

```bash
bash scripts/run.sh      # Build + bundle + codesign + launch
bash scripts/release.sh   # Universal binary + DMG
```

## Key architecture

- `HermesClient.swift` — SSE streaming to `localhost:8642/v1/chat/completions`
- `SessionStore.swift` — Auto-detects Telegram `user_id` from `~/.hermes/state.db` for cross-platform session continuity via `X-Hermes-Session-Id` header. Uses `user_id` (Telegram chat ID), NOT the internal session `id`.
- `SSEParser.swift` — Two-tier token routing: thinking (`<think>`), tool calls (emoji/XML markers + weak heuristics), clean response
- `NotchView.swift` — Root view with flanking buttons overlay beside the hardware notch
- `NotchShape.swift` — Custom animatable shape (quad curves matching hardware notch)
- `HermesConfig.swift` — Watches `~/.hermes/config.yaml` with file system events

## Important gotchas

- **Bundle.module path**: SPM's generated `Bundle.module` looks for `BoaNotch_BoaNotch.bundle` at `Bundle.main.bundleURL` (app root), NOT in `Contents/Resources/`. The `run.sh` script copies to `Contents/Resources/` which doesn't match. Logo loading via `Bundle.module` currently fails at runtime — needs fixing.
- **Session ID**: `X-Hermes-Session-Id` must be the Telegram `user_id` (e.g. `7921106232`), not the Hermes internal session ID. Sending an internal session ID causes Hermes to return empty 0-token responses.
- **Ad-hoc signed**: Triggers Gatekeeper. Users need `xattr -cr` or right-click > Open.
- **SPM target name**: Still `BoaNotch` in Package.swift (renamed to `notchnotch` only at the app bundle level).

## Conventions

- Language: Swift 5.9, macOS 14+ deployment target
- UI: SwiftUI with AppKit (NSPanel, NSStatusItem, Carbon hotkeys)
- No external dependencies — all standard frameworks
- French locale for speech transcription
- Purple/violet accent color throughout
