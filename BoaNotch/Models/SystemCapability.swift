import Foundation

/// Editorial entry for a capability that operates on the Mac itself (clicks,
/// keystrokes, screen reads via Hermes `computer_use`), as opposed to
/// `CuratedSkill` which wires NotchNotch to third-party services (Gmail,
/// Notion, Spotify…).
///
/// Both types share a similar shape (id / displayName / description / icon /
/// detection / prompt examples), but they diverge on the connection model:
///
/// - `CuratedSkill` → "connect" means linking an external account (OAuth, API
///   key, third-party CLI) and the action surface is the per-card detail view.
/// - `SystemCapability` → "install" means downloading and registering a local
///   driver (`cua-driver` for `computer_use`), then granting macOS TCC
///   permissions (Accessibility, Screen Recording, Automation). No external
///   account, no token to refresh; the agent operates against the user's own
///   machine.
///
/// Same doctrine applies as for CuratedSkill though: per CLAUDE.md
/// "Curated Skills connect rule (NEVER `.viaChat`)", the install and
/// permission flow MUST be exposed through structured UI (buttons opening
/// system panels, progress indicators), never mediated by chat. The mission
/// is to make Hermes's powers visible and inspectable to non-dev users.
struct SystemCapability: Identifiable, Hashable {
    let id: String
    let displayName: String
    let descriptionFR: String
    let icon: IconKind
    let detection: SystemDetectionRule
    let promptExamplesFR: [String]
    let docsURL: URL
}

/// How NotchNotch decides whether a system capability is installed. The single
/// case in v1 covers `computer_use` (binary on PATH). Future capabilities may
/// want richer detection (process running, kext loaded, etc.).
enum SystemDetectionRule: Hashable {
    /// `which <name>` returns 0 — the binary is reachable from a login shell.
    case binaryOnPath(String)
}

/// Resolved per-capability state. The 4 cases form a directed progression:
///
///   `.notInstalled` → `.installing` → `.installedPendingPermissions` → `.ready`
///
/// - `.installedPendingPermissions`: the binary is on PATH but the user has
///   not yet confirmed the macOS TCC grants (Accessibility / Screen Recording
///   / Automation). NotchNotch can NOT verify these programmatically —
///   cua-driver is a separate binary with its own bundle-id, and TCC grants
///   are scoped per bundle.
/// - `.ready`: binary is on PATH AND the user clicked "C'est bon" in the
///   detail view after walking through the 3 System Settings panels. This is
///   a UI-side act of faith persisted via `UserDefaults`.
enum SystemCapabilityState: Hashable {
    case notInstalled
    case installing
    case installedPendingPermissions
    case ready
}
