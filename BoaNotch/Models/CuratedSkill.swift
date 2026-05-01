import Foundation

/// Editorial entry in the Skills tab's curated zone.
///
/// Curated skills are user-facing capabilities (Gmail, Spotify, Notion…) shown
/// with brand icons and a structured connect/disconnect path. They sit above
/// the raw `SkillInfo` list (zone 2) which keeps the technical skills.
///
/// One curated entry can map to one or several Hermes skills via
/// `mappedSkillIDs` so we don't double-list them in zone 2.
struct CuratedSkill: Identifiable, Hashable {
    let id: String
    let displayName: String
    let descriptionFR: String
    let icon: IconKind
    let detection: DetectionRule
    let connectAction: ConnectAction
    let promptExamplesFR: [String]
    let mappedSkillIDs: [String]
}

/// Visual identity for a curated entry. `.brand` resolves to a Simple Icons
/// monochrome SVG bundled in `Contents/Resources/<slug>.svg` and tinted to the
/// official brand `hex`. `.sfSymbol` is the fallback for capabilities without
/// a single brand (web browsing, image generation).
enum IconKind: Hashable {
    case brand(slug: String, hex: String)
    case sfSymbol(name: String)
}

/// How NotchNotch decides whether a curated capability is connected. Resolved
/// in `BrainViewModel.resolveCuratedStates()` against on-disk Hermes state.
enum DetectionRule: Hashable {
    /// `~/.hermes/.env` contains a non-empty `KEY=...` line.
    case envVar(String)
    /// `~/.hermes/google_token.json` exists and has the given OAuth scope
    /// granted (substring match against any URL in the `scopes` array).
    case googleScope(String)
    /// `~/.hermes/auth.json` contains `providers.<id>` (truthy).
    case hermesAuthProvider(String)
}

/// Structured connect path. `.viaChat` is intentionally *not* a case here —
/// connection actions must be exposed as visible UI (OAuth button, API-key
/// form, external link) so non-dev users can see and inspect what's possible.
/// See CLAUDE.md "Curated Skills connect rule".
enum ConnectAction: Hashable {
    case oauth(OAuthProvider)
    case apiKeyInput(envVarName: String, helpText: String, helpURL: URL?)
    case external(URL)
    case none
}

enum OAuthProvider: Hashable {
    case google
}

/// Resolved per-card state surfaced by `BrainViewModel.curatedSkillStates`.
/// `.connected` may carry an optional detail (e.g. the Google email) shown in
/// the drill-down view.
enum CuratedSkillState: Hashable {
    case connected(detail: String?)
    case available
}
