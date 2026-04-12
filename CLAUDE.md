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

- `HermesClient.swift` — Non-streaming `POST /v1/responses` with server-side conversation persistence via `conversation` parameter (UUID stored in UserDefaults as `hermesConversationId`). `sendResponse(input:systemContext:)` returns a `ResponseResult` with `content`, `thinkingContent`, and `toolCalls` parsed from the response `output` array. When `systemContext` is provided, `input` is sent as `[system_msg, user_msg]` array instead of a plain string. Fire-and-forget brain saves via `sendCompletion` (non-streaming `/v1/responses` with `store: false`). `conversationId` persists across app launches; `resetConversation()` generates a new UUID for fresh context. `HermesError.httpErrorWithBody(Int, String)` captures the server response body on HTTP errors for actionable messages in the UI.
- `SessionStore.swift` — Auto-detects Telegram `user_id` from `~/.hermes/state.db`, prefixes with `notchnotch-` for the `session_id` field. Also provides conversation history via `loadRecentSessions()` (max 30, last 30 days) and `messagesForSession(sessionId:)` — both read-only SQLite3 C API queries. `SessionSummary` and `SessionMessage` models live in the same file.
- `SSEParser.swift` — Legacy SSE parser from the `/v1/runs` era. Currently unused but kept for potential future streaming support.
- `CronStore.swift` — Watches `~/.hermes/cron/jobs.json` with DispatchSource (same pattern as HermesConfig). Decodes `CronJob` array with `sortedJobs` (enabled first, soonest `next_run_at`). Fails silently to empty array if file is missing or malformed.
- `RoutineTemplates.swift` — Data model for the routine template system. `RoutineCategory` (7 categories: Personal, Professional, Research, Travel, Health, Finance, Creator), `RoutineTemplate` (25 templates with icon, title, subtitle, schedule, deliver, inputs, and `promptTemplate` with `{{placeholder}}` tokens), `TemplateInput` (structured inputs: `.freeText`, `.picker`, `.number`, `.filePath`). `composeDraft(values:)` substitutes placeholders and prepends schedule/deliver info as natural language for Hermes to parse via its `cronjob` tool. All data is static — zero runtime cost until accessed.
- `TemplateBrowserView.swift` — Three-screen drill-down for browsing routine templates within the 640×340px notch panel. Screen 1: category picker (7 rows + "Create your own"). Screen 2: template list for selected category. Screen 3: form with input fields (TextField, capsule picker buttons, number field, NSOpenPanel file picker) and a "Create routine" button. Navigation uses `@State` with spring-animated `.move` transitions. Output: calls `onSelectTemplate(draft)` with the composed prompt string — same callback contract as the old starter templates.
- `DocumentExtractor.swift` — Handles file attachments: `extract(from: URL)` reads text/PDF/RTF or copies images to `~/.hermes/cache/images/`. `extractFromClipboardImage(_:)` converts clipboard `NSImage` to PNG, saves to the same cache dir, returns an `Attachment`. `hermesCacheDir` is `~/.hermes/cache/images/` (auto-created).
- `BrainViewModel.swift` — Read-only view model for the Brain panel. Loads `~/.hermes/memories/MEMORY.md` and `USER.md`, splits each on `§` separator into `[MemoryBlock]` (title extracted from first bold label, dash-prefix, or heading). Scans `~/.hermes/skills/<category>/<skill>/SKILL.md` with simple `---` frontmatter parsing (no Yams) to extract `name`/`description`. Checks `~/.hermes/brain/wiki/` or `~/.hermes/wiki/` for wiki articles (capped at 50, 50KB each) and computes `wikiLastUpdated` from file modification dates. `SkillInfo`, `MemoryBlock`, and `WikiArticle` models live in the same file. `loadIfNeeded()` is a one-time gate; `reload()` forces a refresh. All FileManager reads, no network calls.
- `BrainView.swift` — Three-tab panel (Memory, Skills, Wiki) for browsing Hermes knowledge. Tab bar uses capsule buttons (same style as SettingsView). Memory tab renders `§`-separated blocks as individual `MemoryCard` views (title + markdown content, subtle card background). Skills tab lists all installed skills with category badges, descriptions, and drill-down detail view. Wiki tab (hidden when no wiki directory exists) shows a compact dashboard with article count, last-updated timestamp, and "Ask" buttons — tapping sends a question to Hermes via `onSendToChat` callback (no article content preview). Refresh button reloads all sections.
- `NotchView.swift` — Root view with flanking overlay buttons (42pt inset matching the input bar). Left side: `plus.bubble` new conversation button (visible when no panel is open). Right side: burger menu — on hover the burger (`line.3.horizontal`) expands into action icons (history, search, routines, brain, settings) that fan out to the left via a ZStack with opacity/offset animation. All views stay in the hierarchy, no conditional insertion/removal. `menuButton()` helper renders each action icon. When a panel is open, the overlay shows an xmark close button instead. `RecordingToastView` appears below the closed notch during voice recording with Talk/Brain Dump action buttons.
- `NotchDropDelegate` — Custom DropDelegate in NotchView.swift for split drop zones (attach left, brain right)
- `ClipperListener.swift` — NWListener HTTP server on port 19944, receives toast notifications from the NotchNotch Clipper Chrome extension
- `NotchShape.swift` — Custom animatable shape (quad curves matching hardware notch)
- `HermesConfig.swift` — Watches `~/.hermes/config.yaml` with file system events. Reads config via Yams (`Yams.load(yaml:)` → `[String: Any]` dict navigation); writes via line-level regex replacement to preserve comments. `availableModels` returns `[(value: String, label: String)]` hardcoded per provider (switch on `modelProvider`: openai, anthropic, openrouter, default) — add new models to the relevant case. `switchModel()` writes `model.default`, `model.provider`, and `model.base_url` atomically in a single file write via `Data.write(options: .atomic)`. The old `writeToConfig` method also uses this pattern (NOT tmp+moveItem which fails on macOS). Reasoning effort supports `none`/`minimal`/`low`/`medium`/`high`/`xhigh`.

### Conversation flow (v0.11)

1. `ChatViewModel.send()` builds `fullContent` (inlined attachments + text), appends user message, calls `startRequest(input:)`
2. `startRequest(input:)` appends a placeholder assistant message, sets `isStreaming`, and launches a Task that calls `HermesClient.sendResponse(input:)` — single `POST /v1/responses` with `store: true`, `conversation: <UUID>` (non-streaming)
3. Server runs the full agent loop (including tool calls), returns a complete JSON response with `output` array containing `function_call`, `function_call_output`, `reasoning`, and `message` items
4. `HermesClient.parseOutput()` extracts `content`, `thinkingContent` (from `reasoning` items), and `toolCalls` (formatted from `function_call`/`function_call_output` items)
5. `ChatViewModel.startRequest()` runs `splitSubagentContent()` on the tool calls — lines containing `🤖` or `delegate_task` are extracted into `ChatMessage.subagentActivity`, the rest stays in `toolCallContent`
6. Server persists the full conversation history in `~/.hermes/response_store.db` — next turn automatically chains via the `conversation` name
7. `retryLastAssistant()` removes the last user+assistant pair, re-appends the user message, and calls `startRequest(input:)` to get a fresh response
8. `editMessage(id:newContent:)` updates the user message content, truncates all subsequent messages, and calls `startRequest(input:)` to regenerate. Server-side history retains the pre-edit version (acceptable for v1). Editing is blocked while streaming.
9. `startNewConversation()` cancels any stream, clears messages, nils `sessionId`, and calls `resetConversation()` for a fresh UUID. `confirmNewConversation()` delegates to it (used by the confirmation dialog).
10. Loading a historical session: `ConversationHistoryView` reads messages via `SessionStore.messagesForSession()`, converts to `ChatMessage` array, sets `chatVM.sessionId` to the session ID for `X-Hermes-Session-Id` continuity.

### Voice recording flow

Triple-tap the Control (⌃) key to start recording. A toast appears below the closed notch with a pulsing red dot and two buttons:

1. **Talk** — stops recording, transcribes via `SpeechTranscriber` (macOS `SFSpeechRecognizer`, French locale), opens notch, sends transcript as chat message
2. **Brain Dump** — stops recording, transcribes, saves transcript to Hermes memory via `saveToBrain()`, shows pacman toast "Note archivée 🧠"
3. **Triple-tap ⌃ again** while recording — cancels, discards audio

The triple-tap detection uses `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` gated on `event.keyCode == kVK_Control || kVK_RightControl` with down→up transition tracking. 0.5s sliding window, 3 releases to trigger. No Carbon hotkeys — all keyboard shortcuts were removed to avoid global key hijacking (Enter, Escape).

If transcription fails, the Talk path falls back to sending the audio file as an attachment. The Brain Dump path shows a "Transcription échouée" toast.

### Brain save pattern (v0.9)

The drop zone "Save to brain", voice notes, and the Clipper extension all use the same flow:

1. `ChatViewModel.saveToBrain(content:fileName:)` builds a prompt: `"Please save the following content to your memory. File: <name>\n\n<content>"`
2. `HermesClient.sendCompletion(messages:)` sends `POST /v1/responses` with `store: false`, checks HTTP 200, discards body
3. Toast shown via `notchVM.showToast()`

The NotchNotch Clipper Chrome extension uses the identical API pattern, then pings `localhost:19944/clip` to trigger a pacman toast in the notch.

### Brain panel (v0.12)

The Brain panel is a read-only viewer for Hermes knowledge, opened via the `brain` icon in the burger menu (`NotchViewModel.isBrainOpen`, `openBrain()`). Three tabs: Memory, Skills, Wiki.

**Memory tab — card-based display:**
- `BrainViewModel` reads `~/.hermes/memories/MEMORY.md` and `USER.md`, splits each on `§` (section sign) into `[MemoryBlock]`
- Title extraction priority: `**Bold Label**:` → `- Dash prefix:` → `## Heading` → first 40 chars
- Each block renders as a `MemoryCard` (purple title, markdown body, `.white.opacity(0.04)` card background)
- Section headers: "ABOUT YOU" (from USER.md) and "LEARNED FACTS" (from MEMORY.md)
- If a file has no `§` separators, the entire content becomes one card. Missing files = empty state.

**Hermes memory file format** (important for Clipper compatibility):
```
~/.hermes/memories/
  MEMORY.md    # Agent-curated facts, § separated blocks
  USER.md      # User profile/preferences, § separated blocks
  MEMORY.md.lock / USER.md.lock  # Lock files (ignore)
```
When Hermes saves to memory (via `saveToBrain` or its own `memory` tool), it appends `§`-separated blocks to MEMORY.md. Each block is a thematic group — a single fact, a project context, a person's details, etc. The `§` separator is Hermes's convention, not a NotchNotch invention.

**Skills tab** — Lists all installed skills from `~/.hermes/skills/<category>/<skill-name>/SKILL.md`. Each SKILL.md has YAML frontmatter (`name`, `description`). Tapping a skill shows full content in a drill-down detail view.

**Wiki tab — dashboard + ask pattern:**
- Only visible when `~/.hermes/brain/wiki/` or `~/.hermes/wiki/` exists (`hasWiki`)
- Shows article count and relative "last updated" timestamp (from file modification dates)
- Each article row has an "Ask" button — tapping it:
  1. Closes the brain panel (`notchVM.isBrainOpen = false`)
  2. Sets `chatVM.draft` to a question (e.g. `"Qu'est-ce que tu sais sur Attention Mechanisms ?"`)
  3. Calls `chatVM.send()` immediately
- Index article sends `"Résume-moi ton wiki"` instead
- NO article content preview — the wiki tab is a dashboard, not a reader
- `onSendToChat: ((String) -> Void)?` callback wired in NotchView.swift

**Wiki filesystem** (important for Clipper compatibility):
```
~/.hermes/brain/wiki/     # Primary location (Karpathy-style LLM wiki)
  index.md                # Wiki index — pinned first in the list
  topic-name.md           # One article per topic
~/.hermes/wiki/           # Fallback location (checked if brain/wiki/ doesn't exist)
```
Wiki articles are LLM-compiled summaries from ingested raw material. The Clipper could feed raw content into `~/.hermes/brain/raw/` for Hermes to compile into wiki articles, or save directly to memory via the existing `saveToBrain` pattern.

**Integration points for Clipper:**
- **Saving clipped content** → goes through `saveToBrain` → Hermes decides whether to store in MEMORY.md (facts) or process into wiki (if wiki pipeline is active)
- **ClipperListener** (`localhost:19944/clip`) → only handles the toast notification, NOT the save itself. The Clipper must call the Hermes API directly for the actual save, then ping ClipperListener for the toast.
- **Brain panel refresh** → `BrainViewModel.reload()` re-reads all files. After a Clipper save, the user can hit the refresh button in the Brain panel to see the new content. No automatic refresh on file change (no DispatchSource watcher on memory files — could be added).

### Routines (cron job display + template browser)

Read-only view of Hermes cron jobs from `~/.hermes/cron/jobs.json`. The burger menu (right-aligned overlay) reveals search, routines, and settings icons on hover — panels are mutually exclusive via `NotchViewModel.openRoutines()`, `isSearchOpen`, `isSettingsOpen`. `NotchViewModel.isMenuExpanded` drives the expand/collapse state with a 3-second auto-collapse timer (`expandMenu()`/`collapseMenu()`). `isAnyPanelOpen` computed property switches the overlay between action icons and an xmark close button.

**Template browser** — `TemplateBrowserView` provides a three-screen drill-down replacing the old 4-card starter templates. Screen 1: 7 category rows (Personal, Professional, Research, Travel, Health, Finance, Creator) with SF Symbol icons, template counts, and a "Create your own" row at the bottom. Screen 2: template list for the selected category. Screen 3: form with structured inputs (text fields, capsule picker buttons, number fields, file pickers via NSOpenPanel) and a "Create routine" button. Navigation uses `@State` — resets to categories each time the panel reopens. Transitions: `.asymmetric(.move)` with spring animation.

**Template data** — `RoutineTemplates.swift` defines 25 templates across 7 categories (`RoutineCategory.all`). Each `RoutineTemplate` has a `promptTemplate` with `{{placeholder}}` tokens and `[TemplateInput]` describing the form fields. `composeDraft(values:)` substitutes placeholders and prepends `"Schedule a new routine running <schedule>, delivered via <deliver>."` — producing a natural-language string that Hermes parses via its `cronjob(action="create", ...)` tool. NotchNotch never calls the cron API directly.

**Empty state** — shows the template browser. When jobs exist, `RoutinesView` shows the job list with a "Browse templates" link at the bottom (toggles `@State showingBrowser`).

**Job list** — when jobs exist, full-width cards sorted by enabled status then `next_run_at`. Each card shows: status dot (green=scheduled, orange=paused, pulsing accent=running), job name, human-readable schedule via `humanSchedule()` (converts cron expressions like `0 9 * * *` → "Daily at 9 AM"), run count from `repeat.completed`, and formatted next run time. Paused cards are dimmed. Count badge shows next to "Routines" title. Tapping a card sets `chatVM.activeRoutineContext` and switches to chat. Right-click context menu offers: "Change schedule" (prefills draft), "Pause"/"Resume" (auto-sends), "Remove" (prefills draft, user confirms). All actions go through chat — Hermes executes via its `cronjob` tool. Wired via `onDraftAction: ((String, Bool) -> Void)?` where the Bool triggers auto-send.

**`humanSchedule()` cron parser** — converts common 5-field cron expressions to readable text: `0 9 * * *` → "Daily at 9 AM", `0 9 * * 1-5` → "Weekdays at 9 AM", `0 9 * * 0` → "Suns at 9 AM", `0 9 * * 1,4` → "Mon & Thu at 9 AM", `*/30 * * * *` → "Every 30 min", `0 */6 * * *` → "Every 6h", `0 9 15 * *` → "Day 15, 9 AM". Falls back to raw string for unrecognized patterns. Also passes through `every Xh/Xm` interval syntax unchanged.

**CronStore JSON format** — `jobs.json` is `{"jobs": [...]}` (wrapper object), not a bare array. `CronStore.load()` tries `JobsWrapper` first, falls back to bare `[CronJob]`.

**Routine context** — when `activeRoutineContext` is set, `startRequest()` passes a `systemContext` string to `sendResponse()`, which converts the API `input` from a string to `[system_msg, user_msg]` array. The system message describes the job so Hermes knows which cron job the user is referring to. `routineCreationMode` uses the same mechanism for file-based routine creation (one-shot, resets after send).

**Hermes cron API** — Hermes exposes cron management through a tool-based interface (`cronjob(action, ...)`), not REST endpoints. Actions: `create`, `list`, `update`, `pause`, `resume`, `run`, `remove`. Schedule formats: cron expressions (`0 9 * * *`), relative delays (`30m`), intervals (`every 2h`), ISO timestamps. Delivery targets: `telegram`, `discord`, `slack`, `local`, `origin`, etc. Jobs stored in `~/.hermes/cron/jobs.json`, output in `~/.hermes/cron/output/{job_id}/`. `[SILENT]` prefix suppresses delivery.

### Conversation history

`ConversationHistoryView` — read-only browser for past Hermes sessions from `~/.hermes/state.db`. Opened via `clock.arrow.circlepath` in the burger menu. `NotchViewModel.isHistoryOpen` toggles visibility, mutually exclusive with all other panels via `openHistory()`. Sessions reload on open via `.onChange`.

Each row shows source icon (color-coded: orange for CLI, blue for Telegram, purple for Discord), title (or "Untitled"), and relative timestamp. Active session highlighted with `AppColors.accent` tint. Tapping a row loads its messages into `chatVM.messages` and sets `chatVM.sessionId` for session continuity. The [+ New] button calls `chatVM.startNewConversation()` (also accessible via the `plus.bubble` flanking button on the left side of the notch).

### Rich media in messages

**Inline image previews** — `MessageBubble.filePathAwareContent` detects image paths (png, jpg, gif, etc.) in both `.text` and `.code` blocks via `splitByFilePaths()`. Image paths render as inline thumbnails (280×200 max, rounded corners, subtle border) via `imagePreview()`. Click opens in default app; context menu offers "Open in default app" and "Reveal in Finder". Non-image paths render as `fileCard()`. If NSImage fails to load, falls through to `fileCard()`.

**Color-coded file cards** — `fileCard()` uses `colorForFileType(ext)` from `AppConstants.swift` for category-based coloring: purple for code, pink for audio, blue for video, green for images, red for PDF, orange for text, yellow for data formats, teal for CSV, gray for archives. Background is `color.opacity(0.15)` with a subtle `color.opacity(0.25)` border stroke and full-saturation icon+text.

**Smart file open** — File cards open the file in its default app on click (not reveal in Finder). Right-click context menu provides "Reveal in Finder" via `revealInFinder()`.

**Code block path extraction** — When a code block contains a file path and is under 300 chars, the code block is replaced by a file card (or image preview). Longer code blocks render normally. This handles Hermes's habit of wrapping file paths in code fences.

**Backtick path regex** — `splitByFilePaths()` has two regex branches: backtick-delimited paths (`` `~/path with spaces/file.ext` ``) that allow spaces, and bare paths that stop at whitespace. Hermes frequently backtick-wraps paths with spaces.

**Clipboard image paste** — `ChatView` installs a local `NSEvent` monitor for Cmd+V (stored in `@State pasteMonitor`, cleaned up on disappear). When the notch is open and the pasteboard contains `.png`/`.tiff` data, `ChatViewModel.pasteFromClipboard()` calls `DocumentExtractor.extractFromClipboardImage()` to save to cache and adds a pending attachment. Normal text paste falls through. `PendingAttachmentChip` shows a 20×20 thumbnail for image attachments instead of the generic SF Symbol.

## Important gotchas

- **Conversation history is server-side**: NotchNotch no longer sends `conversation_history` — the server chains responses via the `conversation` UUID. The stored history includes full agent messages (tool calls + results), which can grow large in tool-heavy conversations. If this becomes a problem, check that Hermes's context compression handles tool results well — do NOT strip them from the response store.
- **Session ID prefix (legacy)**: `session_id` was used with `/v1/runs` and had to be `notchnotch-<user_id>`. Now using `/v1/responses` with `conversation` parameter instead. The `sessionId` property is still passed as `X-Hermes-Session-Id` header for Telegram continuity but is no longer the primary conversation mechanism.
- **No streaming on /v1/responses**: Hermes's `/v1/responses` endpoint does not support `stream: true` (the param is silently ignored). The response arrives complete as JSON. Streaming exists on `/v1/chat/completions` and `/v1/runs` but those don't support the `conversation` persistence parameter.
- **DropDelegate, not .onDrop closure**: The split drop zone requires `DropInfo.location` for position detection, which is only available via a `DropDelegate`. The simple `.onDrop(of:isTargeted:)` closure does not expose cursor position.
- **NWListener response timing**: In `ClipperListener.swift`, do NOT use `defer { connection.cancel() }` in the receive handler — it cancels the connection before `connection.send()` completes. Let the send completion handler call `connection.cancel()`.
- **Bundle.module path**: SPM's generated `Bundle.module` looks for `BoaNotch_BoaNotch.bundle` at `Bundle.main.bundleURL` (app root), NOT in `Contents/Resources/`. Logo loading via `Bundle.module` currently fails at runtime — needs fixing.
- **Ad-hoc signed**: Triggers Gatekeeper. Users need `xattr -cr` or right-click > Open.
- **SPM target name**: Still `BoaNotch` in Package.swift (renamed to `notchnotch` only at the app bundle level).
- **NotchState exhaustive switch**: Adding a new case to `NotchState` enum (`closed`, `open`, `toast`, `clipperToast`) requires updating the switch in `NotchWindowController.swift` (line ~61) or the build fails.
- **Chrome extension local path**: The extension is loaded from `~/NotchNotch Extension/` on the dev machine, NOT from the git repo clone. Changes to the repo must be copied there and the extension reloaded in Chrome.

## Companion projects

### NotchNotch Clipper

**Repo:** [KikinaStudio/NotchNotch-Clipper](https://github.com/KikinaStudio/NotchNotch-Clipper) — Chrome extension that clips web pages to Hermes's brain.

**Current flow:**
1. User clicks the Clipper extension icon on a web page
2. Extension extracts page content (title, URL, text/selection)
3. Extension calls the Hermes API directly (`POST /v1/responses` to `localhost:8642`) with a save-to-memory prompt
4. On success, extension POSTs `{"title": "...", "url": "..."}` to `localhost:19944/clip`
5. `ClipperListener.swift` receives the POST, triggers `notchVM.showClipperToast(title)` — pacman animation + page title

**How clipped content appears in NotchNotch Brain panel:**
- Hermes processes the save prompt and writes to `~/.hermes/memories/MEMORY.md` as a `§`-separated block
- Next time the user opens Brain > Memory tab (or hits refresh), the clipped content appears as a card
- The card title is extracted from the first bold label or dash-prefixed line that Hermes wrote

**Key integration contracts:**
- Hermes API: `localhost:8642` (health check: `GET /health`)
- ClipperListener: `localhost:19944` — only accepts `POST /clip` with JSON `{"title": String, "url": String}`
- ClipperListener response: HTTP 200 with `{"status":"ok"}` on success
- The toast uses the pacman icon (purple animated circle) and auto-dismisses after 4 seconds

**Local dev path:** Extension is loaded from `~/NotchNotch Extension/` (NOT the git repo clone). Changes to the repo must be copied there and the extension reloaded in `chrome://extensions`.

## Conventions

- Language: Swift 5.9, macOS 14+ deployment target
- UI: SwiftUI with AppKit (NSPanel, NSStatusItem, NSEvent global monitors)
- Dependencies: Yams (SPM) for YAML parsing; otherwise standard frameworks (Network.framework for ClipperListener)
- French locale for speech transcription
- Purple/violet accent color throughout
- Pacman icon for clipper toasts (animated purple circle, 
Canvas + TimelineView)

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.