//
//  SubscriptionPlanService.swift
//  AIVideo
//
//  Service for fetching subscription plans from Supabase
//  Based on iOS-API-Integration_update.md
//

import Foundation

@MainActor
final class SubscriptionPlanService: ObservableObject {
    // MARK: - Singleton
    static let shared = SubscriptionPlanService()
    
    // MARK: - Published Properties
    @Published private(set) var plans: [SubscriptionPlanInfo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    // MARK: - Private
    private init() {}
    
    // MARK: - Public Methods
    
    /// Fetch active subscription plans from Supabase
    func fetchPlans() async {
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        do {
            // Using direct REST API call
            let url = URL(string: "\(Secrets.supabaseUrl)/rest/v1/subscription_plans?is_active=eq.true&order=price_cents.asc")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw SubscriptionPlanServiceError.fetchFailed
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            let fetchedPlans = try decoder.decode([SubscriptionPlanInfo].self, from: data)
            plans = fetchedPlans
            
            print("✅ SubscriptionPlanService: Loaded \(plans.count) plans")
            
        } catch {
            self.error = error
            print("❌ SubscriptionPlanService: \(error.localizedDescription)")
        }
    }
    
    /// Get plan by Apple product ID
    func plan(forAppleProductId productId: String) -> SubscriptionPlanInfo? {
        plans.first { $0.appleProductId == productId }
    }
    
    /// Get plan by name
    func plan(named name: String) -> SubscriptionPlanInfo? {
        plans.first { $0.name == name }
    }
    
    /// Refresh plans
    func refresh() async {
        await fetchPlans()
    }
}

// MARK: - Plan Model

/// Subscription plan information from database
struct SubscriptionPlanInfo: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let generationLimit: Int
    let periodDays: Int?
    let appleProductId: String?
    let isActive: Bool
    let priceCents: Int?
    let description: String?
    
    /// Human-readable limit description (e.g., "10 videos")
    var limitDescription: String {
        if name.lowercased().contains("unlimited") || generationLimit >= 999999 {
            return "Unlimited videos"
        }
        return "\(generationLimit) videos"
    }
    
    /// Whether this is an unlimited plan
    var isUnlimited: Bool {
        name.lowercased().contains("unlimited") || generationLimit >= 999999 || periodDays == nil
    }
}

// MARK: - Errors

enum SubscriptionPlanServiceError: Error, LocalizedError {
    case fetchFailed
    case planNotFound
    
    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Failed to load subscription plans"
        case .planNotFound:
            return "Subscription plan not found"
        }
    }
}
