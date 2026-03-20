//
//  SubscriptionValidationService.swift
//  AIVideo
//
//  Service for validating Apple subscriptions with backend
//  Based on iOS-API-Integration.md
//

import Foundation

final class SubscriptionValidationService {
    // MARK: - Singleton
    static let shared = SubscriptionValidationService()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Validate / register Apple subscription with backend
    /// - Parameters:
    ///   - originalTransactionId: Apple's original transaction ID (from StoreKit 2)
    ///   - signedTransactionInfo: Verified StoreKit JWS for server-side Apple verification
    ///   - useSandbox: Whether this is a sandbox / TestFlight transaction
    /// - Returns: Validation response with subscription details
    func validateSubscription(
        originalTransactionId: String,
        signedTransactionInfo: String? = nil,
        useSandbox: Bool = false
    ) async throws -> ValidationResult {
        let url = SupabaseEndpoints.validateAppleSubscription
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        var body: [String: Any] = [
            "device_id": DeviceManager.shared.backendDeviceId,
            "original_transaction_id": originalTransactionId,
            "use_sandbox": useSandbox
        ]
        
        if let signedTransactionInfo = signedTransactionInfo {
            body["signed_transaction_info"] = signedTransactionInfo
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ValidationError.requestFailed
        }
        
        let result: ValidationResponse
        do {
            result = try JSONDecoder().decode(ValidationResponse.self, from: data)
        } catch {
            throw ValidationError.invalidResponse
        }
        
        if result.valid {
            print("✅ SubscriptionValidation: Valid subscription")
            return ValidationResult(
                isValid: true,
                productId: result.subscription?.productId,
                expiresAt: result.subscription?.expiresAt,
                generationsRemaining: result.subscription?.generationsRemaining,
                generationLimit: result.subscription?.plan?.generationLimit,
                planName: result.subscription?.plan?.planName
            )
        } else {
            print("⚠️ SubscriptionValidation: Invalid - \(result.error ?? "unknown")")
            return ValidationResult(
                isValid: false,
                productId: nil,
                expiresAt: nil,
                generationsRemaining: nil,
                generationLimit: nil,
                planName: nil
            )
        }
    }
}

// MARK: - Result Types

struct ValidationResult {
    let isValid: Bool
    let productId: String?
    let expiresAt: String?
    let generationsRemaining: Int?
    let generationLimit: Int?
    let planName: String?
}

// MARK: - Errors

enum ValidationError: Error, LocalizedError, Equatable {
    case requestFailed
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Failed to validate subscription"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

// MARK: - Response Models

private struct ValidationResponse: Decodable {
    let valid: Bool
    let error: String?
    let environment: String?
    let subscription: SubscriptionInfo?
    
    struct SubscriptionInfo: Decodable {
        let productId: String?
        let originalTransactionId: String?
        let expiresAt: String?
        let status: Int
        let environment: String
        let plan: PlanInfo?
        let generationsRemaining: Int?
        
        enum CodingKeys: String, CodingKey {
            case productId = "product_id"
            case originalTransactionId = "original_transaction_id"
            case expiresAt = "expires_at"
            case status, environment, plan
            case generationsRemaining = "generations_remaining"
        }
    }
    
    struct PlanInfo: Decodable {
        let planId: String
        let planName: String
        let generationLimit: Int
        let periodDays: Int?
        
        enum CodingKeys: String, CodingKey {
            case planId = "plan_id"
            case planName = "plan_name"
            case generationLimit = "generation_limit"
            case periodDays = "period_days"
        }
    }
}
