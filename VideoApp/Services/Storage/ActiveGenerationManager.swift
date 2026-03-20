//
//  ActiveGenerationManager.swift
//  AIVideo
//
//  Manages persistent state for active video generations
//  Allows generations to continue even if user leaves the screen or app
//

import Foundation
import Combine
import Supabase
import Realtime

/// Represents a generation that is currently in progress
struct PendingGeneration: Codable, Equatable {
    let generationId: String
    let fetchId: Int?
    let templateName: String
    let templateId: String?
    let inputImageUrl: String
    let referenceVideoUrl: String
    let startedAt: Date
    var lastPolledAt: Date?
    var pollCount: Int
    var status: String  // "uploading", "processing", "polling"
    
    var isExpired: Bool {
        // If it's still uploading after 5 minutes, it probably crashed/failed silently
        if status == "uploading" {
            return Date().timeIntervalSince(startedAt) > 300
        }
        // Consider expired after 30 minutes (backend may take a while for complex generations)
        // This is a safety net for abandoned generations, not a timeout
        return Date().timeIntervalSince(startedAt) > 1800
    }
    
    var displayStatus: String {
        switch status {
        case "uploading": return "Uploading..."
        case "processing", "polling": return "Generating..."
        default: return "Processing..."
        }
    }
}

/// Result of checking a pending generation
enum PendingGenerationResult {
    case stillProcessing(pollCount: Int)
    case completed(outputUrl: String)
    case failed(error: String)
    case expired
}

/// Result of a completed generation (for toast display)
struct CompletedGenerationInfo: Equatable {
    let generationId: String
    let templateName: String
    let outputUrl: String
}

@MainActor
final class ActiveGenerationManager: ObservableObject {
    // MARK: - Singleton
    static let shared = ActiveGenerationManager()
    
    // MARK: - Published Properties
    @Published private(set) var pendingGeneration: PendingGeneration?
    @Published private(set) var isCheckingPending = false
    @Published private(set) var lastCompletedGeneration: CompletedGenerationInfo?
    
    // MARK: - Private
    private let storageKey = "activeGeneration"
    private let generationService = GenerationService.shared
    private let historyService = GenerationHistoryService.shared
    private var pollingTask: Task<Void, Never>?
    
    // MARK: - Realtime
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeObservationToken: ObservationToken?
    
    // MARK: - Initialization
    
    private init() {
        loadPendingGeneration()
    }
    
    // MARK: - Public Methods
    
    /// Start tracking a generation that is currently uploading
    func startUploading(
        templateName: String,
        templateId: String?,
        referenceVideoUrl: String
    ) {
        let pending = PendingGeneration(
            generationId: "uploading-\(UUID().uuidString)",
            fetchId: nil,
            templateName: templateName,
            templateId: templateId,
            inputImageUrl: "", // Not uploaded yet
            referenceVideoUrl: referenceVideoUrl,
            startedAt: Date(),
            lastPolledAt: nil,
            pollCount: 0,
            status: "uploading"
        )
        
        pendingGeneration = pending
        savePendingGeneration()
        print("✅ ActiveGenerationManager: Started tracking upload phase")
    }
    
    /// Update an uploading generation with the real ID from the backend
    func transitionToProcessing(
        generationId: String,
        fetchId: Int?,
        inputImageUrl: String
    ) {
        guard let pending = pendingGeneration, pending.status == "uploading" else { return }
        
        let updated = PendingGeneration(
            generationId: generationId,
            fetchId: fetchId,
            templateName: pending.templateName,
            templateId: pending.templateId,
            inputImageUrl: inputImageUrl,
            referenceVideoUrl: pending.referenceVideoUrl,
            startedAt: pending.startedAt,
            lastPolledAt: Date(),
            pollCount: 0,
            status: "processing"
        )
        
        pendingGeneration = updated
        savePendingGeneration()
        
        print("✅ ActiveGenerationManager: Transitioned to processing \(generationId)")
        
        Analytics.track(.generationPollingStarted(generationId: generationId))
        
        NotificationCenter.default.post(
            name: .generationStarted,
            object: nil,
            userInfo: ["generationId": generationId]
        )
    }
    
    /// Start tracking a new generation
    func startGeneration(
        generationId: String,
        fetchId: Int?,
        templateName: String,
        templateId: String?,
        inputImageUrl: String,
        referenceVideoUrl: String
    ) {
        let pending = PendingGeneration(
            generationId: generationId,
            fetchId: fetchId,
            templateName: templateName,
            templateId: templateId,
            inputImageUrl: inputImageUrl,
            referenceVideoUrl: referenceVideoUrl,
            startedAt: Date(),
            lastPolledAt: nil,
            pollCount: 0,
            status: "processing"
        )
        
        pendingGeneration = pending
        savePendingGeneration()
        
        print("✅ ActiveGenerationManager: Started tracking generation \(generationId)")
        
        // Track analytics
        Analytics.track(.generationPollingStarted(generationId: generationId))
        
        // Post notification
        NotificationCenter.default.post(
            name: .generationStarted,
            object: nil,
            userInfo: ["generationId": generationId]
        )
    }
    
    /// Start polling in the background (non-blocking)
    /// Call this after startGeneration() to poll without blocking the UI
    func startBackgroundPolling() {
        // Cancel any existing polling task
        pollingTask?.cancel()
        
        guard pendingGeneration != nil else {
            print("⚠️ ActiveGenerationManager: No pending generation to poll")
            return
        }
        
        print("🔄 ActiveGenerationManager: Starting background polling")
        
        // Start slow fallback polling in a detached task (safety net)
        pollingTask = Task { [weak self] in
            guard let self = self else { return }
            
            let result = await self.pollUntilComplete()
            
            // Result is already handled in pollUntilComplete/completeGeneration
            switch result {
            case .completed(let outputUrl):
                print("✅ ActiveGenerationManager: Background polling completed with URL: \(outputUrl)")
            case .failed(let error):
                print("❌ ActiveGenerationManager: Background polling failed: \(error)")
            case .expired:
                print("⚠️ ActiveGenerationManager: Background polling expired")
            case .stillProcessing:
                print("ℹ️ ActiveGenerationManager: Background polling cancelled or interrupted")
            }
        }
    }
    
    /// Cancel background polling (e.g., when user manually cancels)
    func cancelBackgroundPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        unsubscribeFromRealtime()
        print("✅ ActiveGenerationManager: Cancelled background polling")
    }
    
    /// Check if background polling is active
    var isPollingActive: Bool {
        pollingTask != nil && !pollingTask!.isCancelled
    }
    
    /// Update the status of the current generation
    func updateStatus(_ status: String) {
        guard var pending = pendingGeneration else { return }
        pending = PendingGeneration(
            generationId: pending.generationId,
            fetchId: pending.fetchId,
            templateName: pending.templateName,
            templateId: pending.templateId,
            inputImageUrl: pending.inputImageUrl,
            referenceVideoUrl: pending.referenceVideoUrl,
            startedAt: pending.startedAt,
            lastPolledAt: Date(),
            pollCount: pending.pollCount + 1,
            status: status
        )
        pendingGeneration = pending
        savePendingGeneration()
    }
    
    /// Mark generation as completed
    func completeGeneration(outputUrl: String) {
        guard let pending = pendingGeneration else { return }
        
        // Save to history
        historyService.saveGeneration(
            templateName: pending.templateName,
            templateId: pending.templateId,
            inputImageUrl: pending.inputImageUrl,
            outputVideoUrl: outputUrl,
            isCustomTemplate: pending.templateId == nil
        )
        
        // Store completed info for toast/UI
        lastCompletedGeneration = CompletedGenerationInfo(
            generationId: pending.generationId,
            templateName: pending.templateName,
            outputUrl: outputUrl
        )
        
        print("✅ ActiveGenerationManager: Generation completed \(pending.generationId)")
        
        // Post notification (ToastManager listens to this)
        NotificationCenter.default.post(
            name: .generationCompleted,
            object: nil,
            userInfo: [
                "generationId": pending.generationId,
                "outputUrl": outputUrl,
                "templateName": pending.templateName
            ]
        )
        
        // Clear pending
        clearPendingGeneration()
        
        // Haptic feedback for completion
        HapticManager.shared.success()
    }
    
    /// Mark generation as failed
    func failGeneration(error: String) {
        guard let pending = pendingGeneration else { return }
        
        print("❌ ActiveGenerationManager: Generation failed \(pending.generationId): \(error)")
        
        // Post notification
        NotificationCenter.default.post(
            name: .generationFailed,
            object: nil,
            userInfo: [
                "generationId": pending.generationId,
                "error": error
            ]
        )
        
        // Clear pending
        clearPendingGeneration()
    }
    
    /// Clear pending generation (on completion or manual clear)
    func clearPendingGeneration() {
        pollingTask?.cancel()
        pollingTask = nil
        unsubscribeFromRealtime()
        pendingGeneration = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
        print("✅ ActiveGenerationManager: Cleared pending generation")
    }
    
    /// Clear last completed generation (after user has seen it)
    func clearLastCompletedGeneration() {
        lastCompletedGeneration = nil
    }
    
    /// Check and resume any pending generation (call on app launch)
    func checkAndResumePendingGeneration() async -> PendingGenerationResult? {
        guard let pending = pendingGeneration else {
            return nil
        }
        
        // Check if expired
        if pending.isExpired {
            print("⚠️ ActiveGenerationManager: Pending generation expired")
            Analytics.track(.generationExpired(generationId: pending.generationId))
            clearPendingGeneration()
            return .expired
        }
        
        // If it's still in the upload phase, we can't check the backend yet
        if pending.status == "uploading" {
            return .stillProcessing(pollCount: pending.pollCount)
        }
        
        isCheckingPending = true
        defer { isCheckingPending = false }
        
        print("🔄 ActiveGenerationManager: Checking pending generation \(pending.generationId)")
        
        // Track polling resumed (when coming back from background)
        if pending.pollCount > 0 {
            Analytics.track(.generationPollingResumed(generationId: pending.generationId, pollCount: pending.pollCount))
        }
        
        do {
            // Always pass fetchId so the edge function can poll ModelsLab and update the DB.
            // The edge function now always returns our DB record (not the raw ModelsLab response),
            // ensuring a consistent, parseable response format with correct field types.
            let job = try await generationService.checkStatus(
                generationId: pending.generationId,
                fetchId: pending.fetchId
            )
            
            switch job.status {
            case .completed:
                if let outputUrl = job.outputVideoUrl {
                    completeGeneration(outputUrl: outputUrl)
                    return .completed(outputUrl: outputUrl)
                } else {
                    failGeneration(error: "Completed but no output URL")
                    return .failed(error: "No output URL")
                }
                
            case .failed:
                let error = ClientSafeErrorMessage.sanitizeUserFacingNonEmpty(job.errorMessage)
                failGeneration(error: error)
                return .failed(error: error)
                
            case .pending, .processing:
                updateStatus("polling")
                return .stillProcessing(pollCount: pending.pollCount + 1)
            }
        } catch {
            print("❌ ActiveGenerationManager: Error checking status - \(error)")
            // Don't clear on network error - might be temporary
            return .stillProcessing(pollCount: pending.pollCount)
        }
    }
    
    /// Poll until completion (fallback safety net alongside Realtime)
    /// Each poll calls the edge function with fetchId, which polls ModelsLab,
    /// updates our DB, and returns the DB record. This ensures both the DB
    /// stays fresh AND the client gets a parseable response.
    /// No client-side timeout - relies on backend status (completed/failed) or expiry safety net.
    func pollUntilComplete() async -> PendingGenerationResult {
        guard pendingGeneration != nil else {
            return .failed(error: "No pending generation")
        }
        
        // 15-second interval: Realtime can provide instant detection,
        // this fallback ensures we never miss completion even if Realtime hiccups.
        // 3x fewer API calls than the previous 5-second interval.
        let pollInterval: UInt64 = 15_000_000_000  // 15 seconds
        
        // Poll indefinitely until backend returns completed/failed or generation expires
        while true {
            // Check if generation was cleared (user cancelled or completed via Realtime)
            guard pendingGeneration != nil else {
                return .failed(error: "Generation was cancelled")
            }
            
            // Wait before polling
            try? await Task.sleep(nanoseconds: pollInterval)
            
            if let result = await checkAndResumePendingGeneration() {
                switch result {
                case .stillProcessing:
                    // Continue polling - no client-side timeout
                    continue
                case .completed, .failed, .expired:
                    return result
                }
            }
        }
    }
    
    /// Check if there's an active generation
    var hasActiveGeneration: Bool {
        pendingGeneration != nil
    }
    
    /// Check if a new generation can start.
    /// Auto-clears expired generations so the user is never stuck forever.
    func canStartNewGeneration() -> Bool {
        guard let pending = pendingGeneration else { return true }
        
        if pending.isExpired {
            print("⚠️ ActiveGenerationManager: Auto-clearing expired generation \(pending.generationId)")
            Analytics.track(.generationExpired(generationId: pending.generationId))
            clearPendingGeneration()
            return true
        }
        
        return false
    }
    
    // MARK: - Realtime Subscription
    
    /// Realtime is intentionally disabled because generations are no longer
    /// readable by the anon client after RLS hardening.
    func subscribeToGenerationUpdates(generationId: String) {
        unsubscribeFromRealtime()
        print("📡 ActiveGenerationManager: Realtime disabled for generation \(generationId)")
    }
    
    /// Unsubscribe from Realtime updates and clean up resources
    func unsubscribeFromRealtime() {
        if let channel = realtimeChannel {
            Task {
                await channel.unsubscribe()
                print("📡 ActiveGenerationManager: Realtime channel unsubscribed")
            }
        }
        realtimeObservationToken = nil
        realtimeChannel = nil
    }
    
    /// Handle an incoming Realtime UPDATE event from the generations table
    private func handleRealtimeUpdate(_ record: [String: AnyJSON]) {
        // Extract status from the record
        guard let statusValue = record["status"] else {
            print("⚠️ ActiveGenerationManager: Realtime update missing status field")
            return
        }
        
        let status: String
        switch statusValue {
        case .string(let s):
            status = s
        default:
            print("⚠️ ActiveGenerationManager: Realtime status not a string: \(statusValue)")
            return
        }
        
        print("📡 ActiveGenerationManager: Realtime update received - status: \(status)")
        
        // Guard against processing updates after generation was already handled
        guard pendingGeneration != nil else {
            print("ℹ️ ActiveGenerationManager: Ignoring Realtime update - no pending generation")
            return
        }
        
        switch status {
        case "completed":
            // Extract output_video_url
            if let urlValue = record["output_video_url"],
               case .string(let outputUrl) = urlValue {
                print("📡 ActiveGenerationManager: Realtime detected completion - \(outputUrl)")
                completeGeneration(outputUrl: outputUrl)
            } else {
                print("⚠️ ActiveGenerationManager: Realtime completed but no output_video_url")
                // Don't fail here - let the fallback polling handle it
            }
            
        case "failed":
            let errorMessage: String
            if let errorValue = record["error_message"],
               case .string(let msg) = errorValue {
                errorMessage = ClientSafeErrorMessage.sanitizeUserFacingNonEmpty(msg)
            } else {
                errorMessage = ClientSafeErrorMessage.genericGeneration
            }
            print("📡 ActiveGenerationManager: Realtime detected failure - \(errorMessage)")
            failGeneration(error: errorMessage)
            
        default:
            // Still processing - nothing to do, let it continue
            break
        }
    }
    
    // MARK: - Private Methods
    
    private func loadPendingGeneration() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            pendingGeneration = try decoder.decode(PendingGeneration.self, from: data)
            print("✅ ActiveGenerationManager: Loaded pending generation \(pendingGeneration?.generationId ?? "nil")")
        } catch {
            print("❌ ActiveGenerationManager: Failed to load pending generation - \(error)")
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }
    
    private func savePendingGeneration() {
        guard let pending = pendingGeneration else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(pending)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("❌ ActiveGenerationManager: Failed to save pending generation - \(error)")
        }
    }
}

// MARK: - Notification Names
// Note: Notification.Name extensions for generation events are defined in Constants.swift
