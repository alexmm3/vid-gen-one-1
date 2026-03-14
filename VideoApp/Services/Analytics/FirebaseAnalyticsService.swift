//
//  FirebaseAnalyticsService.swift
//  AIVideo
//
//  Firebase Analytics implementation of AnalyticsService
//  NOTE: Requires Firebase SDK. Add FirebaseAnalytics to your project.
//

import Foundation
import FirebaseAnalytics
import FirebaseCore

/// Firebase Analytics implementation of AnalyticsService
final class FirebaseAnalyticsService: AnalyticsService {
    
    func track(_ event: AnalyticsEvent) {
        guard FirebaseApp.app() != nil else { return }
        
        // Add default platform parameter to all events
        var parameters = event.parameters ?? [:]
        parameters["platform"] = "ios"
        
        // Log event to Firebase Analytics
        FirebaseAnalytics.Analytics.logEvent(event.name, parameters: parameters.isEmpty ? nil : parameters)
        
        // Debug logging
        #if DEBUG
        print("📊 Analytics: \(event.name) - \(parameters)")
        #endif
    }
    
    func setUserId(_ id: String?) {
        guard FirebaseApp.app() != nil else { return }
        
        FirebaseAnalytics.Analytics.setUserID(id)
        
        #if DEBUG
        print("📊 Analytics: Set user ID - \(id ?? "nil")")
        #endif
    }
    
    func setUserProperty(_ value: String?, for key: AnalyticsUserPropertyKey) {
        guard FirebaseApp.app() != nil else { return }
        
        FirebaseAnalytics.Analytics.setUserProperty(value, forName: key.rawValue)
        
        #if DEBUG
        print("📊 Analytics: Set property \(key.rawValue) = \(value ?? "nil")")
        #endif
    }
    
    func setDefaultEventParameters(_ parameters: [String: Any]?) {
        guard FirebaseApp.app() != nil else { return }
        
        FirebaseAnalytics.Analytics.setDefaultEventParameters(parameters)
        
        #if DEBUG
        print("📊 Analytics: Set default params - \(parameters ?? [:])")
        #endif
    }
}
