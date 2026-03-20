//
//  StorageService.swift
//  AIVideo
//
//  Service for uploading files to Supabase Storage
//

import Foundation
import UIKit

/// Result of uploading an image with smart aspect ratio detection.
struct ImageUploadResult {
    let url: String
    let detectedAspectRatio: String
}

final class StorageService {
    // MARK: - Singleton
    static let shared = StorageService()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Upload portrait image forced to 9:16 and return public URL.
    /// Used by the motion-video (Kling) flow which always requires portrait input.
    func uploadPortrait(_ image: UIImage) async throws -> String {
        let processedImage = image
            .fixedOrientation()
            .croppedTo9by16()
            .resizedToMax(dimension: AppConstants.ImageProcessing.maxDimension)
        
        guard let imageData = processedImage.compressedJPEGData(
            quality: AppConstants.ImageProcessing.compressionQuality
        ) else {
            throw StorageServiceError.imageProcessingFailed
        }
        
        return try await uploadPortraitData(imageData)
    }
    
    /// Upload image, always center-cropped to 9:16.
    /// Trims left/right for wide images, top/bottom for tall ones —
    /// keeping the centre of the frame. Always reports "9:16" so playback
    /// stays full-screen portrait with no black bars.
    func uploadImage(_ image: UIImage) async throws -> ImageUploadResult {
        let processed = image
            .fixedOrientation()
            .croppedTo9by16()
            .resizedToMax(dimension: AppConstants.ImageProcessing.maxDimension)
        
        guard let imageData = processed.compressedJPEGData(
            quality: AppConstants.ImageProcessing.compressionQuality
        ) else {
            throw StorageServiceError.imageProcessingFailed
        }
        
        let url = try await uploadPortraitData(imageData)
        return ImageUploadResult(url: url, detectedAspectRatio: "9:16")
    }
    
    /// Upload portrait image data and return public URL
    /// - Parameter imageData: JPEG data to upload
    /// - Returns: Public URL string for the uploaded image
    func uploadPortraitData(_ imageData: Data) async throws -> String {
        let deviceId = DeviceManager.shared.deviceId
        let filename = "\(deviceId)/\(UUID().uuidString).jpg"
        
        let uploadUrl = URL(string: "\(Secrets.supabaseUrl)/storage/v1/object/\(SupabaseConfig.portraitsBucket)/\(filename)")!
        
        var request = URLRequest(url: uploadUrl)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorStr = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ StorageService: Upload failed with status \((response as? HTTPURLResponse)?.statusCode ?? 0): \(errorStr)")
            throw StorageServiceError.uploadFailed
        }
        
        // Return the public URL
        let publicUrl = SupabaseConfig.storageUrl(
            bucket: SupabaseConfig.portraitsBucket,
            path: filename
        )
        
        print("✅ StorageService: Uploaded portrait to \(publicUrl)")
        return publicUrl.absoluteString
    }
    
    /// Download video data from URL (with caching)
    /// - Parameter urlString: URL string of the video
    /// - Returns: Video data
    func downloadVideo(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw StorageServiceError.invalidUrl
        }
        
        // Check if video is already cached on disk
        if let cachedURL = VideoCacheManager.shared.cachedURL(for: url) {
            if let data = try? Data(contentsOf: cachedURL) {
                print("📦 StorageService: Serving video from cache")
                return data
            }
        }
        
        // Download from network
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw StorageServiceError.downloadFailed
        }
        
        // Cache the downloaded video for future use
        VideoCacheManager.shared.cacheVideoData(data, for: url)
        
        return data
    }
}

// MARK: - Errors

enum StorageServiceError: Error, LocalizedError {
    case imageProcessingFailed
    case uploadFailed
    case downloadFailed
    case invalidUrl
    
    var errorDescription: String? {
        switch self {
        case .imageProcessingFailed:
            return "Failed to process image"
        case .uploadFailed:
            return "Failed to upload file"
        case .downloadFailed:
            return "Failed to download file"
        case .invalidUrl:
            return "Invalid URL"
        }
    }
}
