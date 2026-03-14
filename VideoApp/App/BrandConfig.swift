//
//  BrandConfig.swift
//
//  Single source of truth for app configuration.
//

import Foundation

enum BrandConfig {

    // MARK: - App Identity

    static let appName = "Video-Gen-One"
    static let appTagline = "Turn your photo into a stunning AI video"
    static let appFooterMessage = "Made with AI"

    // MARK: - Supabase

    static let supabaseUrl = "https://oquhbidxsntfrqsloocc.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9xdWhiaWR4c250ZnJxc2xvb2NjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNzQ2NjQsImV4cCI6MjA4ODc1MDY2NH0.yasTip_i88__3Aba0ED1iwO1tjmu7HP9dGDWN9MAaqc"

    static var supabaseFunctionsUrl: String {
        "\(supabaseUrl)/functions/v1"
    }

    // MARK: - App Store Connect
    // TODO: Fill in when App Store Connect entry is created

    static let appStoreId = ""

    static let weeklyProductId = ""
    static let yearlyProductId = ""

    static var allProductIds: [String] {
        [weeklyProductId, yearlyProductId]
    }

    // MARK: - Support & Legal
    // TODO: Fill in with new project URLs and email
    // When empty, ExternalURLs uses placeholders (Apple EULA for legal, support@example.com for email)
    // so the app does not crash. Replace before App Store submission.

    static let supportEmail = ""
    static let privacyPolicyUrl = ""
    static let termsOfUseUrl = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"

    // MARK: - Storage Buckets

    static let portraitsBucket = "portraits"
    static let referenceVideosBucket = "reference-videos"
    static let generatedVideosBucket = "generated-videos"
}
