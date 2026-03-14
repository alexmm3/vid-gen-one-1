//
//  Constants.swift
//  AIVideo
//
//  App-wide constants and configuration values
//

import Foundation
import UIKit

// MARK: - App Constants

enum AppConstants {
    // MARK: - App Info
    static let appName = BrandConfig.appName
    static let appTagline = BrandConfig.appTagline
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    static let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    
    // MARK: - API Configuration
    enum API {
        /// Request timeout in seconds
        static let requestTimeout: TimeInterval = 120
        /// Poll interval for generation status (seconds)
        static let pollInterval: TimeInterval = 5
        /// NOTE: No client-side timeout for polling - backend determines completion/failure
        /// Safety expiry is 30 minutes (handled in ActiveGenerationManager.PendingGeneration)
    }
    
    // MARK: - Video Configuration
    enum Video {
        /// Maximum custom video duration (seconds)
        static let maxCustomVideoDuration: TimeInterval = 60
        /// Supported video formats
        static let supportedFormats = ["mp4", "mov"]
    }
    
    // MARK: - Image Processing
    enum ImageProcessing {
        /// Maximum image dimension for upload
        static let maxDimension: CGFloat = 1024
        /// JPEG compression quality
        static let compressionQuality: CGFloat = 0.8
        /// Thumbnail size for UI display
        static let thumbnailSize: CGFloat = 200
    }
    
    // MARK: - Storage Keys
    enum StorageKeys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let hasReachedPaywall = "hasReachedPaywall"
        static let hasAcceptedAIDataConsent = "hasAcceptedAIDataConsent"
        static let isPremiumUser = "isPremiumUser"
        static let generationHistory = "generationHistory"
        static let deviceId = "deviceId"
    }
    
    // MARK: - Animation Durations
    enum Animation {
        static let quick: Double = 0.15
        static let standard: Double = 0.3
        static let slow: Double = 0.5
        static let pageTransition: Double = 0.4
    }
    
    // MARK: - History Limits
    enum History {
        static let maxGenerationHistory = 100
    }
}

// MARK: - Bundle Extension

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    var fullVersion: String {
        "\(appVersion) (\(buildNumber))"
    }
}

// MARK: - External URLs

enum ExternalURLs {
    static var privacyPolicy: URL {
        URL(string: Secrets.privacyPolicyUrl)!
    }
    
    static var termsOfUse: URL {
        URL(string: Secrets.termsOfUseUrl)!
    }
    
    static var support: URL {
        let subject = "\(AppConstants.appName) – Support Request"
        let device = UIDevice.current
        let body = """
        
        
        ---
        Please describe your issue above this line.
        
        App: \(AppConstants.appName) v\(Bundle.main.fullVersion)
        iOS: \(device.systemVersion)
        Device: \(device.modelName)
        """
        
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Secrets.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url!
    }
    
    static var appStore: URL {
        URL(string: "https://apps.apple.com/app/id\(Secrets.appStoreId)")!
    }
    
    /// Placeholder App Store link (update when app is published)
    static var appStoreLink: String {
        "https://apps.apple.com/app/id\(Secrets.appStoreId)"
    }
    
    /// Share attribution text
    static var shareAttribution: String {
        "Created with \(AppConstants.appName) \(appStoreLink)"
    }
    
    static var appStoreReview: URL {
        URL(string: "https://apps.apple.com/app/id\(Secrets.appStoreId)?action=write-review")!
    }
}

// MARK: - UIDevice Model Name

extension UIDevice {
    /// Machine identifier mapped to a human-readable model name
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
        // On simulators return the simulated device + "(Simulator)"
        if identifier == "x86_64" || identifier == "arm64" {
            return ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? identifier
        }
        return identifier
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let subscriptionStatusChanged = Notification.Name("subscriptionStatusChanged")
    static let generationStarted = Notification.Name("generationStarted")
    static let generationCompleted = Notification.Name("generationCompleted")
    static let generationFailed = Notification.Name("generationFailed")
}
