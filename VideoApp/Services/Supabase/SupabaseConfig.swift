//
//  SupabaseConfig.swift
//  AIVideo
//
//  Supabase configuration and client setup
//

import Foundation
import Supabase

enum SupabaseConfig {
    // MARK: - URLs
    static let projectUrl = URL(string: Secrets.supabaseUrl)!
    static let functionsBaseUrl = Secrets.supabaseFunctionsUrl
    
    // MARK: - Keys
    static let anonKey = Secrets.supabaseAnonKey
    
    // MARK: - Storage Buckets
    static let portraitsBucket = Secrets.portraitsBucket
    static let referenceVideosBucket = Secrets.referenceVideosBucket
    static let generatedVideosBucket = Secrets.generatedVideosBucket
    
    // MARK: - Storage URLs
    
    /// Build public storage URL for a file
    static func storageUrl(bucket: String, path: String) -> URL {
        URL(string: "\(Secrets.supabaseUrl)/storage/v1/object/public/\(bucket)/\(path)")!
    }
    
    // MARK: - Supabase Client (used for Realtime subscriptions)
    static let client = SupabaseClient(
        supabaseURL: projectUrl,
        supabaseKey: anonKey
    )
}

// MARK: - API Endpoints

enum SupabaseEndpoints {
    static var generateMotionVideo: URL {
        URL(string: "\(SupabaseConfig.functionsBaseUrl)/generate-motion-video")!
    }
    
    static var checkGenerationStatus: URL {
        URL(string: "\(SupabaseConfig.functionsBaseUrl)/check-generation-status")!
    }
    
    static var validateAppleSubscription: URL {
        URL(string: "\(SupabaseConfig.functionsBaseUrl)/validate-apple-subscription")!
    }
    
    static var getDeviceGenerations: URL {
        URL(string: "\(SupabaseConfig.functionsBaseUrl)/get-device-generations")!
    }

    static var generateVideo: URL {
        URL(string: "\(SupabaseConfig.functionsBaseUrl)/generate-video")!
    }
}
