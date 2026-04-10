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

### Starting Hermes locally

Hermes must be running for NotchNotch to work. Start it with its venv:

```bash
cd ~/.hermes/hermes-agent && ./venv/bin/python3 hermes gateway run
```

- The binary is at `~/.hermes/hermes-agent/hermes` but **must** be run with `./venv/bin/python3` (system Python is 3.9, Hermes needs 3.10+ for `str | None` syntax).
- The API server is started via `hermes gateway run`, NOT `hermes serve` (which doesn't exist).
- Health check: `curl http://localhost:8642/health`

## Key architecture

- `HermesClient.swift` — Single-request streaming via `POST /v1/responses` with `stream: true` and server-side conversation persistence via `conversation` parameter (UUID stored in UserDefaults). Fire-and-forget brain saves via `sendCompletion` (non-streaming `/v1/responses` with `store: false`). `conversationId` persists across app launches; `resetConversation()` generates a new UUID for fresh context.
- `SessionStore.swift` — Auto-detects Telegram `user_id` from `~/.hermes/state.db`, prefixes with `notchnotch-` for the `session_id` field
- `SSEParser.swift` — Routes SSE events from `/v1/responses` streaming: `response.output_text.delta` (with `<think>` tag parsing), `tool.started`, `tool.completed`, `response.completed`. Also supports legacy `/v1/runs` format (`message.delta`, `run.completed`) via `json["event"]` fallback. No heuristics.
- `NotchView.swift` — Root view with flanking buttons overlay beside the hardware notch
- `NotchDropDelegate` — Custom DropDelegate in NotchView.swift for split drop zones (attach left, brain right)
- `ClipperListener.swift` — NWListener HTTP server on port 19944, receives toast notifications from the NotchNotch Clipper Chrome extension
- `NotchShape.swift` — Custom animatable shape (quad curves matching hardware notch)
- `HermesConfig.swift` — Watches `~/.hermes/config.yaml` with file system events. `availableModels` returns a flat list of all models with routing info `(value, label, provider, baseURL)`. `switchModel()` writes `model.default`, `model.provider`, and `model.base_url` atomically in a single file write via `Data.write(options: .atomic)`. The old `writeToConfig` method also uses this pattern (NOT tmp+moveItem which fails on macOS). Reasoning effort supports `none`/`minimal`/`low`/`medium`/`high`/`xhigh`.

### Conversation flow (v0.10)

1. `ChatViewModel.send()` calls `HermesClient.streamCompletion(input:)` — single `POST /v1/responses` with `stream: true`, `store: true`, `conversation: <UUID>`
2. Server returns SSE events: `response.created`, `response.output_text.delta`, `tool.started`, `tool.completed`, `response.completed`, `[DONE]`
3. `SSEParser` routes deltas through `routeContent()` for `<think>` tag detection, tool events formatted as `→ tool preview` / `✓ tool (0.1s)`
4. Server persists the full conversation history (including tool calls) in `~/.hermes/response_store.db` — next turn automatically chains via the `conversation` name
5. `confirmNewConversation()` calls `client.resetConversation()` to generate a fresh UUID — no `/new` command sent

### Brain save pattern (v0.9)

The drop zone "Save to brain", voice notes, and the Clipper extension all use the same flow:

1. `ChatViewModel.saveToBrain(content:fileName:)` builds a prompt: `"Please save the following content to your memory. File: <name>\n\n<content>"`
2. `HermesClient.sendCompletion(messages:)` sends `POST /v1/responses` with `store: false`, checks HTTP 200, discards body
3. Toast shown via `notchVM.showToast()`

The NotchNotch Clipper Chrome extension uses the identical API pattern, then pings `localhost:19944/clip` to trigger a pacman toast in the notch.

## Important gotchas

- **Conversation history is server-side**: NotchNotch no longer sends `conversation_history` — the server chains responses via the `conversation` UUID. The stored history includes full agent messages (tool calls + results), which can grow large in tool-heavy conversations. If this becomes a problem, check that Hermes's context compression handles tool results well — do NOT strip them from the response store.
- **Session ID prefix (legacy)**: `session_id` was used with `/v1/runs` and had to be `notchnotch-<user_id>`. Now using `/v1/responses` with `conversation` parameter instead. The `sessionId` property is still passed in the request body for Telegram continuity but is no longer the primary conversation mechanism.
- **DropDelegate, not .onDrop closure**: The split drop zone requires `DropInfo.location` for position detection, which is only available via a `DropDelegate`. The simple `.onDrop(of:isTargeted:)` closure does not expose cursor position.
- **NWListener response timing**: In `ClipperListener.swift`, do NOT use `defer { connection.cancel() }` in the receive handler — it cancels the connection before `connection.send()` completes. Let the send completion handler call `connection.cancel()`.
- **Bundle.module path**: SPM's generated `Bundle.module` looks for `BoaNotch_BoaNotch.bundle` at `Bundle.main.bundleURL` (app root), NOT in `Contents/Resources/`. Logo loading via `Bundle.module` currently fails at runtime — needs fixing.
- **Ad-hoc signed**: Triggers Gatekeeper. Users need `xattr -cr` or right-click > Open.
- **SPM target name**: Still `BoaNotch` in Package.swift (renamed to `notchnotch` only at the app bundle level).
- **NotchState exhaustive switch**: Adding a new case to `NotchState` enum requires updating the switch in `NotchWindowController.swift` (line ~61) or the build fails.
- **Chrome extension local path**: The extension is loaded from `~/NotchNotch Extension/` on the dev machine, NOT from the git repo clone. Changes to the repo must be copied there and the extension reloaded in Chrome.

## Companion projects

- **[NotchNotch-Clipper](https://github.com/KikinaStudio/NotchNotch-Clipper)** — Chrome extension that clips web pages to Hermes's brain. After a successful Hermes save, it POSTs `{"title","url"}` to `localhost:19944/clip` which triggers the pacman toast in NotchNotch. Loaded locally from `~/NotchNotch Extension/`.

## Conventions

- Language: Swift 5.9, macOS 14+ deployment target
- UI: SwiftUI with AppKit (NSPanel, NSStatusItem, Carbon hotkeys)
- No external dependencies — all standard frameworks (Network.framework for ClipperListener)
- French locale for speech transcription
- Purple/violet accent color throughout
- Pacman icon for clipper toasts (animated purple circle, Canvas + TimelineView)
