//
//  GenerationViewModel.swift
//  AIVideo
//
//  ViewModel for managing the full generation flow
//  Uses ActiveGenerationManager for persistent state and background polling
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class GenerationViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedPhoto: UIImage?
    @Published var isGenerating = false
    @Published var progress: GenerationProgress = .idle
    @Published var showResult = false
    @Published var outputVideoUrl: String?
    @Published var error: GenerationServiceError?
    @Published var showPaywall = false
    
    /// Indicates generation has been submitted to backend and user can dismiss
    /// This is different from isGenerating - submitted means upload/submit is done
    @Published var generationSubmitted = false
    
    enum GenerationProgress: Equatable {
        case idle
        case uploadingVideo
        case uploading
        case submitting
        case processing(eta: Int?)
        case finalizing
        case completed
        case failed(String)
        
        var message: String {
            switch self {
            case .idle: return ""
            case .uploadingVideo: return "Uploading your video..."
            case .uploading: return "Uploading your photo..."
            case .submitting: return "Starting generation..."
            case .processing(let eta):
                if let eta = eta {
                    return "Creating your video... (~\(eta)s)"
                }
                return "Creating your video..."
            case .finalizing: return "Almost done..."
            case .completed: return "Done!"
            case .failed(let message): return message
            }
        }
        
        /// Whether the user can safely dismiss the generating screen
        var canDismiss: Bool {
            switch self {
            case .processing, .finalizing, .completed:
                return true
            default:
                return false
            }
        }
    }
    
    // MARK: - Private
    private let storageService = StorageService.shared
    private let generationService = GenerationService.shared
    private let historyService = GenerationHistoryService.shared
    private let activeGenerationManager = ActiveGenerationManager.shared
    private let userVideoService = UserVideoService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        setupNotificationListeners()
    }
    
    // MARK: - Setup
    
    private func setupNotificationListeners() {
        // Listen for generation completed (from background polling)
        NotificationCenter.default.publisher(for: .generationCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                if let outputUrl = notification.userInfo?["outputUrl"] as? String {
                    self.handleBackgroundCompletion(outputUrl: outputUrl)
                }
            }
            .store(in: &cancellables)
        
        // Listen for generation failed (from background polling)
        NotificationCenter.default.publisher(for: .generationFailed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                if let error = notification.userInfo?["error"] as? String {
                    self.handleBackgroundFailure(error: error)
                }
            }
            .store(in: &cancellables)
    }
    
    /// Handle completion from background polling
    private func handleBackgroundCompletion(outputUrl: String) {
        // Only update if we're still showing as generating
        if isGenerating || generationSubmitted {
            outputVideoUrl = outputUrl
            progress = .completed
            isGenerating = false
            generationSubmitted = false
            AppState.shared.navigateToTab(.myVideos)
        }
    }
    
    /// Handle failure from background polling
    private func handleBackgroundFailure(error: String) {
        if isGenerating || generationSubmitted {
            self.error = .generationFailed(error)
            progress = .failed(error)
            isGenerating = false
            generationSubmitted = false
            HapticManager.shared.error()
        }
    }
    
    // MARK: - Public Methods
    
    /// Start the full generation flow with persistent state tracking (non-blocking)
    /// Generation continues in background after submission
    func generate(photo: UIImage, template: VideoTemplate) async {
        guard !isGenerating else { return }
        guard AppState.shared.isPremiumUser else {
            showPaywall = true
            return
        }
        guard activeGenerationManager.canStartNewGeneration() else { return }
        
        isGenerating = true
        generationSubmitted = false
        error = nil
        
        // Determine if this is a custom user video
        let isCustom = UserVideoService.isLocalFileURL(template.videoUrl)
        
        // Track start
        Analytics.track(.generationStarted(
            effectId: template.id.uuidString,
            effectName: template.name,
            isCustom: isCustom
        ))
        
        // Register intent immediately so it persists even if user leaves
        activeGenerationManager.startUploading(
            templateName: template.name,
            templateId: template.id.uuidString,
            referenceVideoUrl: template.videoUrl
        )
        
        // Allow early dismissal after a short delay for better UX
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            if self.isGenerating {
                self.generationSubmitted = true
            }
        }
        
        do {
            // Step 0: If reference video is a local file, upload it first
            var referenceVideoUrl = template.videoUrl
            if UserVideoService.isLocalFileURL(referenceVideoUrl) {
                progress = .uploadingVideo
                if let localVideo = userVideoService.findVideo(byEffectiveUrl: referenceVideoUrl) {
                    referenceVideoUrl = try await userVideoService.ensureUploaded(localVideo)
                } else {
                    throw GenerationServiceError.serverError("Video file not found. Please re-import the video and try again.")
                }
            }
            
            // Step 1: Upload photo to Supabase storage
            progress = .uploading
            let imageUrl = try await storageService.uploadPortrait(photo)
            
            // Step 2: Submit generation request
            progress = .submitting
            let job = try await generationService.generateVideo(
                portraitUrl: imageUrl,
                referenceVideoUrl: referenceVideoUrl
            )
            
            // Step 3: Transition to processing state
            activeGenerationManager.transitionToProcessing(
                generationId: job.generationId,
                fetchId: job.fetchId,
                inputImageUrl: imageUrl
            )
            
            // Step 4: Mark as processing
            progress = .processing(eta: nil)
            generationSubmitted = true
            
            // Step 5: Start background polling (non-blocking)
            activeGenerationManager.startBackgroundPolling()
            
        } catch let error as GenerationServiceError {
            handleError(error)
        } catch {
            handleError(.networkError(error))
        }
    }
    
    /// Start effect-based generation (generate-video backend) - non-blocking
    func generateEffect(primaryPhoto: UIImage, secondaryPhoto: UIImage?, userPrompt: String?, effect: Effect) async {
        guard !isGenerating else { return }
        guard AppState.shared.isPremiumUser else {
            showPaywall = true
            return
        }
        guard activeGenerationManager.canStartNewGeneration() else { return }

        isGenerating = true
        generationSubmitted = false
        error = nil

        Analytics.track(.generationStarted(effectId: effect.id.uuidString, effectName: effect.name, isCustom: false))

        // Register intent immediately
        activeGenerationManager.startUploading(
            templateName: effect.name,
            templateId: effect.id.uuidString,
            referenceVideoUrl: "effect"
        )
        
        // Allow early dismissal after a short delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.isGenerating {
                self.generationSubmitted = true
            }
        }

        do {
            progress = .uploading
            let uploadResult = try await storageService.uploadImage(primaryPhoto)

            var secondaryImageUrl: String?
            if effect.requiresSecondaryPhoto, let secondary = secondaryPhoto {
                progress = .uploading
                secondaryImageUrl = try await storageService.uploadImage(secondary).url
            }

            progress = .submitting
            let job = try await generationService.executeEffect(
                effectId: effect.id.uuidString,
                primaryImageUrl: uploadResult.url,
                secondaryImageUrl: secondaryImageUrl,
                userPrompt: userPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? userPrompt : nil,
                detectedAspectRatio: uploadResult.detectedAspectRatio
            )

            activeGenerationManager.transitionToProcessing(
                generationId: job.generationId,
                fetchId: job.fetchId,
                inputImageUrl: uploadResult.url
            )

            progress = .processing(eta: nil)
            generationSubmitted = true
            activeGenerationManager.startBackgroundPolling()

        } catch let error as GenerationServiceError {
            handleError(error)
        } catch {
            handleError(.networkError(error))
        }
    }

    /// Generate with a custom video URL (for custom templates) - non-blocking
    func generateWithCustomVideo(photo: UIImage, videoUrl: String, templateName: String) async {
        guard !isGenerating else { return }
        guard AppState.shared.isPremiumUser else {
            showPaywall = true
            return
        }
        guard activeGenerationManager.canStartNewGeneration() else { return }
        
        isGenerating = true
        generationSubmitted = false
        error = nil
        
        Analytics.track(.generationStarted(effectId: nil, effectName: templateName, isCustom: true))
        
        // Register intent immediately
        activeGenerationManager.startUploading(
            templateName: templateName,
            templateId: nil,
            referenceVideoUrl: videoUrl
        )
        
        // Allow early dismissal after a short delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.isGenerating {
                self.generationSubmitted = true
            }
        }
        
        do {
            // Step 0: If video is a local file, upload it first
            var resolvedVideoUrl = videoUrl
            if UserVideoService.isLocalFileURL(videoUrl) {
                progress = .uploadingVideo
                if let localVideo = userVideoService.findVideo(byEffectiveUrl: videoUrl) {
                    resolvedVideoUrl = try await userVideoService.ensureUploaded(localVideo)
                } else {
                    throw GenerationServiceError.serverError("Video file not found. Please re-import the video and try again.")
                }
            }
            
            // Step 1: Upload photo
            progress = .uploading
            let imageUrl = try await storageService.uploadPortrait(photo)
            
            // Step 2: Submit generation
            progress = .submitting
            let job = try await generationService.generateVideo(
                portraitUrl: imageUrl,
                referenceVideoUrl: resolvedVideoUrl
            )
            
            // Step 3: Transition to processing
            activeGenerationManager.transitionToProcessing(
                generationId: job.generationId,
                fetchId: job.fetchId,
                inputImageUrl: imageUrl
            )
            
            // Step 4: Mark as processing
            progress = .processing(eta: nil)
            generationSubmitted = true
            
            // Step 5: Start background polling (non-blocking)
            activeGenerationManager.startBackgroundPolling()
            
        } catch let error as GenerationServiceError {
            handleError(error)
        } catch {
            handleError(.networkError(error))
        }
    }
    
    /// Resume a pending generation (if one exists) - starts background polling
    func resumePendingGeneration() {
        guard activeGenerationManager.hasActiveGeneration else { return }
        guard !activeGenerationManager.isPollingActive else {
            print("ℹ️ GenerationViewModel: Polling already active")
            return
        }
        
        // Mark as generating so UI shows appropriate state
        generationSubmitted = true
        progress = .processing(eta: nil)
        
        // Start background polling
        activeGenerationManager.startBackgroundPolling()
    }
    
    /// Check if there's a pending generation to resume
    var hasPendingGeneration: Bool {
        activeGenerationManager.hasActiveGeneration
    }
    
    /// Reset state for new generation (does NOT clear pending backend generation)
    func reset() {
        selectedPhoto = nil
        isGenerating = false
        generationSubmitted = false
        progress = .idle
        showResult = false
        outputVideoUrl = nil
        error = nil
        showPaywall = false
    }
    
    /// Dismiss the generating view and continue in background
    func dismissGeneratingView() {
        // Keep generationSubmitted true so we know there's an active generation
        // But allow the UI to dismiss
        if let pending = activeGenerationManager.pendingGeneration {
            Analytics.track(.generationBackgrounded(generationId: pending.generationId))
        }
        isGenerating = false
    }
    
    // MARK: - Private Methods
    
    private func handleError(_ error: GenerationServiceError) {
        let wasGenerating = isGenerating
        let isDismissed = !isGenerating && generationSubmitted
        
        isGenerating = false
        progress = .failed(error.localizedDescription)
        HapticManager.shared.error()
        
        // Track error
        Analytics.track(.generationFailed(
            effectId: nil,
            effectName: nil,
            error: error.localizedDescription,
            errorCategory: Self.categorizeError(error)
        ))
        
        // Clear from active manager if it failed during upload
        activeGenerationManager.clearPendingGeneration()
        
        if isDismissed {
            // User already dismissed the view, show a toast instead of an alert
            NotificationCenter.default.post(
                name: .generationFailed,
                object: nil,
                userInfo: ["error": error.localizedDescription]
            )
        } else {
            // Delay setting the error if we were generating, to allow the fullScreenCover to dismiss
            // otherwise SwiftUI swallows the alert
            if wasGenerating {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.error = error
                    if error.isSubscriptionError {
                        self.showPaywall = true
                    }
                }
            } else {
                self.error = error
                if error.isSubscriptionError {
                    self.showPaywall = true
                }
            }
        }
    }
    
    private static func categorizeError(_ error: GenerationServiceError) -> AnalyticsEvent.ErrorCategory {
        switch error {
        case .networkError: return .network
        case .timeout: return .timeout
        case .noSubscription, .limitReached: return .subscription
        case .serverError, .generationFailed, .invalidResponse, .statusCheckFailed: return .server
        case .invalidRequest: return .unknown
        }
    }

    private func saveToHistory(template: VideoTemplate, inputUrl: String, outputUrl: String?) {
        historyService.saveGeneration(
            templateName: template.name,
            templateId: template.id.uuidString,
            inputImageUrl: inputUrl,
            outputVideoUrl: outputUrl,
            isCustomTemplate: false
        )
    }
}
