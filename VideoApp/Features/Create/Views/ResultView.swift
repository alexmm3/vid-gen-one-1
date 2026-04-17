//
//  ResultView.swift
//  AIVideo
//
//  View displaying the generated video result
//

import SwiftUI
import Photos

struct ResultView: View {
    let videoUrl: String
    let templateName: String
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var showShareSheet = false
    @State private var isSaving = false
    @State private var isSharing = false
    @State private var showSaveSuccess = false
    @State private var showSaveError = false
    @State private var shareFileUrl: URL?
    @State private var isMuted = false
    
    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Success header
                successHeader
                    .padding(.vertical, VideoSpacing.lg)
                
                // Video player
                videoPlayer
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                
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
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.videoTextSecondary)
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
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
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK") { }
        } message: {
            Text("Unable to save video to Photos. Please check your permissions.")
        }
        .onAppear {
            Analytics.track(.resultViewed(effectName: templateName))
        }
    }
    
    // MARK: - Success Header
    
    private var successHeader: some View {
        VStack(spacing: VideoSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.videoAccent)
            
            Text("Your Video is Ready!")
                .font(.videoHeadline)
                .foregroundColor(.videoTextPrimary)
            
            Text(templateName)
                .font(.videoCaption)
                .foregroundColor(.videoTextSecondary)
        }
    }
    
    // MARK: - Video Player
    
    private var videoPlayer: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                if let url = URL(string: videoUrl) {
                    RemoteVideoPlayer(
                        url: url,
                        isPlaying: true,
                        isMuted: isMuted,
                        videoGravity: .resizeAspect
                    )
                } else {
                    Color.videoSurface
                        .overlay(
                            Text("Video unavailable")
                                .foregroundColor(.videoTextTertiary)
                        )
                }
            }
            .aspectRatio(9/16, contentMode: .fit)
            .cornerRadius(VideoSpacing.radiusLarge)
            .videoCardShadow()
            
            // Mute button
            VideoMuteButton(isMuted: $isMuted)
                .padding(VideoSpacing.sm)
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: VideoSpacing.md) {
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
            
            Button {
                Analytics.track(.createAnotherTapped)
                appState.navigateToTab(.create)
                dismiss()
            } label: {
                Text("Create Another")
                    .font(.videoBody)
                    .fontWeight(.semibold)
                    .foregroundColor(.videoTextPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, VideoSpacing.md)
                    .background(Color.videoSurface)
                    .clipShape(Capsule())
            }
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
        guard !isSaving else { return }
        
        isSaving = true
        Analytics.track(.videoSaved(effectName: templateName))
        HapticManager.shared.lightImpact()

        Task {
            do {
                // Download video
                let data = try await StorageService.shared.downloadVideo(from: videoUrl)

                // Save to Photos
                try await saveVideoToPhotoLibrary(data: data)

                await MainActor.run {
                    isSaving = false
                    showSaveSuccess = true
                    HapticManager.shared.success()

                    // Hide toast after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showSaveSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    showSaveError = true
                    Analytics.track(.videoSaveFailed(error: error.localizedDescription))
                    HapticManager.shared.error()
                }
            }
        }
    }
    
    private func saveVideoToPhotoLibrary(data: Data) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            // Create temp file
            let tempUrl = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            
            do {
                try data.write(to: tempUrl)
                
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempUrl)
                } completionHandler: { success, error in
                    // Clean up temp file
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
        guard !isSharing else { return }
        
        isSharing = true
        Analytics.track(.videoShared(effectName: templateName))
        HapticManager.shared.lightImpact()
        
        Task {
            do {
                // Download video to share as file (not URL)
                let data = try await StorageService.shared.downloadVideo(from: videoUrl)
                
                // Create temp file with descriptive name
                let tempUrl = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(templateName.replacingOccurrences(of: " ", with: "_")).mp4")
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

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (() -> Void)? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ResultView(
            videoUrl: "https://example.com/video.mp4",
            templateName: "Hip Hop Groove"
        )
        .environmentObject(AppState.shared)
    }
}
