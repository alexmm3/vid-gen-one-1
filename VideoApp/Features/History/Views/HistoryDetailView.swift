//
//  HistoryDetailView.swift
//  AIVideo
//
//  Immersive fullscreen detail view for a single video.
//  Presented via fullScreenCover with iOS 18 .zoom transition.
//  Custom drag-to-dismiss + overlay controls.
//

import SwiftUI
import Photos
import AVFoundation

struct HistoryDetailView: View {
    let generation: LocalGeneration
    var namespace: Namespace.ID
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = HistoryViewModel()
    
    @State private var showShareSheet = false
    @State private var showDeleteConfirmation = false
    @State private var isSaving = false
    @State private var isSharing = false
    @State private var showSaveSuccess = false
    @State private var showSaveError = false
    @State private var shareFileUrl: URL?
    @State private var isMuted = false
    @State private var isPlaying = true
    
    @State private var timeProvider = VideoTimeProvider()
    
    @State private var showControls = false
    @State private var controlsReady = false
    @State private var autoHideTask: Task<Void, Never>?
    @State private var progress: Double = 0
    @State private var elapsedSeconds: Double = 0
    @State private var totalSeconds: Double = 0
    @State private var isScrubbing = false
    
    // Drag-to-dismiss
    @State private var dragOffset: CGFloat = 0
    private let dismissThreshold: CGFloat = 150
    
    private let progressTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    private var dragFraction: CGFloat {
        min(max(dragOffset / dismissThreshold, 0), 1)
    }
    
    private var safeAreaTop: CGFloat {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let insets = scene.windows.first?.safeAreaInsets else { return 47 }
        return insets.top
    }
    
    private var safeAreaBottom: CGFloat {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let insets = scene.windows.first?.safeAreaInsets else { return 34 }
        return insets.bottom
    }
    
    var body: some View {
        let viewScale = 1.0 - (dragFraction * 0.1)
        let cornerRadius = dragFraction * 24
        let bgOpacity = 1.0 - (dragFraction * 0.4)
        
        ZStack {
            // Fixed background — dims during drag to reveal list underneath
            Color.black
                .opacity(bgOpacity)
                .ignoresSafeArea()
            
            // Movable content group — scales/moves/rounds during drag
            ZStack {
                Color.black
                
                videoPlayerContent
                
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toggleControls() }
                
                controlsOverlay
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showControls)
                
                if showSaveSuccess { saveSuccessToast }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .scaleEffect(viewScale, anchor: .top)
            .offset(y: dragOffset)
            .gesture(dismissDragGesture)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onReceive(progressTimer) { _ in updateProgress() }
        .sheet(isPresented: $showShareSheet) {
            if let fileUrl = shareFileUrl {
                ShareSheet(items: [fileUrl, ExternalURLs.shareAttribution])
                    .onDisappear {
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                controlsReady = true
                showControls = true
                scheduleAutoHide()
            }
        }
        .onDisappear {
            autoHideTask?.cancel()
        }
    }
    
    // MARK: - Video Player
    
    private var videoPlayerContent: some View {
        Group {
            if let url = generation.fullOutputUrl {
                ZStack {
                    VideoThumbnailView(thumbnailUrl: nil, videoUrl: url)
                        .clipped()
                    
                    RemoteVideoPlayer(
                        url: url,
                        isPlaying: isPlaying,
                        isMuted: isMuted,
                        videoGravity: .resizeAspect,
                        timeProvider: timeProvider
                    )
                }
            } else {
                VStack(spacing: VideoSpacing.sm) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 40))
                    Text("Video unavailable")
                        .font(.videoCaption)
                }
                .foregroundColor(.videoTextTertiary)
            }
        }
    }
    
    // MARK: - Controls Overlay
    
    private var controlsOverlay: some View {
        ZStack {
            controlsScrim
            
            VStack(spacing: 0) {
                topControls
                    .padding(.top, safeAreaTop)
                    .offset(y: showControls ? 0 : -20)
                Spacer()
                bottomControls
                    .padding(.bottom, safeAreaBottom)
                    .offset(y: showControls ? 0 : 20)
            }
            .opacity(controlsReady && showControls ? 1 : 0)
            .allowsHitTesting(controlsReady && showControls)
            
            VStack {
                Spacer()
                VideoProgressBar(
                    progress: progress,
                    elapsedSeconds: elapsedSeconds,
                    totalSeconds: totalSeconds,
                    isExpanded: false
                )
                .padding(.bottom, safeAreaBottom + 2)
            }
            .opacity(controlsReady && !showControls ? 1 : 0)
            .allowsHitTesting(false)
        }
    }
    
    // MARK: - Drag Gesture
    
    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                let h = value.translation.height
                let newOffset = max(h, 0)
                withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.86)) {
                    dragOffset = newOffset
                }
                if showControls && newOffset > 12 {
                    showControls = false
                    autoHideTask?.cancel()
                }
            }
            .onEnded { value in
                let h = value.translation.height
                let velocity = value.predictedEndTranslation.height - h
                if h > dismissThreshold || velocity > 600 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                }
            }
    }
    
    // MARK: - Scrims
    
    private var controlsScrim: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.6), location: 0),
                        .init(color: .black.opacity(0.15), location: 0.7),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 140)
                Spacer()
            }
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.15), location: 0.3),
                        .init(color: .black.opacity(0.6), location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 200)
            }
        }
        .opacity(controlsReady && showControls ? 1 : 0)
        .allowsHitTesting(false)
    }
    
    // MARK: - Top Controls
    
    private var topControls: some View {
        HStack(alignment: .center) {
            glassCircleButton(icon: "xmark") {
                dismiss()
            }
            
            Spacer()
            
            VStack(spacing: 2) {
                HStack(spacing: VideoSpacing.xs) {
                    Text(generation.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if generation.isCustomTemplate {
                        Text("Custom")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.videoBlack)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.videoAccent)
                            .cornerRadius(4)
                    }
                }
                .lineLimit(1)
                
                Text(generation.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            glassCircleButton(icon: "trash") {
                showDeleteConfirmation = true
            }
        }
        .padding(.horizontal, VideoSpacing.screenHorizontal)
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        VStack(spacing: VideoSpacing.md) {
            HStack(spacing: VideoSpacing.md) {
                glassCircleButton(icon: isPlaying ? "pause.fill" : "play.fill") {
                    isPlaying.toggle()
                }
                glassCircleButton(icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    isMuted.toggle()
                }
                Spacer()
                glassCircleButton(icon: "square.and.arrow.down", isLoading: isSaving, tint: .videoAccent) {
                    saveToPhotos()
                }
                glassCircleButton(icon: "square.and.arrow.up", isLoading: isSharing, tint: .videoAccent) {
                    shareVideo()
                }
            }
            
            VideoProgressBar(
                progress: progress, elapsedSeconds: elapsedSeconds, totalSeconds: totalSeconds,
                isExpanded: true,
                onScrub: { fraction in
                    timeProvider.seek?(fraction)
                    progress = fraction
                    elapsedSeconds = fraction * totalSeconds
                },
                onScrubStarted: { isScrubbing = true; autoHideTask?.cancel() },
                onScrubEnded: { isScrubbing = false; scheduleAutoHide() }
            )
        }
        .padding(.horizontal, VideoSpacing.screenHorizontal)
    }
    
    // MARK: - Glass Button
    
    private func glassCircleButton(
        icon: String, isLoading: Bool = false, tint: Color? = nil, action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.shared.selection()
            scheduleAutoHide()
            action()
        } label: {
            Group {
                if isLoading {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(tint ?? .white)
                }
            }
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
        }
        .disabled(isLoading)
        .buttonStyle(.plain)
    }
    
    // MARK: - Controls Visibility
    
    private func toggleControls() {
        guard controlsReady else { return }
        HapticManager.shared.lightImpact()
        showControls.toggle()
        if showControls { scheduleAutoHide() } else { autoHideTask?.cancel() }
    }
    
    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled, !isScrubbing else { return }
            showControls = false
        }
    }
    
    // MARK: - Progress
    
    private func updateProgress() {
        guard !isScrubbing else { return }
        let current = timeProvider.currentTime()
        guard current.isValid, current.isNumeric else { return }
        elapsedSeconds = CMTimeGetSeconds(current)
        if let dur = timeProvider.duration, dur.isNumeric {
            let durSec = CMTimeGetSeconds(dur)
            if durSec > 0 { totalSeconds = durSec; progress = elapsedSeconds / durSec }
        }
    }
    
    // MARK: - Toast
    
    private var saveSuccessToast: some View {
        VStack {
            Spacer()
            HStack(spacing: VideoSpacing.sm) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.videoAccent)
                Text("Saved to Photos").font(.videoBody).foregroundColor(.white)
            }
            .padding(.horizontal, VideoSpacing.lg)
            .padding(.vertical, VideoSpacing.md)
            .background(.ultraThinMaterial)
            .cornerRadius(VideoSpacing.radiusFull)
            .videoElevatedShadow()
            .padding(.bottom, safeAreaBottom + 60)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSaveSuccess)
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
                    isSaving = false; showSaveSuccess = true; HapticManager.shared.success()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showSaveSuccess = false }
                }
            } catch {
                await MainActor.run { isSaving = false; showSaveError = true; HapticManager.shared.error() }
            }
        }
    }
    
    private func saveVideoToPhotoLibrary(data: Data) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let tempUrl = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
            do {
                try data.write(to: tempUrl)
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempUrl)
                } completionHandler: { success, error in
                    try? FileManager.default.removeItem(at: tempUrl)
                    if success { continuation.resume() }
                    else { continuation.resume(throwing: error ?? StorageServiceError.downloadFailed) }
                }
            } catch { continuation.resume(throwing: error) }
        }
    }
    
    private func shareVideo() {
        guard let urlString = generation.outputVideoUrl, !isSharing else { return }
        isSharing = true
        Analytics.track(.videoShared)
        HapticManager.shared.lightImpact()
        Task {
            do {
                let data = try await StorageService.shared.downloadVideo(from: urlString)
                let tempUrl = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(generation.displayName.replacingOccurrences(of: " ", with: "_")).mp4")
                try data.write(to: tempUrl)
                await MainActor.run { isSharing = false; shareFileUrl = tempUrl; showShareSheet = true }
            } catch {
                await MainActor.run { isSharing = false; HapticManager.shared.error() }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @Namespace var ns
    HistoryDetailView(
        generation: .sample,
        namespace: ns
    )
    .environmentObject(AppState.shared)
}
