# NotchNotch

A native macOS app that lives in your MacBook's notch, providing instant access to your [Hermes](https://github.com/NousResearch/hermes-agent) AI agent without switching windows.

**No terminal required.** notchnotch includes a guided onboarding that installs the Hermes agent, connects your AI provider, picks a model, and optionally sets up Telegram — all from a visual interface. Your non-technical friends can use it too.

Built with Swift & SwiftUI. Inspired by [BoringNotch](https://github.com/TheBoredTeam/boring.notch) and [NotchNook](https://lo.cafe/notchnook).

![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![Version](https://img.shields.io/badge/version-0.8.0-violet)

---

## Install

### Download DMG

Download from [GitHub Releases](https://github.com/KikinaStudio/Notchnotch/releases). Drag to Applications.

**Gatekeeper will block it** (unsigned app). Run this once:

```bash
xattr -cr /Applications/BoaNotch.app
```

Then open normally. Don't look for "Allow Anyway" in System Settings — it's buried and unreliable. `xattr -cr` is the canonical bypass.

### Homebrew

```bash
brew install --cask KikinaStudio/tap/boanotch --no-quarantine
```

The `--no-quarantine` flag bypasses Gatekeeper automatically. No `xattr` needed.

> **Setup:** requires a personal tap repo. See [Publishing a release](#publishing-a-release).

### Build from source

```bash
git clone https://github.com/KikinaStudio/Notchnotch.git
cd BoaNotch
bash scripts/run.sh
```

No Xcode required — only Command Line Tools (`xcode-select --install`).

### First launch

On first launch (when Hermes is not installed), notchnotch walks you through setup:

1. **Welcome** — the notchnotch logo
2. **Privacy** — explains what stays local, what goes to your AI provider
3. **Connect** — sign in to OpenRouter (free, one click) or paste an API key (OpenAI, Anthropic)
4. **Install** — Hermes agent installs automatically in the background
5. **Model** — pick a free or paid AI model
6. **Telegram** — optionally connect a Telegram bot for mobile access
7. **Ready** — start chatting

If Hermes is already installed (`~/.hermes/config.yaml` exists), the onboarding is skipped entirely.

---

## Features

### Chat in the notch
Hover or click the notch to expand a chat panel with spring animations. Messages stream in real-time via SSE from the Hermes agent API.

### Telegram continuity
notchnotch auto-detects your Telegram DM session with the Hermes bot from `~/.hermes/state.db` on launch. The same `session_id` (your Telegram `chat_id`) is sent as `X-Hermes-Session-Id` on every API request — giving you full continuity between Telegram and notchnotch. No manual linking, no picker. One session, two interfaces.

### Collapsible thinking & tool calls
Hermes's internal reasoning (`<think>` blocks) and tool execution are hidden behind collapsible toggles. Only the clean response is shown. The SSE parser uses a two-tier heuristic with post-processing fallback (see [SSE Token Routing](#sse-token-routing)).

### Search in conversation
Magnifying glass icon (top-left) opens full-text search across all messages:
- Match counter (`N/M`), Previous/Next navigation
- Auto-scroll to matched message, purple highlight on matching text

### Settings
Gear icon (top-right) opens settings: max iterations (Quick/Normal/Deep), streaming toggle, terminal backend (local/docker/ssh), and Telegram session status.

### Voice memos
`Ctrl+Shift+R` anywhere to record. KITT-style purple scanner line under the closed notch. Press again or `Enter` to stop — transcribed locally (macOS Speech, French locale) and sent as text. Mic button in the input bar does the same.

### Drag & drop files
Drag any file onto the notch. Supports images (vision analysis), PDFs, code (35+ languages), text, CSV, JSON, YAML, RTF. Violet overlay on drag hover.

### Onboarding
First launch walks new users through Hermes installation, AI provider setup, model selection, and optional Telegram connection — no terminal needed.

### Welcome screen
Before the first message, notchnotch shows the logo with "notch notch ! Who's there ? Your futchure." — disappears after first input.

### Smart file paths
File paths in responses render as clickable cards with SF Symbol icons. Click to reveal in Finder.

### Streaming indicator
- **Closed**: notch extends slightly with a braille spinner (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`)
- **Open**: send button becomes a spinner (click to cancel)

### Toast notifications
When closed, a black toast slides out below the notch with the response preview. Tap to expand.

### Code blocks & markdown
Fenced code blocks with language labels, bold, italic, inline code, and links via `AttributedString`.

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
    |     Left: search button
    |     Right: settings button
    |
    +-- Content (when open)
    |     Onboarding flow (7 screens, first launch only)
    |     Welcome screen (logo + tagline, before first message)
    |     ChatView: messages + input bar
    |       MessageBubble: thinking/tool toggles, code blocks, file cards
    |       Input bar: [+file] [mic] [...more] [send/spinner]
    |     -- OR --
    |     SettingsView: agent config + session status
    |
    +-- Overlays
    |     KITT scanner (recording), Braille spinner (thinking)
    |     Drop overlay (file drag), Toast (response preview)
    |
    +-- Services
          HermesClient -> localhost:8642 (SSE streaming)
          SessionStore -> auto-detect Telegram session from state.db
          SSEParser, SpeechTranscriber, DocumentExtractor, AudioRecorder
```

## Project Structure

```
BoaNotch/
+-- Package.swift                        # SwiftPM, macOS 14+
+-- scripts/
|   +-- run.sh                           # Build + bundle + codesign + launch
|   +-- release.sh                       # Universal binary + DMG + ad-hoc sign
+-- homebrew/
|   +-- boanotch.rb                      # Homebrew Cask formula template
+-- BoaNotch/
    +-- BoaNotchApp.swift                # @main entry point
    +-- AppDelegate.swift                # Lifecycle, Carbon hotkeys, menu bar, voice
    +-- AppConstants.swift               # Colors, file icons, cursor modifier
    +-- Info.plist                        # LSUIElement, ATS, mic/speech permissions
    +-- BoaNotch.entitlements            # network.client
    +-- Resources/
    |   +-- AppIcon.icns                 # App icon (all sizes)
    |   +-- menubar-icon.png/@2x.png     # Menu bar template icon
    |   +-- logo-white.png               # Welcome screen logo (white)
    |   +-- icon.svg, logo.svg           # Source SVGs
    |
    +-- Models/
    |   +-- ChatMessage.swift            # role, content, thinking, toolCalls
    |   +-- Attachment.swift             # fileName, fileType, textContent, fileURL
    |
    +-- ViewModels/
    |   +-- NotchViewModel.swift         # State machine (closed/open/toast)
    |   +-- ChatViewModel.swift          # Messages, streaming, send/cancel, voice
    |   +-- SearchViewModel.swift        # Search matches, navigation
    |
    +-- Views/
    |   +-- NotchView.swift              # Root: shape + top bar + overlays
    |   +-- ChatView.swift               # Scroll + welcome screen + input bar
    |   +-- MessageBubble.swift          # Thinking/tool toggles, code, file cards
    |   +-- SearchBarView.swift          # Search input + match counter
    |   +-- SettingsView.swift           # Agent config + session status
    |   +-- ExpandedBarView.swift        # Profile, model, reasoning, incognito
    |   +-- NotchShape.swift, ToastView.swift, DropOverlay.swift
    |
    +-- Window/
    |   +-- NotchPanel.swift             # Borderless NSPanel subclass
    |   +-- NotchWindowController.swift  # Positioning, drag monitor, screen tracking
    |
    +-- Onboarding/
    |   +-- OnboardingViewModel.swift    # Step state, OAuth, install, config writes
    |   +-- OnboardingContainerView.swift # Step router + nav dots
    |   +-- WelcomeStep.swift            # Screen 1: logo + tagline
    |   +-- PrivacyStep.swift            # Screen 2: privacy explainer
    |   +-- ConnectProviderStep.swift     # Screen 3: OpenRouter OAuth + API key paste
    |   +-- InstallHermesStep.swift       # Screen 4: background installer
    |   +-- ChooseModelStep.swift         # Screen 5: model picker
    |   +-- TelegramStep.swift            # Screen 6: optional Telegram bot
    |   +-- ReadyStep.swift              # Screen 7: done
    |   +-- OAuthService.swift           # PKCE + OpenRouter token exchange
    |   +-- ShellRunner.swift            # Async Process() wrapper
    |
    +-- Services/
        +-- HermesClient.swift           # OpenAI-compatible SSE client
        +-- SSEParser.swift              # Two-tier token routing
        +-- SessionStore.swift           # Auto-detect Telegram session from state.db
        +-- HermesConfig.swift           # config.yaml watcher
        +-- SpeechTranscriber.swift      # SFSpeechRecognizer, French locale
        +-- DocumentExtractor.swift      # 40+ file types, 50K char limit
        +-- AudioRecorder.swift          # AVAudioRecorder, M4A
```

---

## Requirements

- **macOS 14** (Sonoma) or later
- **MacBook with notch** (works on non-notch Macs too, positioned at top-center)

Hermes agent is installed automatically on first launch via the onboarding flow. No terminal required.

If you already have Hermes installed, notchnotch detects it and skips the onboarding.

### Permissions

On first use, macOS will prompt for:
- **Microphone** — for voice memos (only when you tap the mic button)
- **Speech Recognition** — for on-device transcription
- **Accessibility** (manual) — for global Ctrl+Shift+R hotkey. Add the app in System Settings > Privacy & Security > Accessibility.

---

## Usage

### Chat
- **Hover** the notch (300ms delay) or **click** to expand
- Type and press **Return** to send
- Braille spinner replaces send button while streaming (click to cancel)
- Move cursor away to collapse (600ms delay)

### Search
- Click the **magnifying glass** icon (top-left)
- Type to search — matches highlighted in purple
- **Chevron arrows** or **Enter** to jump between matches
- Counter shows position (`3/12`)

### Settings
- Click the **gear** icon (top-right)
- Agent: max iterations, streaming toggle
- Execution: terminal backend (local/docker/ssh)
- Session: shows auto-linked Telegram session status

### Voice Memos
- **Ctrl+Shift+R** — start recording (KITT scanner appears)
- **Ctrl+Shift+R** or **Enter** — stop, transcribe, send
- **Mic button** in input bar — same flow
- Uses Carbon `RegisterEventHotKey` — works from any app, no error beep

### Attach Files
- **Drag & drop** onto the notch, or click **+** in the input bar
- Images copied to `~/.hermes/cache/images/` for vision analysis
- 50K character extraction limit

### Quit
Menu bar icon > Quit notchnotch, or Cmd+Q.

---

## Distribution

### Building a release

```bash
bash scripts/release.sh
```

This script:
1. Builds a release binary (universal `arm64+x86_64` if Xcode is installed, `arm64` only with Command Line Tools)
2. Creates a `.app` bundle with Info.plist, resources, and icons
3. Signs with ad-hoc certificate (`codesign --force --deep --sign -`) — avoids runtime crashes on macOS 14+ even without an Apple Developer account
4. Creates a DMG via `create-dmg` (install with `brew install create-dmg`) or `hdiutil` fallback

Output: `.build/BoaNotch-v0.7.0.dmg`

### Publishing a release

```bash
# 1. Build the DMG
bash scripts/release.sh

# 2. Create a GitHub Release
gh release create v0.7.0 .build/BoaNotch-v0.7.0.dmg \
    --title "BoaNotch v0.7.0" \
    --notes "Telegram auto-link, custom icon, distribution pipeline"

# 3. Update Homebrew formula
shasum -a 256 .build/BoaNotch-v0.7.0.dmg
# Copy the hash into homebrew/boanotch.rb sha256 field
```

### Homebrew tap setup

To enable `brew install --cask KikinaStudio/tap/boanotch`:

1. Create repo `KikinaStudio/homebrew-tap` on GitHub
2. Copy `homebrew/boanotch.rb` to `Casks/boanotch.rb` in that repo
3. Fill in the `sha256` from `shasum -a 256` of the DMG
4. Users install with: `brew install --cask KikinaStudio/tap/boanotch --no-quarantine`

The `--no-quarantine` flag bypasses Gatekeeper automatically — no `xattr` needed.

### Signing notes

The app is currently **ad-hoc signed** (`codesign --sign -`). This:
- Avoids runtime crashes from macOS 14+ code signing enforcement
- Does NOT satisfy Gatekeeper (users still need `xattr -cr` or `--no-quarantine`)
- If you later get an Apple Developer account ($99/year), just change `--sign -` to `--sign "Developer ID Application: Your Name"` — no other changes needed

---

## How It Works

### SSE Token Routing

The `SSEParser` classifies each streaming token into three channels:

1. **Thinking** — `<think>...</think>` tags
2. **Tool calls** — two tiers:
   - **Strong markers**: emojis (`💻🔧⚙️🔎📚`), XML tags
   - **Weak heuristics**: shell operators, command prefixes, CLI flags
3. **Response** — clean text (French pronouns, uppercase starts, numbered lists)

`sawCleanResponse` flag prevents re-entry to tool mode from natural text. Post-processing fallback (`extractCleanResponse`) catches misclassified content after streaming.

### Session Auto-Link

On launch, `SessionStore` reads `~/.hermes/state.db`:

```sql
SELECT id FROM sessions WHERE source = 'telegram'
ORDER BY started_at DESC LIMIT 1
```

This `id` is the Telegram `chat_id` of your DM with the Hermes bot. It's sent as `X-Hermes-Session-Id` on every request, giving full context continuity between Telegram and BoaNotch. Persisted in `UserDefaults` across restarts.

### Window System

Custom `NSPanel` — borderless, transparent, non-activating, level `mainMenu + 3`. Fixed panel size (620x380pt). Content animates inside via `NotchShape` clipping. Panel joins all spaces and only becomes key when open.

### Notch Shape

Custom `Shape` with `animatableData` for smooth corner radius transitions. Quad curves approximate the hardware notch silhouette. Closed: top 6pt, bottom 10pt. Open: top 14pt, bottom 18pt.

---

## API

| Endpoint | Method | Headers | Description |
|----------|--------|---------|-------------|
| `localhost:8642/health` | GET | — | Health check |
| `localhost:8642/v1/chat/completions` | POST | `Content-Type: application/json`, `X-Hermes-Session-Id: <id>` | Chat completions (SSE) |

Request:
```json
{
  "model": "hermes-agent",
  "messages": [{"role": "user", "content": "Hello!"}],
  "stream": true
}
```

Timeouts: 300s request, 600s resource.

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
| `hermesSessionId` | UserDefaults | Auto-linked Telegram session ID |
| `onboardingCompleted` | UserDefaults | Skips onboarding on future launches |
| `onboardingStep` | UserDefaults | Resume point if app quits mid-onboarding |
| `selectedProvider` | UserDefaults | AI provider chosen during onboarding |
| `CFBundleURLTypes` | Info.plist | `boanotch://` URL scheme for OAuth callback |

---

## Known Limitations

- **No conversation persistence** — messages are lost on restart. Hermes remembers context server-side via sessions and memory, but the UI starts blank.
- **Fixed notch size** — 580x340pt. Dynamic height and drag-to-resize are planned.
- **Hardcoded localhost:8642** — no UI to change the Hermes URL.
- **No conversation history** — new conversation button is hidden until a history list is implemented.
- **Tool detection is heuristic** — some tool output may leak into the response or vice versa. Post-processing fallback catches most cases.
- **Unsigned** — triggers Gatekeeper. Use `xattr -cr` or `brew install --no-quarantine`.

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

---

## Roadmap

- [ ] Dynamic notch height (auto-grow with content, drag handle)
- [ ] Conversation history list + new conversation button
- [ ] Auto-update via Sparkle
- [ ] Flanking search/settings buttons beside physical notch
- [ ] Universal binary (requires Xcode)
- [ ] Apple Developer signing + notarization

---

## License

MIT
