//
//  VideoTemplate.swift
//  AIVideo
//
//  Model for video template videos fetched from Supabase
//

import Foundation

/// Video template model matching Supabase reference_videos table
struct VideoTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let videoUrl: String
    let thumbnailUrl: String?
    let description: String?
    let durationSeconds: Int?
    let isActive: Bool
    let sortOrder: Int?
    let createdAt: Date?
    let categoryId: UUID?
    
    /// Lightweight preview video URL (trimmed to ~3s) used ONLY for thumbnail cards
    /// on the main screen. This is NEVER used for AI generation — that always uses videoUrl.
    let previewUrl: String?
    
    /// Used to decode the joined table category_id
    private let referenceVideoCategories: [ReferenceVideoCategory]?
    
    struct ReferenceVideoCategory: Codable, Equatable {
        let categoryId: UUID
        enum CodingKeys: String, CodingKey {
            case categoryId = "category_id"
        }
    }
    
    /// The actual category ID, either from the direct column or the joined table
    var effectiveCategoryId: UUID? {
        categoryId ?? referenceVideoCategories?.first?.categoryId
    }
    
    init(id: UUID, name: String, videoUrl: String, thumbnailUrl: String? = nil, description: String? = nil, durationSeconds: Int? = nil, isActive: Bool = true, sortOrder: Int? = nil, createdAt: Date? = nil, categoryId: UUID? = nil, previewUrl: String? = nil, referenceVideoCategories: [ReferenceVideoCategory]? = nil) {
        self.id = id
        self.name = name
        self.videoUrl = videoUrl
        self.thumbnailUrl = thumbnailUrl
        self.description = description
        self.durationSeconds = durationSeconds
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.categoryId = categoryId
        self.previewUrl = previewUrl
        self.referenceVideoCategories = referenceVideoCategories
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case videoUrl = "video_url"
        case thumbnailUrl = "thumbnail_url"
        case description
        case durationSeconds = "duration_seconds"
        case isActive = "is_active"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case categoryId = "category_id"
        case previewUrl = "preview_url"
        case referenceVideoCategories = "reference_video_categories"
    }
    
    /// Formatted duration string (e.g., "15s")
    var formattedDuration: String? {
        guard let seconds = durationSeconds else { return nil }
        return "\(seconds)s"
    }
    
    /// Full URL for the original video (used for AI generation and full-screen playback)
    var fullVideoUrl: URL? {
        URL(string: videoUrl)
    }
    
    /// Full URL for the lightweight preview video (used ONLY for thumbnail cards).
    /// Falls back to the full video URL if no preview is available.
    var fullPreviewUrl: URL? {
        if let preview = previewUrl, let url = URL(string: preview) {
            return url
        }
        return fullVideoUrl
    }
    
    /// Full Supabase storage URL for thumbnail
    var fullThumbnailUrl: URL? {
        guard let thumbnail = thumbnailUrl else { return nil }
        return URL(string: thumbnail)
    }
}

// MARK: - Sample Data for Previews

extension VideoTemplate {
    static let sample = VideoTemplate(
        id: UUID(),
        name: "Viral TikTok Video",
        videoUrl: "https://example.com/video.mp4",
        thumbnailUrl: nil,
        description: "The trending video everyone is doing",
        durationSeconds: 15,
        isActive: true,
        sortOrder: 1,
        createdAt: Date(),
        categoryId: nil,
        previewUrl: nil, referenceVideoCategories: nil
    )
    
    static let samples: [VideoTemplate] = [
        VideoTemplate(
            id: UUID(),
            name: "Hip Hop Groove",
            videoUrl: "https://example.com/hiphop.mp4",
            thumbnailUrl: nil,
            description: "Classic hip hop moves",
            durationSeconds: 20,
            isActive: true,
            sortOrder: 1,
            createdAt: Date(),
            categoryId: nil,
            previewUrl: nil, referenceVideoCategories: nil
        ),
        VideoTemplate(
            id: UUID(),
            name: "K-Pop Challenge",
            videoUrl: "https://example.com/kpop.mp4",
            thumbnailUrl: nil,
            description: "Popular K-pop choreography",
            durationSeconds: 30,
            isActive: true,
            sortOrder: 2,
            createdAt: Date(),
            categoryId: nil,
            previewUrl: nil, referenceVideoCategories: nil
        ),
        VideoTemplate(
            id: UUID(),
            name: "Shuffle Video",
            videoUrl: "https://example.com/shuffle.mp4",
            thumbnailUrl: nil,
            description: "Energetic shuffle moves",
            durationSeconds: 15,
            isActive: true,
            sortOrder: 3,
            createdAt: Date(),
            categoryId: nil,
            previewUrl: nil, referenceVideoCategories: nil
        )
    ]
}
