//
//  SubscriptionPlan.swift
//
//  Subscription plan types — product IDs come from BrandConfig
//

import Foundation

enum SubscriptionPlan: String, CaseIterable {
    case weekly
    case monthly

    /// App Store Connect product ID — reads from BrandConfig
    var productId: String {
        switch self {
        case .weekly: return BrandConfig.weeklyProductId
        case .monthly: return BrandConfig.monthlyProductId
        }
    }

    /// Reverse lookup: find a plan by its product ID
    static func from(productId: String) -> SubscriptionPlan? {
        allCases.first { $0.productId == productId }
    }

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    /// Default limit description when backend plan info is unavailable
    var defaultLimitDescription: String {
        switch self {
        case .weekly: return "10 videos"
        case .monthly: return "50 videos"
        }
    }

    /// Default generation limit
    var defaultGenerationLimit: Int {
        switch self {
        case .weekly: return 10
        case .monthly: return 50
        }
    }

    /// Default period in days
    var defaultPeriodDays: Int {
        switch self {
        case .weekly: return 7
        case .monthly: return 30
        }
    }
}
