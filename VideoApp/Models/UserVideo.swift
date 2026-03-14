//
//  UserVideo.swift
//  AIVideo
//
//  Model for user-uploaded custom videos
//

import Foundation

// MARK: - Remote User Video (from Supabase)

struct UserVideo: Identifiable, Codable, Equatable {
    let id: UUID
    let deviceId: UUID
    let name: String
    let videoUrl: String
    let thumbnailUrl: String?
    let durationSeconds: Int?
    let fileSizeBytes: Int64?
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
        case name
        case videoUrl = "video_url"
        case thumbnailUrl = "thumbnail_url"
        case durationSeconds = "duration_seconds"
        case fileSizeBytes = "file_size_bytes"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Local User Video (stored on device)

struct LocalUserVideo: Identifiable, Codable, Equatable {
    let id: UUID
    var localVideoPath: String          // Local file path in Documents
    var remoteVideoUrl: String?         // Supabase URL (after upload)
    var localThumbnailPath: String?     // Local thumbnail path
    var remoteThumbnailUrl: String?     // Supabase thumbnail URL
    let name: String
    var durationSeconds: Int?
    var fileSizeBytes: Int64?
    var isUploaded: Bool                // Whether synced to Supabase
    var remoteId: UUID?                 // ID in Supabase after upload
    let createdAt: Date
    var uploadedAt: Date?
    
    init(
        id: UUID = UUID(),
        localVideoPath: String,
        remoteVideoUrl: String? = nil,
        localThumbnailPath: String? = nil,
        remoteThumbnailUrl: String? = nil,
        name: String,
        durationSeconds: Int? = nil,
        fileSizeBytes: Int64? = nil,
        isUploaded: Bool = false,
        remoteId: UUID? = nil,
        createdAt: Date = Date(),
        uploadedAt: Date? = nil
    ) {
        self.id = id
        self.localVideoPath = localVideoPath
        self.remoteVideoUrl = remoteVideoUrl
        self.localThumbnailPath = localThumbnailPath
        self.remoteThumbnailUrl = remoteThumbnailUrl
        self.name = name
        self.durationSeconds = durationSeconds
        self.fileSizeBytes = fileSizeBytes
        self.isUploaded = isUploaded
        self.remoteId = remoteId
        self.createdAt = createdAt
        self.uploadedAt = uploadedAt
    }
    
    /// Get the video URL to use (remote if uploaded, local if file exists)
    var effectiveVideoUrl: URL? {
        if let remote = remoteVideoUrl {
            return URL(string: remote)
        }
        let localURL = URL(fileURLWithPath: localVideoPath)
        guard FileManager.default.fileExists(atPath: localURL.path) else { return nil }
        return localURL
    }
    
    /// Get the thumbnail URL to use
    var effectiveThumbnailUrl: URL? {
        if let remote = remoteThumbnailUrl {
            return URL(string: remote)
        }
        if let local = localThumbnailPath {
            let localURL = URL(fileURLWithPath: local)
            guard FileManager.default.fileExists(atPath: localURL.path) else { return nil }
            return localURL
        }
        return nil
    }
}

// MARK: - Convert to VideoTemplate (for generation)

extension LocalUserVideo {
    func toVideoTemplate() -> VideoTemplate {
        VideoTemplate(
            id: id,
            name: name,
            videoUrl: effectiveVideoUrl?.absoluteString ?? localVideoPath,
            thumbnailUrl: effectiveThumbnailUrl?.absoluteString,
            description: "Your custom video",
            durationSeconds: durationSeconds,
            isActive: true,
            sortOrder: 0,
            createdAt: createdAt,
            categoryId: nil,
            previewUrl: nil
        )
    }
}

extension UserVideo {
    func toVideoTemplate() -> VideoTemplate {
        VideoTemplate(
            id: id,
            name: name,
            videoUrl: videoUrl,
            thumbnailUrl: thumbnailUrl,
            description: "Your custom video",
            durationSeconds: durationSeconds,
            isActive: isActive,
            sortOrder: 0,
            createdAt: createdAt,
            categoryId: nil,
            previewUrl: nil
        )
    }
}
