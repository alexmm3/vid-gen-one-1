//
//  HistoryDetailView.swift
//  AIVideo
//
//  Detail view for a single video from My Videos
//

import SwiftUI
import Photos
import AVFoundation

struct HistoryDetailView: View {
    let generation: LocalGeneration
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = HistoryViewModel()
    
    @State private var showShareSheet = false
    @State private var showDeleteConfirmation = false
    @State private var isSaving = false
    @State private var isSharing = false
    @State private var showSaveSuccess = false
    @State private var showSaveError = false
    @State private var showFullScreenVideo = false
    @State private var shareFileUrl: URL?
    @State private var isMuted = false
    @State private var isPlaying = true
    
    // Time provider for seamless detail → fullscreen transition
    @State private var timeProvider = VideoTimeProvider()
    @State private var capturedTime: CMTime = .zero
    
    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Video player
                videoPlayer
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                    .padding(.top, VideoSpacing.md)
                
                // Info section
                infoSection
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                    .padding(.top, VideoSpacing.lg)
                
                Spacer()
                
                // Action buttons
                actionButtons
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                    .padding(.bottom, VideoSpacing.xxl)
            }
            
            // Save success toast
            if showSaveSuccess {
                saveSuccessToast
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    HapticManager.shared.selection()
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.white)
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(isPresented: $showFullScreenVideo) {
            FullScreenVideoView(
                videoUrl: generation.fullOutputUrl,
                title: generation.displayName,
                startTime: capturedTime,
                initialMuted: isMuted
            )
        }
        .sheet(isPresented: $showShareSheet) {
            if let fileUrl = shareFileUrl {
                ShareSheet(items: [fileUrl, ExternalURLs.shareAttribution])
                    .onDisappear {
                        // Clean up temp file after sharing
                        try? FileManager.default.removeItem(at: fileUrl)
                        shareFileUrl = nil
                    }
            }
        }
        .alert("Delete Video", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.deleteGeneration(generation)
                dismiss()
            }
        } message: {
            Text("This will remove the video from My Videos. This cannot be undone.")
        }
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK") { }
        } message: {
            Text("Unable to save video to Photos. Please check your permissions.")
        }
        .onAppear {
            viewModel.trackItemViewed(generation)
        }
    }
    
    // MARK: - Video Player
    
    private var videoPlayer: some View {
        Button {
            HapticManager.shared.selection()
            // Capture current playback position before opening fullscreen
            capturedTime = timeProvider.currentTime()
            showFullScreenVideo = true
        } label: {
            ZStack {
                if let url = generation.fullOutputUrl {
                    RemoteVideoPlayer(
                        url: url,
                        isPlaying: isPlaying && !showFullScreenVideo,
                        isMuted: isMuted,
                        videoGravity: .resizeAspect,
                        timeProvider: timeProvider
                    )
                } else {
                    Color.videoSurface
                        .overlay(
                            VStack(spacing: VideoSpacing.sm) {
                                Image(systemName: "video.slash")
                                    .font(.system(size: 40))
                                Text("Video unavailable")
                                    .font(.videoCaption)
                            }
                            .foregroundColor(.videoTextTertiary)
                        )
                }
            }
            .aspectRatio(9/16, contentMode: .fit)
            .cornerRadius(VideoSpacing.radiusLarge)
            .videoCardShadow()
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            // Play/pause (left) and mute (right) inside the video frame
            HStack {
                VideoPlayPauseButton(isPlaying: $isPlaying)
                Spacer()
                VideoMuteButton(isMuted: $isMuted)
            }
            .padding(VideoSpacing.sm)
        }
    }
    
    // MARK: - Info Section
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: VideoSpacing.sm) {
            HStack {
                Text(generation.displayName)
                    .font(.videoHeadline)
                    .foregroundColor(.videoTextPrimary)
                
                if generation.isCustomTemplate {
                    Text("Custom")
                        .font(.videoCaptionSmall)
                        .foregroundColor(.videoBlack)
                        .padding(.horizontal, VideoSpacing.xs)
                        .padding(.vertical, 2)
                        .background(Color.videoAccent)
                        .cornerRadius(4)
                }
            }
            
            Text(generation.createdAt.formatted(date: .long, time: .shortened))
                .font(.videoCaption)
                .foregroundColor(.videoTextTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: VideoSpacing.sm) {
            Button {
                saveToPhotos()
            } label: {
                HStack(spacing: VideoSpacing.xs) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(.darkGray)))
                            .frame(height: 20)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text("Save")
                        .font(.videoBody)
                        .fontWeight(.semibold)
                }
                .foregroundColor(Color(.darkGray))
                .frame(maxWidth: .infinity)
                .padding(.vertical, VideoSpacing.md)
                .background(Color.white.opacity(0.92))
                .clipShape(Capsule())
            }
            .disabled(isSaving || isSharing)
            .buttonStyle(ScaleButtonStyle())
            
            Button {
                shareVideo()
            } label: {
                HStack(spacing: VideoSpacing.xs) {
                    if isSharing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(.darkGray)))
                            .frame(height: 20)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text("Share")
                        .font(.videoBody)
                        .fontWeight(.semibold)
                }
                .foregroundColor(Color(.darkGray))
                .frame(maxWidth: .infinity)
                .padding(.vertical, VideoSpacing.md)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
            }
            .disabled(isSaving || isSharing)
            .buttonStyle(ScaleButtonStyle())
        }
    }
    
    // MARK: - Save Success Toast
    
    private var saveSuccessToast: some View {
        VStack {
            Spacer()
            
            HStack(spacing: VideoSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.videoAccent)
                Text("Saved to Photos")
                    .font(.videoBody)
                    .foregroundColor(.videoTextPrimary)
            }
            .padding(.horizontal, VideoSpacing.lg)
            .padding(.vertical, VideoSpacing.md)
            .background(Color.videoSurface)
            .cornerRadius(VideoSpacing.radiusFull)
            .videoElevatedShadow()
            .padding(.bottom, 150)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(), value: showSaveSuccess)
    }
    
    // MARK: - Actions
    
    private func saveToPhotos() {
        guard let urlString = generation.outputVideoUrl, !isSaving else { return }
        
        isSaving = true
        Analytics.track(.videoSaved)
        HapticManager.shared.lightImpact()
        
        Task {
            do {
                let data = try await StorageService.shared.downloadVideo(from: urlString)
                try await saveVideoToPhotoLibrary(data: data)
                
                await MainActor.run {
                    isSaving = false
                    showSaveSuccess = true
                    HapticManager.shared.success()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showSaveSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    showSaveError = true
                    HapticManager.shared.error()
                }
            }
        }
    }
    
    private func saveVideoToPhotoLibrary(data: Data) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let tempUrl = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            
            do {
                try data.write(to: tempUrl)
                
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempUrl)
                } completionHandler: { success, error in
                    try? FileManager.default.removeItem(at: tempUrl)
                    
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error ?? StorageServiceError.downloadFailed)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func shareVideo() {
        guard let urlString = generation.outputVideoUrl, !isSharing else { return }
        
        isSharing = true
        Analytics.track(.videoShared)
        HapticManager.shared.lightImpact()
        
        Task {
            do {
                // Download video to share as file (not URL)
                let data = try await StorageService.shared.downloadVideo(from: urlString)
                
                // Create temp file with descriptive name
                let tempUrl = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(generation.displayName.replacingOccurrences(of: " ", with: "_")).mp4")
                try data.write(to: tempUrl)
                
                await MainActor.run {
                    isSharing = false
                    shareFileUrl = tempUrl
                    showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isSharing = false
                    HapticManager.shared.error()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HistoryDetailView(generation: .sample)
            .environmentObject(AppState.shared)
    }
}
