# BoaNotch

A native macOS app that lives in your MacBook's notch, providing instant access to your [Hermes](https://github.com/NousResearch/hermes-agent) AI agent without switching windows.

Built with Swift & SwiftUI. Zero dependencies. Inspired by [BoringNotch](https://github.com/TheBoredTeam/boring.notch) and [NotchNook](https://lo.cafe/notchnook).

![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)

---

## Features

### Chat in the notch
Hover or click the notch to expand a chat panel with spring animations. Messages stream in real-time via SSE from the Hermes agent API.

### Collapsible thinking & tool calls
Hermes's internal reasoning (`<think>` blocks) and tool execution (shell commands, API calls) are hidden behind collapsible toggles. Only the clean response is shown. The SSE parser uses a two-tier detection system (see [SSE Token Routing](#sse-token-routing)) with post-processing fallback to ensure clean separation.

### Search in conversation
Click the magnifying glass icon (top-left of the open notch) to open a search bar. Case-insensitive full-text search across all messages with:
- Match counter (`N/M`)
- Previous/Next navigation (chevron arrows or Enter key)
- Auto-scroll to the matched message
- Purple highlight on matching text ranges via `AttributedString.backgroundColor`

### Settings & session linking
Click the gear icon (top-right of the open notch) to open settings. Link BoaNotch to an existing Hermes conversation from any platform:
- **Auto-discovery**: reads `SELECT DISTINCT source FROM sessions` from `~/.hermes/state.db` — no code changes needed when new platforms are added
- **Currently supported**: Telegram, with Slack, Discord, WhatsApp, Signal ready when Hermes adds them
- **Session continuity**: the selected session ID is sent as `X-Hermes-Session-Id` header on every API request
- **Persistence**: selection saved in `UserDefaults`, restored on launch

### Voice memos
Press `Ctrl+Shift+R` anywhere to record. A KITT-style purple scanner line sweeps under the closed notch while recording. Press again or `Enter` to stop — the audio is transcribed locally (macOS Speech framework, French locale) and sent as text. The notch stays closed; a toast appears when Hermes responds.

A mic button in the open notch input bar provides the same functionality: tap to record (icon turns purple with pulse), tap again to stop + transcribe + auto-send. A spinning ring animation shows during transcription.

### Drag & drop files
Drag any file onto the notch to attach it. Supports images (with vision analysis), PDFs, code files, text, and 35+ formats. A violet overlay appears on drag hover.

### Smart file paths
File paths in responses are rendered as clickable cards with SF Symbol icons, filename, and relative path. Click to reveal in Finder.

### Streaming indicator
While Hermes is responding:
- **Notch closed**: extends slightly right with a braille spinner animation (unicode frames, see [Braille Spinner](#braille-spinner))
- **Notch open**: the send button becomes a braille spinner (clickable to cancel)

### Toast notifications
When the notch is closed and Hermes finishes responding, a clean black toast slides out below the notch with the beginning of the response. Tap to expand.

### Code blocks & markdown
Fenced code blocks render in monospaced style with language labels. Bold, italic, inline code, and links render natively via `AttributedString`. Orphan `**` markers (from content split across tool/response boundaries) are automatically stripped.

---

## Architecture

```
BoaNotch (NSPanel, always-on-top, level mainMenu+3)
    |
    +-- NotchShape (custom animatable path, quad curves)
    |     Closed: matches hardware notch (~185x32pt)
    |     Open: expanded chat panel (580x340pt)
    |
    +-- Top bar (when open)
    |     Left: search button (magnifying glass)
    |     Center: linked session indicator
    |     Right: settings button (gear)
    |     States: default | search bar | recording indicator
    |
    +-- Content (when open)
    |     ChatView: messages + input bar
    |       MessageBubble:
    |         [> Thought for Xs]     <- collapsible
    |         [> Used tools]         <- collapsible
    |         Clean response text    <- always visible
    |         [file.txt card]        <- clickable, Finder reveal
    |         Search highlights      <- purple bg on matching text
    |       Input bar (bare, purple cursor, buttons right-aligned)
    |         [+] [mic] [send/spinner]
    |     -- OR --
    |     SettingsView: source picker + session list
    |
    +-- Overlays
    |     KITT scanner (recording, below closed notch)
    |     Braille spinner (thinking, closed notch right side)
    |     Drop overlay (violet, file drag)
    |     Toast (response preview, below closed notch)
    |     Fade gradient (black, bottom of scroll area)
    |
    +-- Services
          HermesClient -> localhost:8642/v1/chat/completions
            X-Hermes-Session-Id header (when session linked)
          SSEParser (two-tier: strong markers + weak heuristics)
          SessionStore -> ~/.hermes/state.db (SQLite3 readonly)
          SpeechTranscriber (on-device, SFSpeechRecognizer)
          DocumentExtractor (PDF, images, code, text)
          AudioRecorder (M4A to ~/.hermes/cache/audio/)
```

## Project Structure

```
BoaNotch/
+-- Package.swift                        # SwiftPM, macOS 14+, zero deps
+-- scripts/
|   +-- run.sh                           # Build + bundle + codesign + launch
+-- BoaNotch/
    +-- BoaNotchApp.swift                # @main entry point
    +-- AppDelegate.swift                # Lifecycle, Carbon hotkeys, menu bar, voice
    +-- AppConstants.swift               # Colors, file icons, cursor modifier
    +-- Info.plist                        # LSUIElement, ATS, mic/speech permissions
    +-- BoaNotch.entitlements             # network.client
    |
    +-- Models/
    |   +-- ChatMessage.swift             # role, content, thinkingContent, toolCallContent
    |   +-- Attachment.swift              # fileName, fileType, textContent, fileURL
    |
    +-- ViewModels/
    |   +-- NotchViewModel.swift          # State machine (closed/open/toast), recording, streaming
    |   +-- ChatViewModel.swift           # Messages, streaming, send/cancel, voice, session passthrough
    |   +-- SearchViewModel.swift         # Search matches, navigation, query state
    |
    +-- Views/
    |   +-- NotchView.swift               # Root: shape + top bar + KITT + braille + overlays
    |   +-- NotchShape.swift              # Animatable Shape, quad curves, corner radii
    |   +-- ChatView.swift                # Scroll + fade + input bar + file picker
    |   +-- MessageBubble.swift           # Thinking/tool toggles, code blocks, file cards, search highlight
    |   +-- SearchBarView.swift           # Search input + match counter + nav arrows
    |   +-- SettingsView.swift            # Source picker + session list + disconnect
    |   +-- ToastView.swift               # Black toast, markdown-stripped
    |   +-- DropOverlay.swift             # Violet opaque drop zone
    |
    +-- Window/
    |   +-- NotchPanel.swift              # Borderless NSPanel subclass
    |   +-- NotchWindowController.swift   # Positioning, drag monitor, screen tracking
    |
    +-- Services/
        +-- HermesClient.swift            # OpenAI-compatible SSE client, session header
        +-- SSEParser.swift               # Two-tier token routing: thinking / toolCall / delta
        +-- SessionStore.swift            # SQLite3 reader for ~/.hermes/state.db
        +-- SpeechTranscriber.swift       # SFSpeechRecognizer, French locale, guard double-resume
        +-- DocumentExtractor.swift       # 40+ file types, 50K char limit
        +-- AudioRecorder.swift           # AVAudioRecorder, M4A, shared instance
```

---

## Requirements

- **macOS 14** (Sonoma) or later
- **MacBook with notch** (works on non-notch Macs too, positioned at top-center)
- **Hermes agent** running with API server enabled

### Hermes Setup

Add to `~/.hermes/.env`:

```bash
API_SERVER_ENABLED=true
```

Restart your Hermes gateway. Verify:

```bash
curl http://localhost:8642/health
```

### Permissions

On first use, macOS will prompt for:
- **Microphone** — for voice memos
- **Speech Recognition** — for on-device transcription
- **Accessibility** (manual) — for global Ctrl+Shift+R hotkey. Add BoaNotch.app in System Settings > Privacy & Security > Accessibility.

---

## Build & Run

```bash
git clone https://github.com/your-org/boanotch.git
cd boanotch
bash scripts/run.sh
```

The `run.sh` script: builds release binary via SwiftPM, creates `.app` bundle with Info.plist, code-signs with entitlements, launches. No Xcode required — only the Command Line Tools.

---

## Usage

### Chat
- **Hover** the notch (300ms delay) or **click** to expand
- Type and press **Return** to send
- Braille spinner replaces send button while streaming (click to cancel)
- Move cursor away to collapse (600ms delay)

### Search
- Click the **magnifying glass** icon (top-left of open notch)
- Type to search — matches are highlighted in purple across all messages
- Use **chevron arrows** or press **Enter** to jump between matches
- Counter shows current position (`3/12`)
- Click **X** to close search

### Settings & Session Linking
- Click the **gear** icon (top-right of open notch)
- Select a platform (Telegram, etc.) — sessions are loaded from `~/.hermes/state.db`
- Click a session to link it — all subsequent messages use that session's context
- The top bar shows an indicator when a session is linked
- Click the gear again to close settings
- **Disconnect** button clears the linked session

### Voice Memos
- **Ctrl+Shift+R** — start recording (KITT scanner appears under notch)
- **Ctrl+Shift+R** or **Enter** — stop, transcribe locally, send to Hermes
- **Mic button** in input bar — same flow, visible in the open notch
- Notch stays closed for hotkey path. Toast shows Hermes's response.
- Uses Carbon `RegisterEventHotKey` — works from any app, no error beep

### Attach Files
- **Drag & drop** onto the notch, or click **+** in the input bar
- Images are copied to `~/.hermes/cache/images/` for vision analysis
- PDFs, code (35+ languages), text, CSV, JSON, YAML, RTF supported
- 50K character extraction limit

### Thinking & Tool Calls
- `<think>` reasoning: hidden in collapsible "Thought for Xs" toggle
- Tool execution (commands, API calls): hidden in "Used tools" toggle
- Only the clean final response is shown by default
- Click toggles to expand and see full detail

### Quit
Menu bar icon (speech bubble) > Quit BoaNotch, or Cmd+Q from the menu.

---

## How It Works

### SSE Token Routing

The `SSEParser` classifies each streaming token from the Hermes API into one of three channels:

1. **Thinking** — content inside `<think>...</think>` tags (standard Hermes reasoning format, see [hermes-agent-reasoning-traces](https://huggingface.co/datasets/lambda/hermes-agent-reasoning-traces))
2. **Tool calls** — detected via two tiers:
   - **Strong markers** (always trigger tool mode, even after clean response): emojis (`💻🔧⚙️🔎🔍📚📋📧✍️📖`), `<tool_call>`/`<tool_response>` XML tags
   - **Weak heuristics** (only before clean response is detected): shell operators (`&&`, `||`, `2>/dev/null`), variable references (`$GAPI`, `GAPI=`), command prefixes (`python `, `bash `, `curl `), Hermes skill paths (`.hermes/skills/`), CLI flags (`--max`, `--output`)
3. **Response** — clean conversational content detected by `looksLikeCleanResponse`:
   - French pronouns (`Tu`, `Je`, `Il`, `On`, `Ce`, `Un`, `Ça`) for small SSE tokens
   - Uppercase start with no shell operators (3+ chars, excludes ALL_CAPS like `SSH`, `JSON`)
   - Numbered lists (`1. ...`)
   - Common patterns (`Voici`, `J'ai`, `Il y a`, `Le `, `La `, `C'est`, `Desolé`, etc.)

**Key design decisions:**

- `sawCleanResponse` flag: once clean text is detected, only strong markers (emojis/tags) can re-enter tool mode. This prevents keywords like "himalaya" in natural response text from being misclassified as tool output.
- `pendingRegular` buffer: when `<think>` tags and regular content arrive in the same SSE chunk, the regular content is buffered for the next `parse()` call instead of being dropped.
- **Post-processing fallback** (`extractCleanResponse`): after streaming finishes, if `content` is empty but `toolCallContent` has text, the system splits tool content into paragraphs and moves trailing clean paragraphs to `content`. This catches cases where SSE tokens are too small (single characters) for the streaming heuristic to classify correctly.

**Why heuristics instead of structured parsing?** The Hermes model internally uses `<tool_call>` XML tags (documented in the [reasoning traces dataset](https://huggingface.co/datasets/lambda/hermes-agent-reasoning-traces)), but the agent runtime intercepts these tags, executes the tools, and streams the execution output as plain text content (`delta.content`). The `<tool_call>` tags are consumed server-side and never appear in the SSE stream. Tool output arrives as free-form text with emoji markers — hence the heuristic approach.

### Braille Spinner

The braille spinner uses Unicode braille pattern characters cycling at 80ms per frame:

```
⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏
```

These are the standard frames from [unicode-animations](https://www.npmjs.com/package/unicode-animations) (`dots` pattern). Rendered with `TimelineView(.periodic(from:by:))` for leak-free animation (no `Timer` needed). Parameterized with `size` and `color` — used in two contexts:
- Closed notch thinking indicator: 14pt, accent purple
- Send button during streaming: 16pt, white, clickable to cancel

### Session Linking

BoaNotch reads Hermes session data from `~/.hermes/state.db` (SQLite3, `SQLITE_OPEN_READONLY`). The database schema is documented in the [Hermes Agent v0.7.0 release](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.4.3):

```sql
sessions (
    id TEXT PRIMARY KEY,
    source TEXT NOT NULL,     -- 'telegram', 'api_server', 'cron', etc.
    title TEXT,
    started_at REAL NOT NULL, -- Unix timestamp
    message_count INTEGER,
    -- ... plus model, tokens, cost fields
)
```

**Platform auto-discovery**: `SELECT DISTINCT source FROM sessions` populates the source picker. When Hermes adds new platforms (Slack, Discord, WhatsApp, Signal — all have defined toolsets in `config.yaml` under `platform_toolsets`), they appear automatically without code changes.

**Session continuity via `X-Hermes-Session-Id`**: the Hermes API server (v0.7.0+) supports persistent sessions via this header. The API server streams tool progress events in real-time and tracks conversation state per session. See [API server streaming docs](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.4.3).

### Window System

Custom `NSPanel` — borderless, transparent, non-activating, level `mainMenu + 3`. Panel size is fixed (620x380pt). Content animates inside via `NotchShape` clipping. The panel joins all spaces and only becomes key when the notch is open.

This approach is derived from [BoringNotch](https://github.com/TheBoredTeam/boring.notch) and [NotchNook](https://lo.cafe/notchnook), both of which use a similar borderless panel strategy. Key differences:
- BoaNotch uses a single fixed-size panel rather than dynamically resizing the window
- The notch shape uses quad curves (not rounded rects) for a closer match to the hardware notch silhouette
- Hover detection is handled via SwiftUI `.onHover` with debounced delays rather than NSTrackingArea

### Notch Detection

Hardware notch dimensions via `screen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. The gap between them defines the notch width. Fallback: 185x32pt pill centered at screen top. Height is clamped to `screen.safeAreaInsets.top`.

### Notch Shape

`NotchShape` is a custom `Shape` with `animatableData` for smooth corner radius transitions:
- **Closed**: top 6pt (concave entry curve), bottom 10pt (convex corners) — flatter than BoringNotch's default, closer to hardware
- **Open**: top 14pt, bottom 18pt — reduced from earlier versions to maintain the "less curved" feel

The shape uses `addQuadCurve` for all corners, giving a continuous curvature that approximates the hardware notch's bezier without being an exact replica.

### Animations

- Open: `.interactiveSpring(response: 0.42, dampingFraction: 0.8)`
- Close: `.interactiveSpring(response: 0.45, dampingFraction: 1.0)` (critically damped, no bounce)
- Toast: `.spring(response: 0.35, dampingFraction: 0.8)`
- Recording: `.interactiveSpring(response: 0.35, dampingFraction: 0.7)`
- Corner radii, width, height all animate via `animatableData`

### Voice Pipeline

1. Carbon `RegisterEventHotKey` intercepts Ctrl+Shift+R globally (no error beep)
2. `AVAudioRecorder` captures M4A to `~/.hermes/cache/audio/`
3. `SFSpeechRecognizer` transcribes on-device (French locale `fr-FR`, fallback to system)
4. Transcribed text sent as a regular message to Hermes
5. If transcription fails: audio file path sent as attachment with fallback note
6. Guard against double-resume of continuation (prevents crash on edge cases)

Single shared `AudioRecorder` instance — both the hotkey path (AppDelegate) and the mic button path (ChatViewModel) use the same recorder to prevent conflicts.

### Input Bar Design

The input bar has no background or chrome — just a bare text field with a purple blinking cursor (via `.tint(AppColors.accent)`). All buttons are right-aligned: `[+] [mic] [send]`. This replaces the earlier ChatGPT-style input bar with grey background and rounded corners.

A fade-to-black gradient (32pt tall `LinearGradient`) overlays the bottom of the scroll area, visually separating the last messages from the input line. Messages have 36pt bottom padding so they scroll above the fade.

### Drag Detection

Global `NSEvent.addGlobalMonitorForEvents(.leftMouseDragged)` detects file drags into the notch region (80pt tall zone at screen top). `leftMouseUp` monitor clears the drag state.

---

## API

| Endpoint | Method | Headers | Description |
|----------|--------|---------|-------------|
| `localhost:8642/health` | GET | — | Health check |
| `localhost:8642/v1/chat/completions` | POST | `Content-Type: application/json`, `X-Hermes-Session-Id: <id>` (optional) | Chat completions (SSE streaming) |

Request:
```json
{
  "model": "hermes-agent",
  "messages": [{"role": "user", "content": "Hello!"}],
  "stream": true
}
```

Timeouts: 300s request, 600s resource (allows for long tool execution chains).

The `X-Hermes-Session-Id` header enables conversation continuity with an existing Hermes session (e.g., a Telegram conversation). When set, the API server loads the session's context and continues from where it left off. See [Hermes Agent v0.7.0 release notes](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.4.3) for the full API server streaming specification.

---

## Configuration

| Setting | Location | Purpose |
|---------|----------|---------|
| `LSUIElement` | Info.plist | Hides from Dock |
| `NSAllowsLocalNetworking` | Info.plist | HTTP to localhost |
| `NSMicrophoneUsageDescription` | Info.plist | Mic permission prompt |
| `NSSpeechRecognitionUsageDescription` | Info.plist | Speech recognition prompt |
| `com.apple.security.network.client` | Entitlements | Network access |
| `API_SERVER_ENABLED=true` | `~/.hermes/.env` | Enables Hermes API |
| `API_SERVER_KEY=<token>` | `~/.hermes/.env` | Optional bearer auth |
| `hermesSessionId` | UserDefaults | Persisted linked session ID |

---

## Design Decisions & Learnings

### Why a notch app?
The MacBook notch is unused screen real estate directly in the user's line of sight. A chat interface there provides ambient access to an AI agent without window switching, dock icons, or context changes. Inspired by [NotchNook](https://lo.cafe/notchnook) (general notch utility) and [BoringNotch](https://github.com/TheBoredTeam/boring.notch) (music player in the notch).

### Why heuristic SSE parsing?
The Hermes agent model uses structured `<tool_call>` XML tags internally (documented in the [reasoning traces dataset](https://huggingface.co/datasets/lambda/hermes-agent-reasoning-traces)), but the agent runtime consumes these tags and streams tool execution output as plain text. The SSE stream contains no structural markers for tool output — only emoji prefixes (`💻`, `📚`, etc.) and shell command patterns. A two-tier heuristic (strong markers + weak patterns) with a `sawCleanResponse` gate provides reliable classification for streaming display.

### Why post-processing fallback?
SSE tokens can arrive as single characters. A token like `"C"` from `"Ce sont des..."` cannot match any pattern. The post-processing pass in `ChatViewModel.extractCleanResponse()` runs after streaming finishes and operates on full paragraphs, catching cases the streaming heuristic misses.

### Why Carbon hotkeys?
NSEvent global monitors for key events produce a system error beep on key combinations. Carbon's `RegisterEventHotKey` intercepts the event before the system processes it, eliminating the beep. This is the same approach used by macOS apps like Raycast, Alfred, and the Hermes agent CLI itself.

### Why a single AudioRecorder?
The app has two voice entry points (Ctrl+Shift+R hotkey and mic button in the UI). Using two `AudioRecorder` instances could cause conflicts if both are triggered. A single shared instance prevents this.

### Why SQLite C API directly?
The `SessionStore` uses the C `sqlite3` API rather than a Swift wrapper. macOS ships with `libsqlite3` and SwiftPM links it automatically — no external dependency needed. The database is opened `SQLITE_OPEN_READONLY` to prevent any accidental writes to Hermes state.

---

## Key References

| Resource | What it provides |
|----------|-----------------|
| [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) | The Hermes agent — API server, tools, skills, MCP, memory. BoaNotch is a native client for its `/v1/chat/completions` endpoint. |
| [Hermes Agent v0.7.0 release](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.4.3) | API server streaming, `X-Hermes-Session-Id` header, MCP stability fixes, tool progress events, platform toolsets for Telegram/Slack/Discord/WhatsApp/Signal. |
| [hermes-agent-reasoning-traces](https://huggingface.co/datasets/lambda/hermes-agent-reasoning-traces) | Dataset documenting the `<think>` and `<tool_call>` format used by Hermes models. Essential for understanding SSE parsing. |
| [unicode-animations](https://www.npmjs.com/package/unicode-animations) | Source of braille spinner frames (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`). The `dots` pattern at 80ms/frame. |
| [BoringNotch](https://github.com/TheBoredTeam/boring.notch) | Open-source macOS notch app. Provided the NSPanel/borderless window strategy, notch shape approach, and hover detection pattern. |
| [NotchNook](https://lo.cafe/notchnook) | Commercial macOS notch utility. Design inspiration for notch interaction patterns (hover-to-expand, spring animations). |

---

## Known Limitations

- **No conversation persistence** — messages are lost on restart. Hermes remembers context server-side via sessions and memory, but the UI starts blank. Use session linking to pick up where you left off.
- **Fixed notch size** — the open notch is always 580x340pt. Resizable notch with auto-grow is planned.
- **Hardcoded localhost:8642** — no UI to change the Hermes URL.
- **Tool detection is heuristic** — some tool output may leak into the response or vice versa, especially with very small SSE tokens. The post-processing fallback catches most cases.
- **arm64 only** — builds for Apple Silicon. Intel Macs need a separate build.
- **Unsigned** — triggers Gatekeeper warning. Right-click > Open to bypass.

---

## Tech Stack

- **Swift 5.9 / SwiftUI** — UI, animations, layout
- **AppKit** — NSPanel, NSEvent, NSWorkspace, NSStatusItem
- **Carbon.HIToolbox** — Global hotkeys (RegisterEventHotKey)
- **AVFoundation** — Audio recording
- **Speech** — On-device transcription (SFSpeechRecognizer)
- **SQLite3** — Hermes session database (C API, readonly)
- **PDFKit** — PDF text extraction
- **URLSession.bytes** — Async SSE streaming
- **Zero external dependencies**

---

## License

MIT
