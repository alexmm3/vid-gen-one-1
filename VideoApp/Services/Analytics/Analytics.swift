//
//  Analytics.swift
//  AIVideo
//
//  Main analytics facade for easy access throughout the app
//  Adapted from templates-reference
//

import Foundation

/// Main analytics facade for easy access throughout the app
enum Analytics {
    
    // MARK: - Private Properties
    
    private static let service: AnalyticsService = FirebaseAnalyticsService()
    
    // MARK: - Public Methods
    
    /// Track an analytics event
    static func track(_ event: AnalyticsEvent) {
        service.track(event)
    }
    
    /// Set the user ID for analytics
    static func setUserId(_ id: String?) {
        service.setUserId(id)
    }
    
    /// Set a user property
    static func setUserProperty(_ value: String?, for key: AnalyticsUserPropertyKey) {
        service.setUserProperty(value, for: key)
    }
    
    /// Set default event parameters (attached to all events)
    static func setDefaultEventParameters(_ parameters: [String: Any]?) {
        service.setDefaultEventParameters(parameters)
    }
    
    /// Update subscription status user properties
    static func updateSubscriptionStatus(isPremium: Bool, plan: String?) {
        setUserProperty(isPremium ? "premium" : "free", for: .subscriptionStatus)
        if let plan = plan {
            setUserProperty(plan, for: .subscriptionPlan)
        }
    }
}
