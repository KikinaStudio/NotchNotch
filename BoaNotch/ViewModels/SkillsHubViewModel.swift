import Foundation
import SwiftUI

/// Drives the catalogue overlay that lives above BrainView when
/// `notchVM.isSkillsHubOpen == true`. Owns the screen state machine
/// (catalog → preview → installing → installed/error), the debounced search,
/// and the cached browse result.
///
/// Filtering of "already installed" capabilities is parameterized via
/// `installedNames` (set by BrainView from `brainVM.skills`) so the VM does
/// not retain a reference to BrainViewModel.
@MainActor
final class SkillsHubViewModel: ObservableObject {

    // MARK: - State

    enum Phase: Equatable {
        case loading
        case ready
        case error(String)
    }

    enum Screen: Equatable {
        case catalog
        case preview(HubSkill)
        case installing(HubSkill)
        case installed(HubSkill)
        case installError(HubSkill, String)
    }

    @Published var phase: Phase = .loading
    @Published var screen: Screen = .catalog
    @Published var query: String = ""
    @Published var detail: HubSkillDetail?
    @Published var detailLoading: Bool = false
    @Published var detailError: String?

    /// All catalogue items returned by the last `browse()` call.
    @Published private(set) var allSkills: [HubSkill] = []

    /// Lowercased names of skills already present in `brainVM.skills`. Set by
    /// BrainView to filter them out of the catalogue.
    var installedNames: Set<String> = [] {
        didSet { objectWillChange.send() }
    }

    /// Called after a successful install so the parent (BrainView) can refresh
    /// its `brainVM.skills` list.
    var onInstalled: (() -> Void)?

    private var debouncedQuery: String = ""
    private var searchDebounceTask: Task<Void, Never>?

    // MARK: - Catalogue

    /// Items shown to the user. Drops `installedNames` and applies the
    /// debounced query (case-insensitive on name + description).
    var visibleSkills: [HubSkill] {
        let q = debouncedQuery.lowercased()
        return allSkills
            .filter { !installedNames.contains($0.name.lowercased()) }
            .filter { skill in
                guard !q.isEmpty else { return true }
                return skill.name.lowercased().contains(q)
                    || skill.description.lowercased().contains(q)
            }
    }

    func loadCatalog() async {
        phase = .loading
        do {
            let items = try await SkillsHubClient.shared.browse()
            // Keep only the two sources we expose in v1. Note: Hermes labels
            // skills.sh items with the *dotted* form (`skills.sh`) in the
            // `source` field, even though the install identifier prefix is
            // `skills-sh/...` with a dash. We match what `browse_skills`
            // emits.
            let allowed: Set<String> = ["official", "skills.sh"]
            allSkills = items.filter { allowed.contains($0.source) }
            phase = allSkills.isEmpty
                ? .error("Aucune capacité disponible pour le moment.")
                : .ready
        } catch let err as SkillsHubError {
            phase = .error(err.errorDescription ?? "Erreur inconnue.")
        } catch {
            phase = .error("Erreur inattendue : \(error.localizedDescription)")
        }
    }

    // MARK: - Search

    /// Debounce window: 200ms feels reactive without flooding the filter on
    /// every keystroke.
    func updateQuery(_ value: String) {
        query = value
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.debouncedQuery = value
                // Trigger SwiftUI recompute of `visibleSkills` (computed
                // property, not @Published).
                self.objectWillChange.send()
            }
        }
    }

    // MARK: - Screen transitions

    func openPreview(_ skill: HubSkill) {
        screen = .preview(skill)
        Task { await fetchDetail(for: skill) }
    }

    func backToCatalog() {
        screen = .catalog
        detail = nil
        detailError = nil
    }

    func dismissInstallResult() {
        screen = .catalog
        detail = nil
        detailError = nil
    }

    private func fetchDetail(for skill: HubSkill) async {
        detail = nil
        detailLoading = true
        detailError = nil
        do {
            let raw = try await SkillsHubClient.shared.inspect(name: skill.name)
            // Decorate with the trust we already had from browse — inspect
            // doesn't return trust_level.
            detail = HubSkillDetail(
                identifier: raw.identifier,
                name: raw.name,
                description: raw.description,
                source: raw.source.isEmpty ? skill.source : raw.source,
                trust: skill.trust,
                tags: raw.tags,
                skillMdPreview: raw.skillMdPreview,
                requiresEnv: raw.requiresEnv
            )
        } catch let err as SkillsHubError {
            detailError = err.errorDescription
        } catch {
            detailError = error.localizedDescription
        }
        detailLoading = false
    }

    // MARK: - Install

    func install() {
        guard case .preview(let skill) = screen else { return }
        // Use the resolved identifier from the inspect call; fall back to the
        // bare name (Hermes will try to resolve via _resolve_short_name).
        let identifier = detail?.identifier ?? skill.name
        screen = .installing(skill)
        let onInstalled = self.onInstalled
        Task { [weak self] in
            do {
                try await SkillsHubClient.shared.install(identifier: identifier)
                guard let self else { return }
                self.screen = .installed(skill)
                onInstalled?()
                // Refresh catalogue so the just-installed item drops out.
                await self.loadCatalog()
            } catch let err as SkillsHubError {
                guard let self else { return }
                self.screen = .installError(skill, err.errorDescription ?? "Erreur inconnue.")
            } catch {
                guard let self else { return }
                self.screen = .installError(skill, error.localizedDescription)
            }
        }
    }

    // MARK: - Reset

    func reset() {
        screen = .catalog
        detail = nil
        detailError = nil
        detailLoading = false
        query = ""
        debouncedQuery = ""
        searchDebounceTask?.cancel()
    }
}
