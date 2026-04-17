//
//  AnalyticsService.swift
//  AIVideo
//
//  Protocol for analytics service implementations
//

import Foundation

/// Protocol for analytics service implementations
protocol AnalyticsService {
    /// Track an analytics event
    func track(_ event: AnalyticsEvent)
    
    /// Set the user ID for analytics
    func setUserId(_ id: String?)
    
    /// Set a user property
    func setUserProperty(_ value: String?, for key: AnalyticsUserPropertyKey)
    
    /// Set default event parameters (attached to all events)
    func setDefaultEventParameters(_ parameters: [String: Any]?)
}

/// User property keys for analytics
enum AnalyticsUserPropertyKey: String {
    case subscriptionStatus = "subscription_status"
    case subscriptionPlan = "subscription_plan"
    case appVersion = "app_version"
    case platform = "platform"
    case deviceId = "device_id"
    case totalGenerations = "total_generations"
    case onboardingCompleted = "onboarding_completed"
    case firstGenerationDate = "first_generation_date"
}
