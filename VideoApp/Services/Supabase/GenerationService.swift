//
//  GenerationService.swift
//  AIVideo
//
//  Service for video generation API calls
//  Based on iOS-API-Integration.md
//

import Foundation

@MainActor
final class GenerationService: ObservableObject {
    // MARK: - Singleton
    static let shared = GenerationService()
    
    // MARK: - Published Properties
    @Published private(set) var currentJob: GenerationJob?
    @Published private(set) var isGenerating = false
    @Published private(set) var error: GenerationServiceError?
    
    // MARK: - Private
    private let session = URLSession.shared
    private var pollTask: Task<Void, Never>?
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start video generation
    /// Uses "video" character_orientation mode which:
    /// - Copies motion from reference video to the portrait
    /// - Keeps the environment/background from the portrait
    /// - Supports up to 30 second videos (vs 10s for "image" mode)
    /// - Always copies audio from reference video
    ///
    /// - Parameters:
    ///   - portraitUrl: Public URL of the uploaded portrait image
    ///   - referenceVideoUrl: URL of the video template video
    /// - Returns: GenerationJob with initial status
    func generateVideo(
        portraitUrl: String,
        referenceVideoUrl: String
    ) async throws -> GenerationJob {
        // Safety check: reject local file paths before hitting the network
        guard referenceVideoUrl.hasPrefix("https://") || referenceVideoUrl.hasPrefix("http://") else {
            throw GenerationServiceError.serverError(
                "Video must be uploaded before generation. The reference video URL is not a valid public URL."
            )
        }
        guard portraitUrl.hasPrefix("https://") || portraitUrl.hasPrefix("http://") else {
            throw GenerationServiceError.serverError(
                "Portrait must be uploaded before generation."
            )
        }
        
        isGenerating = true
        error = nil
        
        let url = SupabaseEndpoints.generateMotionVideo
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = AppConstants.API.requestTimeout

        // character_orientation: "video" = motion from video applied to portrait (30s limit)
        // character_orientation: "image" = would use image orientation (10s limit) - NOT USED
        // copy_audio: true = always copy audio from reference video
        let body: [String: Any] = [
            "device_id": DeviceManager.shared.backendDeviceId,
            "init_image_url": portraitUrl,
            "reference_video_url": referenceVideoUrl,
            "character_orientation": "video",
            "copy_audio": true
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GenerationServiceError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let result = try JSONDecoder().decode(GenerateResponse.self, from: data)
            let job = GenerationJob(
                generationId: result.generationId,
                fetchId: result.apiResponse?.id,
                status: .processing,
                outputVideoUrl: nil,
                errorMessage: nil
            )
            currentJob = job
            print("✅ GenerationService: Started generation \(result.generationId)")
            return job
            
        case 403:
            let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)
            if errorResponse.errorCode == "NO_SUBSCRIPTION" || errorResponse.errorCode == "SUBSCRIPTION_EXPIRED" {
                throw GenerationServiceError.noSubscription
            }
            throw GenerationServiceError.serverError(errorResponse.error)
            
        case 429:
            let limitResponse = try JSONDecoder().decode(LimitErrorResponse.self, from: data)
            throw GenerationServiceError.limitReached(
                limit: limitResponse.limit,
                used: limitResponse.used,
                remaining: limitResponse.remaining
            )
            
        default:
            let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw GenerationServiceError.serverError(errorResponse?.error ?? "Unknown error (status \(httpResponse.statusCode))")
        }
    }

    /// Start effect-based video generation (generate-video backend)
    func executeEffect(
        effectId: String,
        primaryImageUrl: String,
        secondaryImageUrl: String?,
        userPrompt: String?,
        detectedAspectRatio: String? = nil
    ) async throws -> GenerationJob {
        guard primaryImageUrl.hasPrefix("https://") || primaryImageUrl.hasPrefix("http://") else {
            throw GenerationServiceError.serverError("Portrait must be uploaded before generation.")
        }
        if let secondary = secondaryImageUrl, !secondary.isEmpty {
            guard secondary.hasPrefix("https://") || secondary.hasPrefix("http://") else {
                throw GenerationServiceError.serverError("Second image must be uploaded before generation.")
            }
        }

        isGenerating = true
        error = nil

        let url = SupabaseEndpoints.generateVideo
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = AppConstants.API.requestTimeout

        var body: [String: Any] = [
            "device_id": DeviceManager.shared.backendDeviceId,
            "effect_id": effectId,
            "input_image_url": primaryImageUrl
        ]
        if let secondary = secondaryImageUrl, !secondary.isEmpty {
            body["secondary_image_url"] = secondary
        }
        if let prompt = userPrompt, !prompt.isEmpty {
            body["user_prompt"] = prompt
        }
        if let aspectRatio = detectedAspectRatio {
            body["detected_aspect_ratio"] = aspectRatio
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GenerationServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let result = try JSONDecoder().decode(GenerateResponse.self, from: data)
            let job = GenerationJob(
                generationId: result.generationId,
                fetchId: result.apiResponse?.id,
                status: .processing,
                outputVideoUrl: nil,
                errorMessage: nil
            )
            currentJob = job
            print("✅ GenerationService: Started effect generation \(result.generationId)")
            return job
        case 403:
            let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)
            if errorResponse.errorCode == "NO_SUBSCRIPTION" || errorResponse.errorCode == "SUBSCRIPTION_EXPIRED" {
                throw GenerationServiceError.noSubscription
            }
            throw GenerationServiceError.serverError(errorResponse.error)
        case 429:
            let limitResponse = try JSONDecoder().decode(LimitErrorResponse.self, from: data)
            throw GenerationServiceError.limitReached(
                limit: limitResponse.limit,
                used: limitResponse.used,
                remaining: limitResponse.remaining
            )
        default:
            let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw GenerationServiceError.serverError(errorResponse?.error ?? "Unknown error (status \(httpResponse.statusCode))")
        }
    }

    /// Check generation status
    /// - Parameters:
    ///   - generationId: UUID of the generation
    ///   - fetchId: Optional API fetch ID for status update
    /// - Returns: Updated GenerationJob
    func checkStatus(generationId: String, fetchId: Int?) async throws -> GenerationJob {
        var urlComponents = URLComponents(url: SupabaseEndpoints.checkGenerationStatus, resolvingAgainstBaseURL: false)!
        
        var queryItems = [
            URLQueryItem(name: "generation_id", value: generationId),
            URLQueryItem(name: "device_id", value: DeviceManager.shared.backendDeviceId),
        ]
        if let fetchId = fetchId {
            queryItems.append(URLQueryItem(name: "fetch_id", value: String(fetchId)))
        }
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            throw GenerationServiceError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GenerationServiceError.statusCheckFailed
        }
        
        let result = try JSONDecoder().decode(StatusResponse.self, from: data)
        
        let job = GenerationJob(
            generationId: generationId,
            fetchId: fetchId,
            status: GenerationStatus(rawValue: result.status) ?? .processing,
            outputVideoUrl: result.outputVideoUrl,
            errorMessage: ClientSafeErrorMessage.sanitizeUserFacing(result.errorMessage)
        )
        
        currentJob = job
        return job
    }
    
    /// Poll for completion with automatic retries
    /// NOTE: This method is deprecated - use ActiveGenerationManager.pollUntilComplete() instead
    /// which has no client-side timeout and persists state across app restarts
    /// - Parameter job: Initial GenerationJob
    /// - Returns: Completed GenerationJob
    func pollUntilComplete(job: GenerationJob) async throws -> GenerationJob {
        var currentJob = job
        let pollInterval: UInt64 = UInt64(AppConstants.API.pollInterval * 1_000_000_000)
        var attempt = 0
        
        // Poll indefinitely until backend returns completed/failed
        while true {
            try await Task.sleep(nanoseconds: pollInterval)
            attempt += 1
            
            print("🔄 GenerationService: Poll attempt \(attempt)")
            
            currentJob = try await checkStatus(
                generationId: currentJob.generationId,
                fetchId: currentJob.fetchId
            )
            
            switch currentJob.status {
            case .completed:
                isGenerating = false
                print("✅ GenerationService: Generation completed")
                return currentJob
                
            case .failed:
                isGenerating = false
                throw GenerationServiceError.generationFailed(
                    currentJob.errorMessage ?? "Unknown error"
                )
                
            case .pending, .processing:
                // Continue polling - no client-side timeout
                continue
            }
        }
    }
    
    /// Fetch completed generations for this device from the server.
    /// Used to sync local history with the server (source of truth).
    func fetchDeviceHistory() async throws -> [RemoteGeneration] {
        var urlComponents = URLComponents(url: SupabaseEndpoints.getDeviceGenerations, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [
            URLQueryItem(name: "device_id", value: DeviceManager.shared.backendDeviceId)
        ]
        
        guard let url = urlComponents.url else {
            throw GenerationServiceError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GenerationServiceError.serverError("Failed to fetch device history")
        }
        
        let result = try JSONDecoder().decode(DeviceHistoryResponse.self, from: data)
        return result.generations
    }
    
    /// Cancel current polling
    func cancelPolling() {
        pollTask?.cancel()
        pollTask = nil
        isGenerating = false
    }
    
    /// Reset service state
    func reset() {
        cancelPolling()
        currentJob = nil
        error = nil
    }
}

// MARK: - Error Types

enum GenerationServiceError: Error, LocalizedError {
    case noSubscription
    case limitReached(limit: Int, used: Int, remaining: Int)
    case serverError(String)
    case networkError(Error)
    case invalidResponse
    case invalidRequest
    case statusCheckFailed
    case generationFailed(String)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .noSubscription:
            return "Subscription required to generate videos"
        case .limitReached(let limit, _, let remaining):
            return "Generation limit reached (\(limit) per period). \(remaining) remaining."
        case .serverError(let message):
            return ClientSafeErrorMessage.sanitizeUserFacingNonEmpty(message)
        case .networkError(let error):
            return ClientSafeErrorMessage.sanitizeUserFacingNonEmpty(error.localizedDescription)
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidRequest:
            return "Invalid request"
        case .statusCheckFailed:
            return "Failed to check generation status"
        case .generationFailed(let message):
            return ClientSafeErrorMessage.sanitizeUserFacingNonEmpty(message)
        case .timeout:
            return "Generation timed out. Please try again."
        }
    }
    
    var isSubscriptionError: Bool {
        if case .noSubscription = self { return true }
        return false
    }
    
    var isLimitError: Bool {
        if case .limitReached = self { return true }
        return false
    }
}

// MARK: - Response Models

private struct GenerateResponse: Decodable {
    let success: Bool
    let generationId: String
    let status: String
    let apiResponse: APIResponse?
    let requestId: String?
    
    struct APIResponse: Decodable {
        let status: String?
        let id: Int?
        let eta: Int?
    }
    
    enum CodingKeys: String, CodingKey {
        case success
        case generationId = "generation_id"
        case status
        case apiResponse = "api_response"
        case requestId = "request_id"
    }
}

private struct StatusResponse: Decodable {
    let id: String?
    let status: String
    let outputVideoUrl: String?
    let errorMessage: String?
    let createdAt: String?
    let updatedAt: String?
    let pollCount: Int?
    let requestId: String?
    
    enum CodingKeys: String, CodingKey {
        case id, status
        case outputVideoUrl = "output_video_url"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case pollCount = "poll_count"
        case requestId = "request_id"
    }
}

private struct ErrorResponse: Decodable {
    let error: String
    let errorCode: String?
    let requestId: String?
    
    enum CodingKeys: String, CodingKey {
        case error
        case errorCode = "error_code"
        case requestId = "request_id"
    }
}

/// A generation record returned from the server's get-device-generations endpoint.
struct RemoteGeneration: Decodable {
    let id: String
    let status: String
    let outputVideoUrl: String?
    let inputImageUrl: String?
    let referenceVideoUrl: String?
    /// Effect name when generation was effect-based (backend may include this)
    let effectName: String?
    let effectId: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, status
        case outputVideoUrl = "output_video_url"
        case inputImageUrl = "input_image_url"
        case referenceVideoUrl = "reference_video_url"
        case effectName = "effect_name"
        case effectId = "effect_id"
        case createdAt = "created_at"
    }
}

private struct DeviceHistoryResponse: Decodable {
    let generations: [RemoteGeneration]
    let count: Int
}

private struct LimitErrorResponse: Decodable {
    let error: String
    let errorCode: String
    let limit: Int
    let periodDays: Int
    let used: Int
    let remaining: Int
    let requestId: String?
    
    enum CodingKeys: String, CodingKey {
        case error
        case errorCode = "error_code"
        case limit
        case periodDays = "period_days"
        case used, remaining
        case requestId = "request_id"
    }
}
