# BoaNotch v0.1

A native macOS app that lives in your MacBook's notch, providing instant access to your [Hermes](https://github.com/NousResearch/hermes-agent) AI agent without switching windows.

Built with Swift & SwiftUI. Zero dependencies. Inspired by [BoringNotch](https://github.com/TheBoredTeam/boring.notch).

![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)

---

## Features

**Chat in the notch** — Hover or click the notch to expand a chat panel with spring animations. Messages stream in real-time via SSE.

**Collapsible thinking & tool calls** — Hermes's internal reasoning (`<think>` blocks) and tool execution (shell commands, API calls) are hidden by default behind collapsible toggles. Only the clean response is shown. Click to expand and see the full chain of thought or tool output.

**Voice memos** — Press `Ctrl+Shift+R` anywhere to record. A KITT-style purple scanner line sweeps under the closed notch while recording. Press again or `Enter` to stop — the audio is transcribed locally (macOS Speech framework) and sent as text to Hermes. The notch stays closed; a toast appears when Hermes responds.

**Drag & drop files** — Drag any file onto the notch to attach it. Supports images (with vision analysis), PDFs, code files, text, and 35+ formats. A violet overlay appears on drag hover.

**Smart file paths** — File paths in responses are rendered as clickable cards with SF Symbol icons, filename, and relative path. Click to reveal in Finder.

**Thinking indicator** — When Hermes is processing and the notch is closed, it extends slightly to the right showing a braille spinner animation.

**Toast notifications** — When the notch is closed and Hermes finishes responding, a clean black toast slides out below the notch with the beginning of the response.

**Code blocks** — Fenced code blocks render in a distinct monospaced style with language labels.

**Markdown** — Bold, italic, inline code, links rendered natively via `AttributedString`.

**Menu bar icon** — Speech bubble icon in the menu bar with Open/Quit actions.

**Always available** — Floats above all windows and spaces. No dock icon. Follows your notch across screen changes.

---

## Architecture

```
BoaNotch (NSPanel, always-on-top, level mainMenu+3)
    |
    +-- NotchShape (custom animatable path)
    |     Closed: matches hardware notch (~185x32pt)
    |     Open: expanded chat panel (580x340pt)
    |
    +-- ChatView (messages + input bar)
    |     MessageBubble:
    |       [> Thought for Xs]     <- collapsible, hidden by default
    |       [> Used tools]         <- collapsible, hidden by default
    |       Clean response text    <- always visible
    |       [file.txt card]        <- clickable, Finder reveal
    |     Input bar (ChatGPT-style, concentric radius)
    |
    +-- Overlays
    |     KITT scanner (recording)
    |     Braille spinner (thinking, closed notch)
    |     Drop overlay (violet, file drag)
    |     Toast (response preview)
    |
    +-- Services
          HermesClient -> http://localhost:8642/v1/chat/completions
          SSEParser (routes: thinking / toolCall / delta)
          SpeechTranscriber (on-device, macOS Speech framework)
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
    +-- Info.plist                        # LSUIElement, ATS, mic/speech permissions
    +-- BoaNotch.entitlements             # network.client
    |
    +-- Models/
    |   +-- ChatMessage.swift             # role, content, thinkingContent, toolCallContent
    |   +-- Attachment.swift              # fileName, fileType, textContent, fileURL
    |
    +-- ViewModels/
    |   +-- NotchViewModel.swift          # State (closed/open/toast), isRecording, isStreaming
    |   +-- ChatViewModel.swift           # Messages, streaming, send/cancel, notchVM binding
    |
    +-- Views/
    |   +-- NotchView.swift               # Root: notch shape + KITT + braille + overlays
    |   +-- NotchShape.swift              # Animatable Shape, corner radii
    |   +-- ChatView.swift                # Scroll + input bar + file picker
    |   +-- MessageBubble.swift           # Thinking/tool toggles, code blocks, file cards
    |   +-- ToastView.swift               # Black toast, markdown-stripped
    |   +-- DropOverlay.swift             # Violet opaque drop zone
    |
    +-- Window/
    |   +-- NotchPanel.swift              # Borderless NSPanel subclass
    |   +-- NotchWindowController.swift   # Positioning, drag monitor, screen tracking
    |
    +-- Services/
        +-- HermesClient.swift            # OpenAI-compatible SSE client (300s timeout)
        +-- SSEParser.swift               # Routes tokens: thinking / toolCall / delta
        +-- SpeechTranscriber.swift       # SFSpeechRecognizer, French locale, on-device
        +-- DocumentExtractor.swift       # 40+ file types, 50K char limit
        +-- AudioRecorder.swift           # AVAudioRecorder, M4A, ~/.hermes/cache/audio/
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

The script: builds release binary, creates `.app` bundle, copies Info.plist, code-signs with entitlements, launches.

---

## Usage

### Chat
- **Hover** the notch (300ms delay) or **click** to expand
- Type and press **Return** to send
- **Stop** button cancels streaming
- Move cursor away to collapse (600ms delay)

### Voice Memos
- **Ctrl+Shift+R** — start recording (KITT scanner appears under notch)
- **Ctrl+Shift+R** or **Enter** — stop, transcribe locally, send to Hermes
- Notch stays closed. Toast shows Hermes's response.
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

### File Paths in Responses
File paths render as clickable white cards with SF Symbol icon + filename. Below: relative path in italic monospaced. Click to reveal in Finder.

### Quit
Menu bar icon (speech bubble) > Quit BoaNotch, or Cmd+Q from the menu.

---

## How It Works

### SSE Token Routing

The `SSEParser` classifies each streaming token into one of three channels:

1. **Thinking** — content inside `<think>...</think>` tags
2. **Tool calls** — `delta.tool_calls` from the JSON, plus content matching shell patterns (`&&`, `||`, `$GAPI`, `.hermes/skills/`, `python`, etc.)
3. **Response** — clean conversational content (detected by heuristic: starts with uppercase natural language, no shell operators)

The transition from tool to response is one-way: once clean text is detected, all subsequent content goes to the response channel.

### Window System
Custom `NSPanel` — borderless, transparent, non-activating, level `mainMenu + 3`. Panel size is fixed (620x380pt). Content animates inside via `NotchShape` clipping. The panel joins all spaces and only becomes key when the notch is open.

### Notch Detection
Hardware notch dimensions via `screen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Fallback: 185x32pt pill centered at screen top.

### Animations
- Open: `.interactiveSpring(response: 0.42, dampingFraction: 0.8)`
- Close: `.interactiveSpring(response: 0.45, dampingFraction: 1.0)`
- Corner radii morph: closed 6/14pt, open 19/24pt
- Input bar radius 8pt (concentric with 24pt notch bottom, 16pt gap)

### Voice Pipeline
1. Carbon `RegisterEventHotKey` intercepts Ctrl+Shift+R globally
2. `AVAudioRecorder` captures M4A to `~/.hermes/cache/audio/`
3. `SFSpeechRecognizer` transcribes on-device (French locale, fallback to system)
4. Transcribed text sent as a regular message to Hermes
5. If transcription fails: audio file path sent with fallback note

### Drag Detection
Global `NSEvent.addGlobalMonitorForEvents(.leftMouseDragged)` detects file drags into the notch region (80pt tall zone at screen top). `leftMouseUp` monitor clears the drag state.

---

## API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `http://localhost:8642/health` | GET | Health check |
| `http://localhost:8642/v1/chat/completions` | POST | Chat completions (SSE streaming) |

Request:
```json
{
  "model": "hermes-agent",
  "messages": [{"role": "user", "content": "Hello!"}],
  "stream": true
}
```

Timeouts: 300s request, 600s resource (allows for tool execution).

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

---

## Known Limitations (v0.1)

- **No conversation persistence** — messages are lost on restart. Hermes remembers context server-side (MEMORY.md, sessions), but the UI starts blank.
- **No new chat button** — must restart the app to clear conversation.
- **Hardcoded localhost:8642** — no UI to change the Hermes URL.
- **No onboarding** — assumes Hermes is already running.
- **Tool detection is heuristic** — some tool output may leak into the response or vice versa. The SSEParser uses pattern matching (shell operators, file paths, command prefixes) which can miss edge cases.
- **arm64 only** — builds for Apple Silicon. Intel Macs need a separate build.
- **Unsigned** — triggers Gatekeeper warning. Right-click > Open to bypass.

## v1 Roadmap

See the [evaluation plan](.claude/plans/zazzy-popping-nest.md) for the full v1 roadmap including:
- Configurable URL + onboarding screen
- Connection status indicator
- Conversation persistence
- New Chat button
- Settings panel
- CLI wrapper for `hermes status`
- DMG packaging
- Resize (deferred to v1.1)
- Hermes Responses API integration (v1.1)

---

## Tech Stack

- **Swift 5.9 / SwiftUI** — UI
- **AppKit** — NSPanel, NSEvent, NSWorkspace, NSStatusItem
- **Carbon.HIToolbox** — Global hotkeys (RegisterEventHotKey)
- **AVFoundation** — Audio recording
- **Speech** — On-device transcription (SFSpeechRecognizer)
- **PDFKit** — PDF text extraction
- **URLSession.bytes** — Async SSE streaming
- **Zero external dependencies**

---

## License

MIT
