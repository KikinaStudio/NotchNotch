import Foundation
import Combine

/// Caches the live OpenRouter `:free` model list with a 24h TTL.
///
/// Why: the hardcoded list in `HermesConfig.availableModels` goes stale within
/// weeks (OpenRouter retires/adds free models constantly). Hardcoding meant
/// fresh users picked dead model IDs and hit HTTP 404. This catalog fetches
/// `https://openrouter.ai/api/v1/models` once per 24h, filters to free models
/// (suffix `:free` OR `pricing.prompt == 0 && pricing.completion == 0`), and
/// caches the result in UserDefaults so the picker is hot on second launch.
///
/// On first launch the cache is empty; `HermesConfig.availableModels` falls
/// back to its hardcoded short-list while a background refresh runs. Network
/// failures leave the existing cache (or fallback) intact — never blocks UI.
///
/// Not `@MainActor` — `HermesConfig` is plain `ObservableObject` and reads the
/// catalog from `availableModels` (a non-actor-isolated computed property).
/// `@Published` updates hop to the main thread explicitly in `refresh()`.
final class OpenRouterCatalog: ObservableObject {
    static let shared = OpenRouterCatalog()

    struct FreeModel: Codable, Equatable {
        let id: String           // "nvidia/nemotron-3-super-120b-a12b:free"
        let name: String         // "Nvidia Nemotron 3 Super (free)"
        let contextLength: Int   // 1000000
    }

    @Published private(set) var freeModels: [FreeModel] = []
    @Published private(set) var lastFetched: Date?

    private let cacheKey = "openrouterFreeModelsCacheV1"
    private let ttl: TimeInterval = 24 * 3600

    private init() {
        loadCached()
    }

    // MARK: - Cache I/O

    func loadCached() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        freeModels = cached.models
        lastFetched = cached.fetchedAt
    }

    private func persistCache() {
        let cache = Cache(models: freeModels, fetchedAt: lastFetched ?? Date())
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    // MARK: - Refresh

    /// Refresh only if cache is older than `ttl` or empty. Called once at
    /// app boot from `AppDelegate.applicationDidFinishLaunching`.
    func refreshIfStale() async {
        if let fetched = lastFetched,
           Date().timeIntervalSince(fetched) < ttl,
           !freeModels.isEmpty {
            return
        }
        await refresh()
    }

    /// Force a fetch. Silent on network errors — keeps the existing list so
    /// the picker doesn't go blank when OpenRouter is down.
    func refresh() async {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return }

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(ModelsResponse.self, from: data)

            let free = decoded.data.filter { model in
                if model.id.hasSuffix(":free") { return true }
                let prompt = Double(model.pricing?.prompt ?? "1") ?? 1
                let completion = Double(model.pricing?.completion ?? "1") ?? 1
                return prompt == 0 && completion == 0
            }

            let mapped = free.map { api in
                FreeModel(
                    id: api.id,
                    name: api.name,
                    contextLength: api.context_length ?? 0
                )
            }

            // Don't overwrite a populated cache with an empty result (likely
            // an OpenRouter API hiccup returning {"data": []}).
            guard !mapped.isEmpty else { return }

            await MainActor.run {
                self.freeModels = mapped
                self.lastFetched = Date()
                self.persistCache()
            }
        } catch {
            // Network/decode error — keep existing list intact.
        }
    }

    // MARK: - Label generation

    /// "nvidia/nemotron-3-super-120b-a12b:free" → "nemotron-3-super-120b-a12b"
    /// (provider prefix dropped, `:free` suffix dropped, clamped to 25 chars).
    /// Mirrors the truncation in the hardcoded fallback list so the dropdown
    /// width doesn't jump when the live list takes over.
    static func niceLabel(for id: String) -> String {
        var label = id
        if let slash = label.firstIndex(of: "/") {
            label = String(label[label.index(after: slash)...])
        }
        if label.hasSuffix(":free") {
            label = String(label.dropLast(5))
        }
        if label.count > 25 {
            label = String(label.prefix(25))
        }
        return label
    }

    // MARK: - Decoding shapes

    private struct Cache: Codable {
        let models: [FreeModel]
        let fetchedAt: Date
    }

    private struct ModelsResponse: Decodable {
        let data: [APIModel]
    }

    private struct APIModel: Decodable {
        let id: String
        let name: String
        let context_length: Int?
        let pricing: Pricing?

        struct Pricing: Decodable {
            let prompt: String?
            let completion: String?
        }
    }
}
