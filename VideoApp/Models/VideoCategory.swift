//
//  VideoCategory.swift
//  AIVideo
//
//  Model for video categories
//

import Foundation

struct VideoCategory: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let name: String
    let displayName: String
    let sortOrder: Int
    let icon: String?
    let isActive: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayName = "display_name"
        case sortOrder = "sort_order"
        case icon
        case isActive = "is_active"
    }
}

// MARK: - Sample Data

extension VideoCategory {
    static let samples: [VideoCategory] = [
        VideoCategory(id: UUID(), name: "trending", displayName: "Trending", sortOrder: 1, icon: "flame.fill", isActive: true),
        VideoCategory(id: UUID(), name: "babies", displayName: "Babies", sortOrder: 2, icon: "face.smiling", isActive: true),
        VideoCategory(id: UUID(), name: "celebrities", displayName: "Celebrities", sortOrder: 3, icon: "star.fill", isActive: true),
        VideoCategory(id: UUID(), name: "other", displayName: "Other", sortOrder: 4, icon: "square.grid.2x2", isActive: true)
    ]
}
