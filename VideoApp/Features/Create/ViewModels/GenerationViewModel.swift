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
        guard activeGenerationManager.canStartNewGeneration() else { return }
        
        isGenerating = true
        generationSubmitted = false
        error = nil
        
        // Determine if this is a custom user video
        let isCustom = UserVideoService.isLocalFileURL(template.videoUrl)
        
        // Track start
        Analytics.track(.generationStarted(
            templateId: template.id.uuidString,
            isCustom: isCustom
        ))
        
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
            
            // Step 3: Register with ActiveGenerationManager for persistence
            activeGenerationManager.startGeneration(
                generationId: job.generationId,
                fetchId: job.fetchId,
                templateName: template.name,
                templateId: template.id.uuidString,
                inputImageUrl: imageUrl,
                referenceVideoUrl: referenceVideoUrl
            )
            
            // Step 4: Mark as submitted - user can now dismiss
            progress = .processing(eta: nil)
            generationSubmitted = true
            
            // Step 5: Start background polling (non-blocking)
            // Polling continues even if user navigates away
            activeGenerationManager.startBackgroundPolling()
            
            // Note: We no longer await pollUntilComplete() here
            // The background polling will trigger notifications when done
            // handleBackgroundCompletion() will be called when complete
            
        } catch let error as GenerationServiceError {
            activeGenerationManager.clearPendingGeneration()
            handleError(error)
        } catch {
            activeGenerationManager.clearPendingGeneration()
            handleError(.networkError(error))
        }
    }
    
    /// Start effect-based generation (generate-video backend) - non-blocking
    func generateEffect(primaryPhoto: UIImage, secondaryPhoto: UIImage?, userPrompt: String?, effect: Effect) async {
        guard !isGenerating else { return }
        guard activeGenerationManager.canStartNewGeneration() else { return }

        isGenerating = true
        generationSubmitted = false
        error = nil

        Analytics.track(.generationStarted(templateId: effect.id.uuidString, isCustom: false))

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

            activeGenerationManager.startGeneration(
                generationId: job.generationId,
                fetchId: job.fetchId,
                templateName: effect.name,
                templateId: effect.id.uuidString,
                inputImageUrl: uploadResult.url,
                referenceVideoUrl: "effect"
            )

            progress = .processing(eta: nil)
            generationSubmitted = true
            activeGenerationManager.startBackgroundPolling()

        } catch let error as GenerationServiceError {
            activeGenerationManager.clearPendingGeneration()
            handleError(error)
        } catch {
            activeGenerationManager.clearPendingGeneration()
            handleError(.networkError(error))
        }
    }

    /// Generate with a custom video URL (for custom templates) - non-blocking
    func generateWithCustomVideo(photo: UIImage, videoUrl: String, templateName: String) async {
        guard !isGenerating else { return }
        guard activeGenerationManager.canStartNewGeneration() else { return }
        
        isGenerating = true
        generationSubmitted = false
        error = nil
        
        Analytics.track(.generationStarted(templateId: nil, isCustom: true))
        
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
            
            // Step 3: Register with ActiveGenerationManager for persistence
            activeGenerationManager.startGeneration(
                generationId: job.generationId,
                fetchId: job.fetchId,
                templateName: templateName,
                templateId: nil,
                inputImageUrl: imageUrl,
                referenceVideoUrl: resolvedVideoUrl
            )
            
            // Step 4: Mark as submitted - user can now dismiss
            progress = .processing(eta: nil)
            generationSubmitted = true
            
            // Step 5: Start background polling (non-blocking)
            activeGenerationManager.startBackgroundPolling()
            
        } catch let error as GenerationServiceError {
            activeGenerationManager.clearPendingGeneration()
            handleError(error)
        } catch {
            activeGenerationManager.clearPendingGeneration()
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
        isGenerating = false
    }
    
    // MARK: - Private Methods
    
    private func handleError(_ error: GenerationServiceError) {
        let wasGenerating = isGenerating
        isGenerating = false
        progress = .failed(error.localizedDescription)
        HapticManager.shared.error()
        
        // Track error
        Analytics.track(.generationFailed(error: error.localizedDescription))
        
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
