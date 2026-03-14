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
    /// Placeholder URL when privacy policy or terms are not yet configured.
    /// Apple's standard EULA is commonly used during development.
    private static let placeholderLegalURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    
    static var privacyPolicy: URL {
        let urlString = Secrets.privacyPolicyUrl
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            return placeholderLegalURL
        }
        return url
    }
    
    static var termsOfUse: URL {
        let urlString = Secrets.termsOfUseUrl
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            return placeholderLegalURL
        }
        return url
    }
    
    static var support: URL {
        let email = Secrets.supportEmail
        guard !email.isEmpty else {
            return URL(string: "mailto:support@example.com")!
        }
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
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url ?? URL(string: "mailto:\(email)")!
    }
    
    static var appStore: URL {
        let id = Secrets.appStoreId
        let urlString = id.isEmpty ? "https://apps.apple.com" : "https://apps.apple.com/app/id\(id)"
        return URL(string: urlString) ?? URL(string: "https://apps.apple.com")!
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
        let id = Secrets.appStoreId
        let urlString = id.isEmpty
            ? "https://apps.apple.com"
            : "https://apps.apple.com/app/id\(id)?action=write-review"
        return URL(string: urlString) ?? URL(string: "https://apps.apple.com")!
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
