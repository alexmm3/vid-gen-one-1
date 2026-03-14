//
//  Generation.swift
//  AIVideo
//
//  Model for video generation jobs and history
//

import Foundation

/// Generation status enum
enum GenerationStatus: String, Codable {
    case pending
    case processing
    case completed
    case failed
    
    var displayText: String {
        switch self {
        case .pending: return "Preparing..."
        case .processing: return "Generating..."
        case .completed: return "Complete"
        case .failed: return "Failed"
        }
    }
    
    var isComplete: Bool {
        self == .completed || self == .failed
    }
}

/// Generation job model (from backend API)
struct GenerationJob: Codable {
    let generationId: String
    let fetchId: Int?
    var status: GenerationStatus
    var outputVideoUrl: String?
    var errorMessage: String?
    
    enum CodingKeys: String, CodingKey {
        case generationId = "generation_id"
        case fetchId = "fetch_id"
        case status
        case outputVideoUrl = "output_video_url"
        case errorMessage = "error_message"
    }
}

/// Local generation history item (persisted on device)
struct LocalGeneration: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let templateName: String
    let templateId: String?
    let inputImageUrl: String
    let outputVideoUrl: String?
    let createdAt: Date
    let isCustomTemplate: Bool
    
    /// Display name for history list
    var displayName: String {
        isCustomTemplate ? "Custom Video" : templateName
    }
    
    /// Whether this generation has a video result
    var hasResult: Bool {
        outputVideoUrl != nil
    }
    
    /// Full URL for the output video
    var fullOutputUrl: URL? {
        guard let urlString = outputVideoUrl else { return nil }
        return URL(string: urlString)
    }
}

// MARK: - Sample Data

extension LocalGeneration {
    static let sample = LocalGeneration(
        id: UUID().uuidString,
        templateName: "Hip Hop Groove",
        templateId: UUID().uuidString,
        inputImageUrl: "https://example.com/input.jpg",
        outputVideoUrl: "https://example.com/output.mp4",
        createdAt: Date(),
        isCustomTemplate: false
    )
    
    static let samples: [LocalGeneration] = [
        LocalGeneration(
            id: UUID().uuidString,
            templateName: "Hip Hop Groove",
            templateId: UUID().uuidString,
            inputImageUrl: "https://example.com/input1.jpg",
            outputVideoUrl: "https://example.com/output1.mp4",
            createdAt: Date().addingTimeInterval(-3600),
            isCustomTemplate: false
        ),
        LocalGeneration(
            id: UUID().uuidString,
            templateName: "K-Pop Challenge",
            templateId: UUID().uuidString,
            inputImageUrl: "https://example.com/input2.jpg",
            outputVideoUrl: "https://example.com/output2.mp4",
            createdAt: Date().addingTimeInterval(-86400),
            isCustomTemplate: false
        ),
        LocalGeneration(
            id: UUID().uuidString,
            templateName: "Custom Video",
            templateId: nil,
            inputImageUrl: "https://example.com/input3.jpg",
            outputVideoUrl: "https://example.com/output3.mp4",
            createdAt: Date().addingTimeInterval(-172800),
            isCustomTemplate: true
        )
    ]
}
