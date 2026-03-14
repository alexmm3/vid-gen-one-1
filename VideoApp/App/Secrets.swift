//
//  Secrets.swift
//
//  Thin compatibility layer — all values come from BrandConfig.
//  Existing code references Secrets.* so this avoids a mass refactor.
//  New code should reference BrandConfig directly.
//

import Foundation

enum Secrets {
    // MARK: - Supabase Configuration
    static let supabaseUrl = BrandConfig.supabaseUrl
    static let supabaseAnonKey = BrandConfig.supabaseAnonKey
    static let supabaseFunctionsUrl = BrandConfig.supabaseFunctionsUrl
    
    // MARK: - Storage Buckets
    static let portraitsBucket = BrandConfig.portraitsBucket
    static let referenceVideosBucket = BrandConfig.referenceVideosBucket
    static let generatedVideosBucket = BrandConfig.generatedVideosBucket
    
    // MARK: - App Store Configuration
    static let appStoreId = BrandConfig.appStoreId
    static let weeklyProductId = BrandConfig.weeklyProductId
    static let yearlyProductId = BrandConfig.yearlyProductId
    
    // MARK: - Support & Legal
    static let supportEmail = BrandConfig.supportEmail
    static let privacyPolicyUrl = BrandConfig.privacyPolicyUrl
    static let termsOfUseUrl = BrandConfig.termsOfUseUrl
}
