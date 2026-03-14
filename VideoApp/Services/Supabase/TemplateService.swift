//
//  TemplateService.swift
//  AIVideo
//
//  Service for fetching video templates from Supabase
//

import Foundation

@MainActor
final class TemplateService: ObservableObject {
    // MARK: - Singleton
    static let shared = TemplateService()
    
    // MARK: - Published Properties
    @Published private(set) var templates: [VideoTemplate] = []
    @Published private(set) var categories: [VideoCategory] = []
    @Published private(set) var templatesByCategory: [UUID: [VideoTemplate]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    private var lastFetchTime: Date?
    private static let cacheTTL: TimeInterval = 5 * 60
    
    // MARK: - Private
    private init() {}
    
    private var isCacheValid: Bool {
        guard let lastFetch = lastFetchTime else { return false }
        return Date().timeIntervalSince(lastFetch) < Self.cacheTTL
    }
    
    // MARK: - Public Methods
    
    /// Fetch active templates and categories from Supabase
    func fetchTemplates() async {
        if isCacheValid && !templates.isEmpty && !categories.isEmpty {
            return
        }
        
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        async let categoriesTask: () = fetchCategories()
        async let templatesTask: () = fetchTemplatesData()
        
        _ = await (categoriesTask, templatesTask)
        
        if error == nil {
            lastFetchTime = Date()
        }
    }
    
    private func fetchCategories() async {
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
                throw TemplateServiceError.fetchFailed
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            categories = try decoder.decode([VideoCategory].self, from: data)
        } catch {
            self.error = error
            print("❌ TemplateService categories error: \(error)")
        }
    }
    
    private func fetchTemplatesData() async {
        do {
            let url = URL(string: "\(Secrets.supabaseUrl)/rest/v1/reference_videos?select=*,reference_video_categories(category_id)&is_active=eq.true&order=sort_order.asc")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw TemplateServiceError.fetchFailed
            }
            
            let decoder = JSONDecoder()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                if let date = formatter.date(from: dateString) { return date }
                if let date = ISO8601DateFormatter().date(from: dateString) { return date }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
            }
            
            let fetchedTemplates = try decoder.decode([VideoTemplate].self, from: data)
            templates = fetchedTemplates
            
            var grouped: [UUID: [VideoTemplate]] = [:]
            for template in fetchedTemplates {
                if let categoryId = template.effectiveCategoryId {
                    grouped[categoryId, default: []].append(template)
                }
            }
            templatesByCategory = grouped
            
        } catch {
            self.error = error
            print("❌ TemplateService templates error: \(error)")
        }
    }
    
    /// Get a template by ID
    func template(withId id: UUID) -> VideoTemplate? {
        templates.first { $0.id == id }
    }
    
    /// Get templates for a specific category
    func templates(for category: VideoCategory) -> [VideoTemplate] {
        templatesByCategory[category.id] ?? []
    }
    
    /// Refresh templates
    func refresh() async {
        lastFetchTime = nil
        await fetchTemplates()
    }
}

// MARK: - Errors

enum TemplateServiceError: Error, LocalizedError {
    case fetchFailed
    case templateNotFound
    
    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Failed to load video templates"
        case .templateNotFound:
            return "Template not found"
        }
    }
}
