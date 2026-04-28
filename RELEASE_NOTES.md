# notchnotch v1.2.1

## Auto-update is here

notchnotch now updates itself via Sparkle. New releases land in the menu — click **Install and Relaunch** and you're on the latest version. No more manual DMG hunts.

We're still ad-hoc-signed (no Apple Developer account yet), so each new version triggers macOS's Gatekeeper warning the same way the first install did. notchnotch shows you a one-click guide right after the relaunch — full walkthrough at [docs/GATEKEEPER_FIRST_LAUNCH.md](https://github.com/KikinaStudio/NotchNotch/blob/master/docs/GATEKEEPER_FIRST_LAUNCH.md).

## What's new

- Sparkle auto-update with EdDSA signature verification.
- Settings → Updates section with a manual "Check now" button.
- LLM provider picker with brand icons (11 providers, custom OpenAI-compatible endpoints, custom model IDs).
- Memory provider selection UI (built-in, hindsight, mem0, supermemory, honcho, retaindb, openviking, byterover, holographic).
- OpenRouter OAuth sign-in flow.
- Settings panel refactor.

## Install

Drag notchnotch.app to Applications, then **right-click → Open → Open** on first launch (and after each update).

## Verify the binary

```sh
shasum -a 256 /Applications/notchnotch.app/Contents/MacOS/notchnotch
```
