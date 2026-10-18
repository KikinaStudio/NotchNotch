# NotchNotch — Claude Code Project Guide

## What is this

A native macOS SwiftUI app that lives in the MacBook notch, giving instant access to a local [Hermes](https://github.com/NousResearch/hermes-agent) AI agent (on-device, with access to the user's files, tools and system). Swift 5.9 / SwiftUI, macOS 14+, built with Command Line Tools only (no Xcode). Users are both technical and non-technical — UI copy is French.

Detailed per-file / per-feature notes live in [docs/architecture.md](docs/architecture.md). Read the relevant part on demand; the code is the source of truth.

## Hermes — verify before assuming

NotchNotch is a thin client over Hermes, a full agent platform (sessions, memory, skills, cron, messaging platforms, tools, checkpoints, compression, personas, memory providers). Don't underestimate it, and don't trust names you haven't checked.

- Check latest releases for new features: `https://github.com/NousResearch/hermes-agent/releases`. Local state: `~/.hermes/config.yaml`, `sqlite3 ~/.hermes/state.db ".schema"`.
- **Before trusting any field, tool, or API name cited in a task prompt, grep the local install:** `grep -r "<name>" ~/.hermes/hermes-agent --include="*.py"`. Prompts hallucinate fields even when citing real PRs (2026-04-24: a fictional `wake_agent` cron field sourced to real PRs).
- **Confirm the installed version against two sources** before relying on a version-gated feature: `grep -m1 -iE '^version' ~/.hermes/hermes-agent/pyproject.toml` and `grep -E '__version__' ~/.hermes/hermes-agent/hermes_cli/__init__.py`; cross-check `gh api repos/NousResearch/hermes-agent/releases/latest --jq .tag_name`. `/health` returns `"version"` since v0.21.6 (older gateways omit it): use it as a third source, not the only one. On a `main` checkout `pyproject.toml` says `0.0.0`: use `/health` and `git -C ~/.hermes/hermes-agent describe --tags` instead, and check a feature with `git merge-base --is-ancestor <commit> v0.21.6`.
- Before trusting a REST path found by grepping Hermes, curl it: `hermes_cli/web_server.py` defines `/api/cron/jobs/...` but is NOT served by `hermes gateway run`; the real one is `/api/jobs/...` in `gateway/platforms/api_server.py`.

## Build & Run

```bash
bash scripts/run.sh       # Build + bundle + codesign + launch
bash scripts/release.sh   # Universal binary + DMG
bash scripts/lint-design.sh   # Run before committing UI changes
```

- **Version source of truth**: `BoaNotch/Info.plist` (`CFBundleShortVersionString`). Don't hardcode it anywhere else.
- SPM target is still `BoaNotch` (renamed `notchnotch` only at the app bundle level).
- `BoaNotch/Resources/google_oauth_config.json` is gitignored — copy from `.example` and fill a Google Cloud "Desktop app" OAuth client before building. `run.sh`/`release.sh` copy it into `Contents/Resources/`.
- Ad-hoc signed: Gatekeeper needs `xattr -cr` or right-click > Open.

### Hermes locally

Hermes owns its LaunchAgent (`~/Library/LaunchAgents/ai.hermes.gateway.plist`, label `ai.hermes.gateway`) since v0.21. NotchNotch never writes it.

```bash
hermes gateway restart          # graceful drain + relaunch (prefer over launchctl kickstart)
hermes gateway status
hermes gateway run --replace    # foreground; stop the service first or KeepAlive fights back
```

- `~/.local/bin/hermes` is a wrapper script exec'ing `~/.hermes/hermes-agent/.hermes/bin/hermes` (bundled Python). The legacy `~/.hermes/hermes-agent/venv/bin/python3` still exists and is used by `SkillsHubClient`.
- The API server starts via `hermes gateway run` (there is no `hermes serve`), port 8642.
- v0.21.6+ only opens :8642 when `API_SERVER_ENABLED=true` AND `API_SERVER_KEY` (16+ chars, not a placeholder) are in `~/.hermes/.env`. NotchNotch writes both when absent (see exceptions).
- `curl http://localhost:8642/health` needs no key. Everything else needs `-H "Authorization: Bearer $(grep '^API_SERVER_KEY=' ~/.hermes/.env | cut -d= -f2-)"`, else 401. Never log the key.
- Logs: `~/.hermes/logs/gateway.log` / `gateway.error.log`.

## Core architecture (one-liners — details in docs/architecture.md)

- `HermesClient` — two chat transports, picked per turn by `streamResponse`: `POST /v1/chat/completions` (stream) when `/health` reports `version` (v0.21.6+), else `POST /v1/responses` (SSE, JSON fallback for pre-v0.11 servers). Both emit the same `StreamEvent`s. One `notchnotch-<uuid>` key per conversation. On /v1/responses it is sent as `conversation`, `X-Hermes-Session-Id` (row id on pre-v0.21.6 gateways) and `X-Hermes-Session-Key` (v0.21.6+ store it in `sessions.session_key`; only with the Bearer, else 403). On /v1/chat/completions history follows `X-Hermes-Session-Id` = the latest state.db row whose `session_key` is the key (`SessionStore.latestRowId`), else the key itself; `X-Hermes-Session-Key` still rides along; only the new user message (+ routine system context) is sent. Never share a key across conversations: Hermes would reuse the previous row. Resuming = restoring the key. Retries only on dead-agent disconnects (cannotConnect / connectionLost / EOF before the final event), never on 5xx/4xx/timeout. Reads `API_SERVER_KEY` fresh from `.env` on every request. The chat model picked in the notch bar (`chatModelProvider` + `chatModelID`) goes out as `model` + `provider` on both chat transports, else `hermes-agent` (gateway default); `sendCompletion` and titles always use the default.
- `ThinkTagSplitter` / `postProcessResult` / `scrubSecrets` (in `HermesClient.swift`) — client-side cleanup of `<think>` blocks, tool-arg previews and secrets. Keep it client-side even though Hermes 0.13+ redacts server-side: it's the fallback for stale gateways.
- `ChatViewModel` — send/stream/retry/edit, brain saves, memory edit/delete, routine actions.
- `SlashPalette` / `SlashPaletteView` — the composer's live `/` palette (H5b): NotchNotch's commands (`HermesSlashCommand.runnable`, French descriptions), then installed skills (`BrainViewModel.skills`, read from disk), then a greyed Hermes-only command only once its exact name is typed. Keys via a local `keyDown` monitor in `ChatView`. A message starting with a skill slug gets a system line asking Hermes to `skill_view` it: Hermes's API takes `/skill …` as plain text.
- `CronStore` — watches `~/.hermes/cron/jobs.json` (`{"jobs": [...]}` wrapper); reattaches on atomic rename; diffs `last_run_at`: an `ok` run surfaces its output as a notch toast (any `deliver`, filters `[SILENT]`); the first failure of a series (`failure_streak == 1`, read in jobs.json, no cron REST) gets an error toast whose tap opens Missions (H7).
- `BrainViewModel` / `BrainView` — Memory · Tools · Missions tabs (internal identifiers stay `brain` / `tasks`; rawValue = user-visible label).
- `HermesConfig` — reads `config.yaml` via Yams, writes via line-level regex (preserves comments) with `Data.write(options: .atomic)` — NOT tmp+moveItem. `writeRawEnv` / `readRawEnv` for `.env`. `modelOptions` = connected providers from `GET /api/model/options?include_unconfigured=0` (the notch bar's per-chat picker, like Hermes Desktop's composer); empty (old gateway) → the bar falls back to `availableModels` + `switchModel` (global default). The default model is picked in Settings (Hermes's list for the configured provider, else `availableModels`); a provider click writes nothing, `switchModel` saves provider + base_url + model together and clears the chat pick (last pick wins). One instance: `AppDelegate.hermesConfig` is `HermesConfig.shared`.
- `HermesGatewayLauncher`, `ComputerUseService`, `GoogleConnectionState` — `@MainActor` singletons.
- `NotchWindowController` — owns the `NotchPanel` and sizing; invariant `openSize = dimensions - 2 × shadowPadding`.
- `DesignSystem.swift` — all visual tokens (`DS.*`). Shared primitives in `BoaNotch/Views/Components/` (`PrimaryButtonStyle`, `SegmentedButtonStyle`, `PanelSection`, `CardCompact`, `CardProminent`, `ListRow`, `Hairline`, `notchPanelInsets`).

## Important gotchas

- **Tap inside the open notch never closes it.** `NotchViewModel.handleClick()` only opens. Don't add `else { close() }` back.
- **An open menu blocks the hover-out close.** `NotchViewModel.openMenuCount` follows `NSMenu.didBegin/EndTrackingNotification`: the bar's model submenus hang below the panel, and the cursor following them used to close the notch under the open menu.
- **`Bundle.module` is forbidden** — use `Bundle.main.resourceURL?.appendingPathComponent(...)`. SPM's `Bundle.module` looks at the app root (breaks codesign) or `fatalError`s on first access (shipped as a crash-on-launch in v1.0.1). Never reintroduce it, even behind a fallback.
- **rpath**: `swift build` doesn't add `@executable_path/../Frameworks`. `run.sh`/`release.sh` run `install_name_tool -add_rpath` after copying Sparkle and before codesign (v1.2.1 crashed on launch without it). Don't remove it.
- **`@Published` fires in willSet**: a sink on `$prop` reads the OLD value. Add `.receive(on: DispatchQueue.main)` when you need the post-change state (see `NotchWindowController.sizeCancellable`).
- **SSE `onEvent` runs off-main** — hop to `Task { @MainActor in ... }` before touching UI state.
- **Tool-call `.added` and `.done` carry identical payloads** — react on `.added` only. See `sse-probe-notes.md`.
- **Hermes v0.11.0 is the SSE floor** — keep the JSON fallback; older Hermes in the wild must keep working.
- **Don't "fix" Hermes to stop emitting `<think>`** — models keep writing them; cleanup stays client-side.
- **Server conversation history includes tool calls/results** — don't strip them from the response store.
- **Hermes v0.21.6+ titles every session itself**, `/v1/responses` included (`maybe_auto_title` in `agent/turn_context.py`, `state.db` `title_source = llm`). Older gateways don't title `/v1/responses` sessions, so NotchNotch still generates its own (`generateTitle` → `TitleStore`); on v0.21.6+ it's a duplicate call kept for compatibility.
- **Provider errors (402, offline) arrive as `response.completed`** on `/v1/responses`, with the error as assistant text and usage 0. `response.failed` only means "no final text" or a crash. Never detect failures by matching Hermes's text (translated, changes between versions). On `/v1/chat/completions` the real status exists: final chunk `finish_reason: "error"` → `HermesError.agentFailed(error.message)` (generic French message when `error` is missing, e.g. a crash). `finish_reason: "length"` is a normal (truncated) completion.
- **`hermes.status` SSE event (v0.21.6+, both transports)** — `{kind, text}`, already redacted, mixed EN/FR. Shown verbatim as the bubble's live status line (`ChatMessage.liveStatus`), no toast; treat unknown kinds like the others.
- **Hermes slash commands never reach the model** — no HTTP route runs them (checked up to v0.22.2): sent as text, the model fakes `/new` and turned `/loop` into a real cron. `HermesSlashCommand.registry` copies `COMMAND_REGISTRY` names + aliases and matches the first word exactly; a near miss (one edit, or a prefix: `/models`, `/sess`) gets a suggestion instead. Paths and skills still go out. Refresh it when Hermes adds commands. `/goal` `/subgoal` point to Telegram / Hermes Desktop and `/loop` `/heartbeat` to Missions (H6): the goal judge and the loop/heartbeat ticks only follow a turn of the RPC backend (`hermes serve`, `/api/ws`) or of a messaging platform, never an HTTP one, so running them needs the whole chat on the RPC (re-evaluate at v0.23.0, H16).
- **DropDelegate, not `.onDrop` closure** — the split drop zone needs `DropInfo.location`.
- **NWListener**: in `ClipperListener`, don't `defer { connection.cancel() }` — cancel in the send completion handler.
- **`NotchState` is switched exhaustively** in `NotchWindowController` — adding a case breaks the build there.
- **Hermes has no `config_set` tool** — via chat, ask Hermes to run `hermes config set <key> <value>` with its `terminal` tool.
- **`cronjob action=run` doesn't execute immediately** — it only advances `next_run_at`. To test a cron prompt, send it directly via `/v1/responses`.
- **Free-tier models skip skill invocation** — prompts must name the skill explicitly (`Utilise le skill llm-wiki pour ...`).
- **Memory edit/delete is fire-and-forget** — HTTP 200 means "received", not "rewritten". Never claim more than the optimistic toast.
- **MiniMax uses `https://api.minimax.io/anthropic`, not `/v1`.** A `MINIMAX_BASE_URL=.../v1` line in `~/.hermes/.env` (from Hermes's `.env.example`) overrides `config.yaml` — affected installs must remove it.
- **Logging from the GUI bundle needs `os_log`** — `print()` goes nowhere when launched via `open`. Use `%{public}@` for readable strings. Query: `PRED='process == "notchnotch"'; /usr/bin/log show --info --debug --last 2m --predicate "$PRED" | grep "(notchnotch)"`.
- **`@MainActor` singletons must be touched from a main-actor context** (e.g. inside `applicationDidFinishLaunching`), not from a stored property on the non-isolated `AppDelegate`.
- **TCC prompts render behind the `.mainMenu + 3` panel** — wrap permission requests in `NotchPanel.withLoweredLevel { ... }`. Mic: request via `AudioRecorder.startRecordingWithPermission()` before recording.
- **`hermes computer-use install` exits 0 even on failure** — `ComputerUseService.install()` asks Hermes again afterwards (`installed` of `permissions status --json`). Keep that probe.
- **Never look for a Hermes tool with `which`** — an app opened from the Finder gets launchd's minimal PATH (`/usr/bin:/bin:/usr/sbin:/sbin`), and pm's tools live in `~/.hermes/tools/`, never on PATH (cua-driver included). Call `~/.local/bin/hermes` by its full path and ask Hermes (`permissions status --json` → `installed`).
- **`/usr/bin/git` is a stub until Apple's Command Line Tools are installed** — `which git` says yes, running it opens macOS's install dialog. The onboarding checks `xcode-select -p` (no window) then `git --version`.
- **`ShellRunner` drains the pipe before `waitUntilExit`** — the Hermes installer prints megabytes (uv, pm); reading after the wait deadlocks once the 64 KB pipe buffer is full.
- **Skills Hub source quirk** — browse items use `source == "skills.sh"` (dot) while install identifiers use `skills-sh/` (dash). Match what the items emit.
- **Chrome extension dev path** — Clipper loads from `~/NotchNotch Extension/`, not the repo clone. Copy changes there and reload.

## Design rules (NOT Material Design)

The panel is near-black to camouflage the hardware notch. Native macOS editorial feel: confident typography, dividers, accent sparingly. The user explicitly rejected the MD3 pill+card look.

- **Use `DS.*` tokens for every value** (`DS.Text`, `DS.Icon`, `DS.Surface`, `DS.Status`, `DS.Radius`, `DS.Spacing`, `DS.Padding`, `DS.Layout`, `DS.Stroke`). No `.system(size:)`, `.white.opacity()`, native font aliases (`.callout`, `.caption`, `.headline`…), literal radii or ad-hoc paddings in views. If a value is missing, add a token to `DesignSystem.swift` first. Use the shared primitives in `Views/Components/` instead of re-implementing buttons, segmented controls or section containers.
- **Lists (Memory, Skills, History, Routines)**: no filled card backgrounds at rest. Hairline dividers between rows, ~32pt min height (`DS.Layout.rowMinHeight`). Hover may use `nnGlass(in:)` on macOS 26+ or a very subtle tint.
- **Section headers**: uppercase monospaced (`DS.Text.sectionHead`), `DS.Surface.headerLow`, tracking 1.5. Never accent-tinted.
- **Tab intros**: one French line, `DS.Text.caption` + `AppColors.accent`. Not italic (user rejected italics).
- **Accent** (`AppColors.accent`, light blue): signature moments only (§ mark, active-state dots, chat toast, primary CTA). Never on headings.
- **Selected button on accent fill → text `.black.opacity(0.85)`**, never white (illegible).
- **Pill vs button**: `Capsule()` only for tag-like state chips (routine context tag, ExpandedBar chips, floating toasts). Buttons, segments and CTAs use `RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)`. The send button is the only Capsule exception.
- **Icon sizing**: top bar icons are 13pt medium (`DS.Icon.topBar`); bottom input bar icons 14pt medium (`DS.Icon.secondary`); send button 18pt. `xmark.triangle.circle.square` (Tools) gets `sizeBoost: 2` for visual balance.
- **Liquid Glass**: always via `nnGlass()` / `nnGlass(in:)` / `NNGlassContainer` (fall back below macOS 26). Glass is for floating UI over the desktop (toasts, recording capsule) and the open panel background (`notchPanelBackground`). Never on content rows or cards inside the panel.
- **Section panels have no inner rectangle**: content sits directly on the panel background with `notchPanelInsets(variant:)`. The "in a section" signal is `notchPanelBackground(inSection: true)`. Don't reintroduce a content-area fill.
- **Top bar**: an open panel shows its title in the left slot; the right burger owns the close X. Panel content has no internal title header.
- **`FadingScrollView`** instead of `ScrollView` in panels (bottom fade only).
- **Settings**: actions go through `settingsActionButton(label:action:)`; labels in French. Advanced sections stay under the collapsed "Avancé" group.
- **Panel size**: don't enlarge the notch panel to make a UI fit — redesign instead (user rejected this, 2026-04-24).
- **Toasts**: tinted per `ToastKind` (info lavender, chat accent, success green, error coral, cron amber). Pixel-art SVGs from halfmage/pixelarticons in `Resources/PixelIcons/`.
- Conditional `foregroundStyle` needs `AnyShapeStyle` on both branches (`DS.Surface.*` already are).

## What NotchNotch never does (except the documented exceptions below)

- Write `~/.hermes/config.yaml` or `~/.hermes/.env` — default path is a chat message asking Hermes to change it.
- Call Hermes's skill manager, cron API or memory tool directly — default path is natural language via `sendCompletion`.
- Edit anything under `~/.hermes/brain/wiki/` or `~/.hermes/memories/` (Hermes owns them). Memory edits are chat prompts to Hermes's `memory` tool.
- Edit `~/.hermes/brain/wiki/SCHEMA.md` (Hermes territory, co-evolved with the user; reading is fine).
- Write any launchd plist.
- Connect a curated capability via chat — `ConnectAction` deliberately has no `.viaChat` case. Use structured UI (OAuth, inline API-key form, external doc link).

**Prefer structured UI + direct REST / file write** when Hermes exposes a deterministic endpoint and the data has a fixed shape (user's choice, 2026-04-26 — chat-driven edits hid *what* was editable). Every non-chat path must be listed below. Don't silently add a new exception — add it here in the same diff. The usual justification: chat adds LLM latency, weak free-tier models misroute it, and the CLI forces the user out of NotchNotch.

### Documented exceptions

- **`~/.hermes/google_token.json`** — `GoogleOAuthService` writes it after the in-process Desktop OAuth flow (loopback + PKCE; chat can't catch a browser redirect). The format must byte-match `google.oauth2.credentials.Credentials.to_json()` (9 keys, `expiry` as `YYYY-MM-DDTHH:MM:SS.000000Z`), mode 0600. Its consumer is the `google-workspace` skill.
- **Cron pause / resume / edit via REST** — `HermesClient.pauseCronJob` / `resumeCronJob` (`POST /api/jobs/{id}/pause|resume`) and `updateCronJob` (`PATCH /api/jobs/{id}`, whitelist `_UPDATE_ALLOWED_FIELDS` in `api_server.py`). Edit patches are minimal: only changed fields, so unknown `deliver` values survive. Schedules that `parseCron` can't round-trip stay read-only in the form. **Create and remove still go through chat.**
- **Memory provider** — `HermesMemoryConfig.switchTo` writes `memory.provider`; `MemoryProviderSection` writes plugin env vars via `writeRawEnv`. `hermes memory setup` is an interactive TUI with no non-interactive flags. Pip deps for cloud providers are left to the user (the UI shows a hint). Providers are discovered like Hermes does (`_iter_provider_dirs`), on disk only, from two folders: bundled `~/.hermes/hermes-agent/plugins/memory/<id>/` and catalog installs in `~/.hermes/plugins/<id>/` (memory providers only, not platform plugins; bundled wins on a name clash). Project plugins and pip entry points aren't listed. The configured provider stays shown even when it's missing on disk. Never write other `memory.*` keys.
- **Skills Hub (browse / inspect / install)** — `SkillsHubClient` runs inline Python against `hermes_cli.skills_hub` (`browse_skills`, `inspect_skill`) with the venv Python, and runs `hermes skills install <id> --yes` (`--yes` prevents a stdin hang). A 0 exit can still be "Installation blocked": check stdout. It's tightly coupled to the `~/.hermes/hermes-agent` layout, on purpose (fails loudly). Only `official` and `skills.sh` sources are exposed.
- **`hermes computer-use install` / `permissions status --json` / `permissions grant` + macOS privacy-panel deeplinks** — Settings › Contrôle du Mac (and the Brain detail view) only: no onboarding step since H14. `ComputerUseService.install()` runs `~/.local/bin/hermes computer-use install` (only from an explicit button), then asks Hermes whether it sees cua-driver: `installed` of the status JSON (pm's binary in `~/.hermes/tools/`, never on PATH), `which cua-driver` only when there's no JSON (Hermes < v0.21.6). `refreshState()` runs `hermes computer-use permissions status --json` (read-only, off the main thread, on events only: launch, install, "C'est bon", opening the detail view or Settings) for the real TCC state of cua-driver (`com.trycua.driver`); read `accessibility` / `screen_recording`, never `ready` (false for "unknown" too). `null` grants (no CuaDriver daemon running), no JSON (Hermes < v0.21.6) or no binary keep the old behaviour: the user's "C'est bon" is a UI-side act of faith (`computerUsePermissionsConfirmed`). `requestPermissionsGrant()` runs `hermes computer-use permissions grant` only from the "Autoriser" button (shown when the status JSON says `can_grant`), inside `NotchPanel.withLoweredLevel`: cua-driver launches CuaDriver.app so macOS asks in CuaDriver's name, waits up to ~3 min for the answers, exit 0 = granted and verified. TCC panes are still opened via `x-apple.systempreferences:` deeplinks as the fallback. NotchNotch never tries to bypass consent.
- **`hermes tools enable computer_use --platform api_server`** — Hermes's default api_server toolset leaves `computer_use` out (`hermes-api-server` = `_core_without(…, "computer_use")`), so with cua-driver alone Telegram can drive the Mac and NotchNotch's chat can't. `ComputerUseService.enableInChat()` runs it after a successful `computer-use install` and from the "Activer" button of Settings › Contrôle du Mac (shown when cua-driver is installed and the toolset is off), never otherwise. Hermes's CLI writes `platform_toolsets.api_server` in `config.yaml` (the whole enabled list). It exits 0 even on an unknown toolset, so the result is read back from `GET /v1/toolsets` (gateway, Bearer, re-reads config.yaml each call), also read by `refreshState()` (`chatEnabled`). No gateway restart: Hermes reloads the config for every new agent (read in the code, to confirm in the H14 test). Never enable or disable another toolset.
- **Approval answers via `POST /v1/runs/{id}/approval`** — `HermesClient.respondToApproval` answers an `approval.request` received on the `/v1/chat/completions` stream (run id = chatcmpl id, `request_id`, Bearer). Only on a click on the in-bubble card, only `once` or `deny`, never `always` (it writes a permanent Hermes allowlist NotchNotch doesn't show) nor `session` (not offered yet). 409 = Hermes no longer waits (timeout → denied). Chat can't answer: the agent is blocked waiting.
- **`approvals.mode`** — written as `manual` after a successful computer-use install and by the Settings picker. Legal values: `manual` / `smart` / `off` (no `auto`). Read via `HermesConfig.readKey`. Never write other `approvals.*` keys.
- **Gateway service** — `HermesGatewayLauncher` runs `hermes gateway start` / `restart` / `uninstall` (chat can't fix the gateway when the gateway is down) and reads state with `launchctl print`. At boot it only re-loads an `.installedNotLoaded` plist; installing waits for user consent (onboarding or the "Tape pour réparer" toast). Repair flow: `ensureApiServerEnv()` → `start` or `restart` → poll `/health` 10s → retry. A 401 with a valid key means restart, never rotate.
- **Hermes install (onboarding, H14)** — when `~/.hermes/config.yaml` is missing, `OnboardingViewModel.installHermes()` downloads `install.sh` of `main` (`raw.githubusercontent.com/…/main/scripts/install.sh`, never a tag's copy: it clones main's tip) into `~/Library/Caches/notchnotch-installer/`, reads `--manifest`, then runs each stage that needs no user input with `--stage <name> --json --non-interactive --skip-computer-use --channel stable` (Hermes Setup's protocol; `setup` and `gateway` skipped) and parses the last `{"ok",…}` line. A stage without that line is retried once, then the whole script runs in one call. The browser tools stay (D1). Output goes to `install.log` next to the script (the script itself writes no `~/.hermes/logs/install.log` off a terminal). Then `ensureApiServerEnv()`, `hermes gateway start` (the gateway exception above: no `gateway install`, no `hermes pm`) and `/health` polled 30 times. Git: `xcode-select -p`, then `git --version` (see gotcha), else `xcode-select --install` and a 5-minute wait.
- **Provider connection (onboarding Connexion, Settings)** — the OpenRouter OAuth (`OpenRouterOAuthService`) and the pasted key write `<PROVIDER>_API_KEY` via `writeRawEnv` (`HermesConfig.writeAPIKey`) and `model.provider` / `model.base_url` / `model.default`. The OpenRouter default is picked in the live list (`OpenRouterCatalog.pickFreeToolModel`: free, with `tools`, preference order, else the first listed), never a hard-coded ID; nothing is written to `model.default` when the list can't be read (the Ready step says to pick one in Settings).
- **`API_SERVER_ENABLED`, `API_SERVER_CORS_ORIGINS`, `API_SERVER_KEY`, `model.max_tokens`** —
  - `ensureApiServerEnv()` writes `API_SERVER_ENABLED=true` and `CORS=*` when absent (respects existing values).
  - It generates `API_SERVER_KEY` (32 random bytes, hex) only when the key is absent or unusable. A valid key is never replaced. It's written via `writeRawEnv`, never `hermes config set` (argv shows up in `ps`).
  - `model.max_tokens: 8000` is set when switching to an OpenRouter `:free` model (the free tier rejects >~13K), removed via `unsetKey` when switching to a paid model, and set at boot only if absent. Hermes ignores it since v0.21.6 (`fd3565d`, no user output cap any more): only older gateways read it.
  - Never write other `API_SERVER_*` keys, or `model.*` keys beyond `default` / `provider` / `base_url` / `max_tokens`.
- **`display.language: fr`** — written once at launch (`applyHermesLocaleOnce`, guarded by `didSetHermesLocaleFr`).

## Brain pipeline invariants

- Wiki path is `~/.hermes/brain/wiki/` (fallback `~/.hermes/wiki/`). The llm-wiki skill defaults to `~/wiki`, so setup forces `skills.config.wiki.path` via a chat message telling Hermes to run `hermes config set` in its terminal.
- Raw sources go to `~/.hermes/brain/raw/{articles,papers,transcripts}` with YAML frontmatter (`source`, `title`, `clipped_at`, `word_count`). The `brain-ingest` cron (every 2h, deliver=local) compiles them; `brain-lint` runs Sundays 9h.
- The wiki contains `SCHEMA.md`, `index.md`, `log.md` (append-only, `## [YYYY-MM-DD] action | subject`) and `concepts/`, `entities/`, `comparisons/`, `queries/`, `raw/articles/`.
- `.lint-report.json` is optional: if absent, health is `.unknown`, never an error. Not verified end-to-end yet.
- Memory files (`MEMORY.md`, `USER.md`) use `§` as the block separator — Hermes's convention. Do not change.
- User-facing copy never says "wiki", "RAG", "Karpathy" or "lint". It says "cerveau", "intégration", "maintenance".

## Companion: NotchNotch Clipper

[KikinaStudio/NotchNotch-Clipper](https://github.com/KikinaStudio/NotchNotch-Clipper) — Chrome extension. It saves by calling Hermes `POST /v1/responses` itself, then pings `POST localhost:19944/clip` with `{"title","url"}`. `ClipperListener` only shows a `.success` toast (green, pacman icon). It does not send `API_SERVER_KEY` yet, so it gets a 401 on Hermes v0.21.6+ until it's updated.

## UserDefaults keys (maintained list — add new keys here)

- `onboardingCompleted` — main onboarding
- `onboardingStep` — current onboarding screen, 0–3 since H14 (`OnboardingStep`: welcome, install, connect, ready); removed on completion
- `onboardingStepScaleH14` — true once `onboardingStep` uses the H14 scale; absent = a pre-H14 value (0–6), remapped once at launch (0,1→0 · 2→1 · 3→2 · 4–6→3). `selectedProvider` (pre-H14, never read) is deleted at launch
- `hasCompletedBrainOnboarding` — brain setup sheet
- `hermesConversationId` — `conversation` name for server-side chaining (= `notchnotchSessionId` since H2a; older installs keep a UUID until the next new conversation)
- `notchnotchSessionId` — current conversation key `notchnotch-<uuid>` (`X-Hermes-Session-Id` + `X-Hermes-Session-Key`, TitleStore key)
- `hermesSessionId` — legacy Telegram-derived session ID (informational)
- `textSize` — `"medium"` | `"large"` (legacy `"small"` falls back to medium)
- `panelSize` — `"standard"` | `"large"`
- `googleConnectedEmail` — connected Gmail address; absent = not connected
- `userCustomModels` — JSON `[String: [HermesConfig.CustomModel]]`
- `didSetHermesLocaleFr` — `display.language: fr` written once
- `computerUsePermissionsConfirmed` — last known TCC state of cua-driver: Hermes's real answer when it has one (H13), else the user's "C'est bon" (act of faith)
- `openrouterFreeModelsCacheV1` — cached OpenRouter `:free` list, 24h TTL; bump `V1` on a schema change
- `chatModelProvider` / `chatModelID` — model picked in the notch bar for the chat only (H4), sent per request; absent = `model.default`

## Working rules

- **Hermes v0.21 plan**: read [PLAN-HERMES-V021.md](PLAN-HERMES-V021.md) before an H-session (next session, done work, open questions) and update its table + journal in the same commit at the end.
- **Read first, report back** on multi-file changes: surface assumptions, confirm signatures, list impacted files, then code.
- Match local idioms (e.g. the `.onChange` closure signature already used in the file).
- After a change: build with `scripts/run.sh` and manually test the feature; check `git diff` for unexpected edits; document new `@AppStorage` keys above.
- **Audit protocol**: when asked to audit your own work, don't modify anything. Read, verify, report as ✅ OK / ⚠️ + explanation / ❓ + question per item.
