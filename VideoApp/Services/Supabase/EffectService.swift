//
//  EffectService.swift
//  AIVideo
//
//  Fetches effects and effect categories from Supabase (effects + effect_categories tables)
//

import Foundation

@MainActor
final class EffectService: ObservableObject {
    static let shared = EffectService()

    @Published private(set) var categories: [VideoCategory] = []
    @Published private(set) var effectsByCategory: [UUID: [Effect]] = [:]
    @Published private(set) var allEffects: [Effect] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private static let cacheTTL: TimeInterval = 5 * 60
    private var lastFetchTime: Date?
    private var isFetching = false

    private init() {}

    private var isCacheValid: Bool {
        guard let lastFetch = lastFetchTime else { return false }
        return Date().timeIntervalSince(lastFetch) < Self.cacheTTL
    }

    /// Fetch all effect categories and effects (uses cache if valid)
    func fetchAll() async {
        if isCacheValid && !categories.isEmpty && !effectsByCategory.isEmpty {
            return
        }
        guard !isFetching else { return }

        isFetching = true
        isLoading = true
        error = nil
        defer {
            isLoading = false
            isFetching = false
        }

        async let categoriesTask: () = fetchCategories()
        async let effectsTask: () = fetchEffectsGrouped()
        _ = await (categoriesTask, effectsTask)

        if error == nil {
            lastFetchTime = Date()
        }
    }

    /// Force refresh (ignores cache)
    func forceRefresh() async {
        lastFetchTime = nil
        await fetchAll()
    }

    func invalidateCache() {
        lastFetchTime = nil
    }

    private static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) { return date }
            if let date = ISO8601DateFormatter().date(from: dateString) { return date }
            return Date()
        }
        return decoder
    }

    private func fetchCategories() async {
        do {
            let url = URL(string: "\(Secrets.supabaseUrl)/rest/v1/effect_categories?is_active=eq.true&order=sort_order.asc")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw EffectServiceError.fetchFailed
            }

            let decoder = Self.jsonDecoder
            categories = try decoder.decode([VideoCategory].self, from: data)
        } catch {
            self.error = error
        }
    }

    private func fetchEffectsGrouped() async {
        do {
            let url = URL(string: "\(Secrets.supabaseUrl)/rest/v1/effects?is_active=eq.true&order=sort_order.asc")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw EffectServiceError.fetchFailed
            }

            let decoder = Self.jsonDecoder
            let effects = try decoder.decode([Effect].self, from: data)

            var grouped: [UUID: [Effect]] = [:]
            var flat: [Effect] = []
            for effect in effects {
                guard effect.previewVideoUrl != nil || effect.thumbnailUrl != nil else {
                    continue
                }
                flat.append(effect)
                if let categoryId = effect.categoryId {
                    grouped[categoryId, default: []].append(effect)
                }
            }
            effectsByCategory = grouped
            allEffects = flat
        } catch {
            self.error = error
        }
    }

    func effects(for category: VideoCategory) -> [Effect] {
        effectsByCategory[category.id] ?? []
    }

    var nonEmptyCategories: [VideoCategory] {
        categories.filter { !(effectsByCategory[$0.id]?.isEmpty ?? true) }
    }
}

enum EffectServiceError: Error, LocalizedError {
    case fetchFailed
    var errorDescription: String? { "Failed to load effects" }
}
