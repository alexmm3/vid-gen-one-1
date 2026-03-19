//
//  Effect.swift
//  AIVideo
//
//  Model for effects from Supabase effects table
//

import Foundation

/// Effect model matching Supabase effects table (catalog + generation config)
struct Effect: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let description: String?
    let previewVideoUrl: String?
    let thumbnailUrl: String?
    let sampleInputImageUrl: String?
    let categoryId: UUID?
    let isActive: Bool
    let isPremium: Bool
    let sortOrder: Int
    let requiresSecondaryPhoto: Bool
    let systemPromptTemplate: String?
    let provider: String?
    let generationParams: EffectGenerationParams?
    let themeColor: String?
    let createdAt: Date?
    let updatedAt: Date?

    init(id: UUID, name: String, description: String?, previewVideoUrl: String?, thumbnailUrl: String?, sampleInputImageUrl: String? = nil, categoryId: UUID?, isActive: Bool, isPremium: Bool, sortOrder: Int, requiresSecondaryPhoto: Bool, systemPromptTemplate: String?, provider: String?, generationParams: EffectGenerationParams?, themeColor: String?, createdAt: Date?, updatedAt: Date?) {
        self.id = id
        self.name = name
        self.description = description
        self.previewVideoUrl = previewVideoUrl
        self.thumbnailUrl = thumbnailUrl
        self.sampleInputImageUrl = sampleInputImageUrl
        self.categoryId = categoryId
        self.isActive = isActive
        self.isPremium = isPremium
        self.sortOrder = sortOrder
        self.requiresSecondaryPhoto = requiresSecondaryPhoto
        self.systemPromptTemplate = systemPromptTemplate
        self.provider = provider
        self.generationParams = generationParams
        self.themeColor = themeColor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.previewVideoUrl = try c.decodeIfPresent(String.self, forKey: .previewVideoUrl)
        self.thumbnailUrl = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        self.sampleInputImageUrl = try c.decodeIfPresent(String.self, forKey: .sampleInputImageUrl)
        self.categoryId = try c.decodeIfPresent(UUID.self, forKey: .categoryId)
        self.isActive = try c.decode(Bool.self, forKey: .isActive)
        self.isPremium = try c.decode(Bool.self, forKey: .isPremium)
        self.sortOrder = try c.decode(Int.self, forKey: .sortOrder)
        self.requiresSecondaryPhoto = try c.decode(Bool.self, forKey: .requiresSecondaryPhoto)
        self.systemPromptTemplate = try c.decodeIfPresent(String.self, forKey: .systemPromptTemplate)
        self.provider = try c.decodeIfPresent(String.self, forKey: .provider)
        self.generationParams = (try? c.decodeIfPresent(EffectGenerationParams.self, forKey: .generationParams)) ?? nil
        self.themeColor = try c.decodeIfPresent(String.self, forKey: .themeColor)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case previewVideoUrl = "preview_video_url"
        case thumbnailUrl = "thumbnail_url"
        case sampleInputImageUrl = "sample_input_image_url"
        case categoryId = "category_id"
        case isActive = "is_active"
        case isPremium = "is_premium"
        case sortOrder = "sort_order"
        case requiresSecondaryPhoto = "requires_secondary_photo"
        case systemPromptTemplate = "system_prompt_template"
        case provider
        case generationParams = "generation_params"
        case themeColor = "theme_color"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// URL for catalog card preview (video only — effects without video are hidden from catalog)
    var fullPreviewUrl: URL? {
        guard let url = previewVideoUrl else { return nil }
        return URL(string: url)
    }

    /// URL for thumbnail image on cards
    var fullThumbnailUrl: URL? {
        guard let url = thumbnailUrl else { return nil }
        return URL(string: url)
    }

    /// URL for the sample "before" image shown on showcase cards
    var fullSampleInputImageUrl: URL? {
        guard let url = sampleInputImageUrl else { return nil }
        return URL(string: url)
    }

    /// Returns the theme color from the backend, or a stable random color based on the effect's ID for testing
    var displayThemeColor: String {
        if let color = themeColor, !color.isEmpty {
            return color
        }
        // Fallback for testing: stable random color based on ID
        let colors = [
            "#FF2A54", // Vibrant Pink/Red
            "#00E5FF", // Cyan
            "#B400FF", // Purple
            "#FFD500", // Yellow
            "#00FF88", // Neon Green
            "#FF6A00", // Orange
            "#5D00FF", // Deep Violet
            "#FF0055"  // Magenta
        ]
        let index = abs(id.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - generation_params (optional, backend uses it)

struct EffectGenerationParams: Codable, Equatable {
    let duration: Int?
    let aspectRatio: String?

    enum CodingKeys: String, CodingKey {
        case duration
        case aspectRatio = "aspect_ratio"
    }
}

// MARK: - Sample Data

extension Effect {
    static let sample = Effect(
        id: UUID(),
        name: "Portrait Animation",
        description: "Animate your portrait",
        previewVideoUrl: nil,
        thumbnailUrl: nil,
        categoryId: nil,
        isActive: true,
        isPremium: false,
        sortOrder: 0,
        requiresSecondaryPhoto: false,
        systemPromptTemplate: nil,
        provider: "kling",
        generationParams: nil,
        themeColor: "#FF0055",
        createdAt: nil,
        updatedAt: nil
    )

    static let sampleTwoPhotos = Effect(
        id: UUID(),
        name: "Romantic Kiss",
        description: "Two people from photos",
        previewVideoUrl: nil,
        thumbnailUrl: nil,
        categoryId: nil,
        isActive: true,
        isPremium: false,
        sortOrder: 0,
        requiresSecondaryPhoto: true,
        systemPromptTemplate: nil,
        provider: "kling",
        generationParams: nil,
        themeColor: "#00FF88",
        createdAt: nil,
        updatedAt: nil
    )
}
