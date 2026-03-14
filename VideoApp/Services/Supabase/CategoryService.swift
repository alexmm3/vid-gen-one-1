//
//  CategoryService.swift
//  AIVideo
//
//  Service for fetching video categories and templates grouped by category
//

import Foundation

@MainActor
final class CategoryService: ObservableObject {
    // MARK: - Singleton
    static let shared = CategoryService()
    
    // MARK: - Published Properties
    @Published private(set) var categories: [VideoCategory] = []
    @Published private(set) var templatesByCategory: [UUID: [VideoTemplate]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    // MARK: - Cache Configuration
    private static let cacheTTL: TimeInterval = 5 * 60 // 5 minutes
    private var lastFetchTime: Date?
    private var isFetching = false
    
    // MARK: - Private
    private init() {}
    
    // MARK: - Cache Helpers
    
    /// Check if cache is still valid
    private var isCacheValid: Bool {
        guard let lastFetch = lastFetchTime else { return false }
        return Date().timeIntervalSince(lastFetch) < Self.cacheTTL
    }
    
    // MARK: - Public Methods
    
    /// Fetch all categories and templates (uses cache if valid)
    func fetchAll() async {
        // Return cached data if still valid and we have data
        if isCacheValid && !categories.isEmpty && !templatesByCategory.isEmpty {
            print("📦 CategoryService: Using cached data (TTL: \(Int(Self.cacheTTL - Date().timeIntervalSince(lastFetchTime!)))s remaining)")
            return
        }
        
        // Prevent duplicate concurrent fetches
        guard !isFetching else {
            print("⏳ CategoryService: Fetch already in progress, skipping")
            return
        }
        
        isFetching = true
        isLoading = true
        error = nil
        
        defer {
            isLoading = false
            isFetching = false
        }
        
        async let categoriesTask: () = fetchCategories()
        async let templatesTask: () = fetchTemplatesGrouped()
        
        _ = await (categoriesTask, templatesTask)
        
        // Update cache timestamp on successful fetch
        if error == nil {
            lastFetchTime = Date()
            print("✅ CategoryService: Cache updated, valid for \(Int(Self.cacheTTL))s")
        }
    }
    
    /// Force refresh all data (ignores cache)
    func forceRefresh() async {
        lastFetchTime = nil // Invalidate cache
        await fetchAll()
    }
    
    /// Fetch categories from Supabase
    func fetchCategories() async {
        do {
            let url = URL(string: "\(Secrets.supabaseUrl)/rest/v1/video_categories?is_active=eq.true&order=sort_order.asc")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw CategoryServiceError.fetchFailed
            }
            
            let decoder = JSONDecoder()
            categories = try decoder.decode([VideoCategory].self, from: data)
            
            print("✅ CategoryService: Loaded \(categories.count) categories")
            
        } catch {
            self.error = error
            print("❌ CategoryService: \(error.localizedDescription)")
        }
    }
    
    /// Fetch templates grouped by category (many-to-many via join table)
    func fetchTemplatesGrouped() async {
        do {
            // 1. Fetch all active templates
            let templatesUrl = URL(string: "\(Secrets.supabaseUrl)/rest/v1/reference_videos?is_active=eq.true&order=sort_order.asc")!
            
            var templatesRequest = URLRequest(url: templatesUrl)
            templatesRequest.httpMethod = "GET"
            templatesRequest.cachePolicy = .reloadIgnoringLocalCacheData
            templatesRequest.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            templatesRequest.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
            templatesRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // 2. Fetch category mappings from join table (includes per-category sort_order)
            let mappingsUrl = URL(string: "\(Secrets.supabaseUrl)/rest/v1/reference_video_categories?select=reference_video_id,category_id,sort_order&order=sort_order.asc")!
            
            var mappingsRequest = URLRequest(url: mappingsUrl)
            mappingsRequest.httpMethod = "GET"
            mappingsRequest.cachePolicy = .reloadIgnoringLocalCacheData
            mappingsRequest.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            mappingsRequest.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
            mappingsRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Fetch both in parallel
            async let templatesResponse = URLSession.shared.data(for: templatesRequest)
            async let mappingsResponse = URLSession.shared.data(for: mappingsRequest)
            
            let (templatesData, templatesHTTP) = try await templatesResponse
            let (mappingsData, mappingsHTTP) = try await mappingsResponse
            
            guard let tHTTP = templatesHTTP as? HTTPURLResponse,
                  (200...299).contains(tHTTP.statusCode) else {
                throw CategoryServiceError.fetchFailed
            }
            
            guard let mHTTP = mappingsHTTP as? HTTPURLResponse,
                  (200...299).contains(mHTTP.statusCode) else {
                throw CategoryServiceError.fetchFailed
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: dateString) {
                    return date
                }
                if let date = ISO8601DateFormatter().date(from: dateString) {
                    return date
                }
                return Date()
            }
            
            let templates = try decoder.decode([VideoTemplate].self, from: templatesData)
            let mappings = try decoder.decode([VideoCategoryMapping].self, from: mappingsData)
            
            // Build lookup: template ID -> template
            let templateLookup = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
            
            // Sort mappings by per-category sort_order, then group (many-to-many)
            let sortedMappings = mappings.sorted { $0.sortOrder < $1.sortOrder }
            var grouped: [UUID: [VideoTemplate]] = [:]
            for mapping in sortedMappings {
                if let template = templateLookup[mapping.referenceVideoId] {
                    grouped[mapping.categoryId, default: []].append(template)
                }
            }
            templatesByCategory = grouped
            
            let totalPlacements = mappings.count
            print("✅ CategoryService: Loaded \(templates.count) templates with \(totalPlacements) category placements across \(grouped.count) categories")
            
        } catch {
            self.error = error
            print("❌ CategoryService: \(error.localizedDescription)")
        }
    }
    
    /// Get templates for a specific category
    func templates(for categoryId: UUID) -> [VideoTemplate] {
        templatesByCategory[categoryId] ?? []
    }
    
    /// Get templates for a category by name
    func templates(forCategoryName name: String) -> [VideoTemplate] {
        guard let category = categories.first(where: { $0.name == name }) else {
            return []
        }
        return templates(for: category.id)
    }
    
    /// Refresh all data (force refresh, ignores cache)
    func refresh() async {
        await forceRefresh()
    }
    
    /// Invalidate cache (useful when data might have changed)
    func invalidateCache() {
        lastFetchTime = nil
        print("🗑️ CategoryService: Cache invalidated")
    }
}

// MARK: - Supporting Models

/// Mapping from the reference_video_categories join table
private struct VideoCategoryMapping: Codable {
    let referenceVideoId: UUID
    let categoryId: UUID
    let sortOrder: Int
    
    enum CodingKeys: String, CodingKey {
        case referenceVideoId = "reference_video_id"
        case categoryId = "category_id"
        case sortOrder = "sort_order"
    }
}

// MARK: - Errors

enum CategoryServiceError: Error, LocalizedError {
    case fetchFailed
    
    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Failed to load categories"
        }
    }
}
