//
//  SubscriptionPlan.swift
//
//  Subscription plan types — product IDs come from BrandConfig
//

import Foundation

enum SubscriptionPlan: String, CaseIterable {
    case weekly
    case yearly
    
    /// App Store Connect product ID — reads from BrandConfig
    var productId: String {
        switch self {
        case .weekly: return BrandConfig.weeklyProductId
        case .yearly: return BrandConfig.yearlyProductId
        }
    }
    
    /// Reverse lookup: find a plan by its product ID
    static func from(productId: String) -> SubscriptionPlan? {
        allCases.first { $0.productId == productId }
    }
    
    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .yearly: return "Yearly"
        }
    }
    
    var trialDays: Int? {
        switch self {
        case .weekly: return 3
        case .yearly: return nil
        }
    }
    
    var hasTrial: Bool {
        trialDays != nil
    }
    
    /// Default limit description when backend plan info is unavailable
    var defaultLimitDescription: String {
        switch self {
        case .weekly: return "10 videos"
        case .yearly: return "40 videos"
        }
    }
    
    /// Default generation limit
    var defaultGenerationLimit: Int {
        switch self {
        case .weekly: return 10
        case .yearly: return 40
        }
    }
    
    /// Default period in days
    var defaultPeriodDays: Int {
        switch self {
        case .weekly: return 7
        case .yearly: return 30
        }
    }
}
