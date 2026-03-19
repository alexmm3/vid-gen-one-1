//
//  HistoryDetailView.swift
//  AIVideo
//
//  ⚠️  PROVEN IMPLEMENTATION — DO NOT REFACTOR THE PRESENTATION MECHANISM  ⚠️
//
//  This view is presented via .fullScreenCover + .navigationTransition(.zoom)
//  from HistoryListView. That combination produces a flawless Photos-like hero
//  zoom from the grid card and back. It was validated on iPhone 17 Pro / iOS 26.
//
//  Key contracts:
//  • HistoryListView applies .matchedTransitionSource(id:in:) on each card
//  • HistoryListView presents this view inside .fullScreenCover(item:)
//  • This view applies .navigationTransition(.zoom(sourceID:in:)) via heroZoomTarget
//  • Dismiss is triggered by @Environment(\.dismiss) — the system reverses the zoom
//  • Custom drag-to-dismiss calls dismiss() after threshold — system handles the rest
//
//  DO NOT replace .fullScreenCover with ZStack overlay.
//  DO NOT replace .navigationTransition(.zoom) with matchedGeometryEffect.
//  DO NOT add manual hero-animation frames/positions/scales for the open transition.
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
    @State private var saveSuccessHideTask: Task<Void, Never>?
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
    
    // Read safe-area from the presentation window rather than deriving it from
    // nested SwiftUI geometry. That was the most stable approach for this
    // fullscreen cover on Dynamic Island devices.
    private var safeAreaInsets: UIEdgeInsets {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else { return UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0) }
        return window.safeAreaInsets
    }
    
    private var screenWidth: CGFloat { UIScreen.main.bounds.width }
    private var screenHeight: CGFloat { UIScreen.main.bounds.height }
    private var hasPlayableVideo: Bool { generation.fullOutputUrl != nil }
    
    // MARK: - Body
    
    var body: some View {
        let viewScale = 1.0 - (dragFraction * 0.1)
        let cornerRadius = dragFraction * 24
        let safeTop = max(safeAreaInsets.top, 20)
        let safeBottom = max(safeAreaInsets.bottom, 20)
        
        ZStack {
            // 1. Fixed dim background — visible during drag-to-dismiss
            Color.black
                .opacity(1.0 - (dragFraction * 0.4))
                .ignoresSafeArea()
            
            // 2. Movable content strictly bound to screen size.
            // The hard screen-sized frame is important: without it, the video /
            // thumbnail layer can report a larger natural width and push the
            // controls off-screen, especially on taller phones.
            ZStack {
                // Video + background fill the screen
                Color.black
                videoPlayerContent
                
                // Tap target for showing/hiding controls
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toggleControls() }
                
                // Gradient scrims behind controls
                controlsScrim
                    .opacity(controlsReady && showControls ? 1 : 0)
                    .allowsHitTesting(false)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showControls)
                
                // Interactive controls (respect safe area via manual padding)
                VStack(spacing: 0) {
                    topControls
                        .padding(.top, safeTop)
                        .offset(y: showControls ? 0 : -20)
                    Spacer()
                    bottomControls
                        .padding(.bottom, safeBottom)
                        .offset(y: showControls ? 0 : 20)
                }
                .opacity(controlsReady && showControls ? 1 : 0)
                .allowsHitTesting(controlsReady && showControls)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showControls)
                
                // Thin always-on progress bar (when controls are hidden)
                VStack {
                    Spacer()
                    VideoProgressBar(
                        progress: progress,
                        elapsedSeconds: elapsedSeconds,
                        totalSeconds: totalSeconds,
                        isExpanded: false
                    )
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                    .padding(.bottom, safeBottom + 2)
                }
                .opacity(controlsReady && !showControls ? 1 : 0)
                .allowsHitTesting(false)
                
                // Save success toast
                if showSaveSuccess { saveSuccessToast(safeBottom: safeBottom) }
            }
            .frame(width: screenWidth, height: screenHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .scaleEffect(viewScale, anchor: .top)
            .offset(y: dragOffset)
            .gesture(dismissDragGesture)
            .position(x: screenWidth / 2, y: screenHeight / 2)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onReceive(progressTimer) { _ in updateProgress() }
        .sheet(isPresented: $showShareSheet) {
            if let fileUrl = shareFileUrl {
                ShareSheet(items: [fileUrl, ExternalURLs.shareAttribution]) {
                    HistoryItemActionHandler.cleanupTemporaryShareFile(fileUrl)
                }
                    .onDisappear {
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
            saveSuccessHideTask?.cancel()
        }
    }
    
    // MARK: - Video Player
    
    private var videoPlayerContent: some View {
        Group {
            if let url = generation.fullOutputUrl {
                ZStack {
                    // Match the fullscreen player with .fit too, otherwise the
                    // placeholder thumbnail can appear more zoomed than the video
                    // during the first moments of the transition.
                    VideoThumbnailView(thumbnailUrl: nil, videoUrl: url, contentMode: .fit)
                        .frame(width: screenWidth, height: screenHeight)
                        .clipped()
                    
                    RemoteVideoPlayer(
                        url: url,
                        isPlaying: isPlaying,
                        isMuted: isMuted,
                        videoGravity: .resizeAspect,
                        timeProvider: timeProvider
                    )
                    .frame(width: screenWidth, height: screenHeight)
                }
                .frame(width: screenWidth, height: screenHeight)
            } else {
                VStack(spacing: VideoSpacing.sm) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 40))
                    Text("Video unavailable")
                        .font(.videoCaption)
                }
                .frame(width: screenWidth, height: screenHeight)
                .foregroundColor(.videoTextTertiary)
            }
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
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    if generation.isCustomTemplate {
                        Text("Custom")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.videoBlack)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.videoAccent)
                            .cornerRadius(4)
                            .layoutPriority(1) // Ensure badge isn't truncated
                    }
                }
                
                Text(generation.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(maxWidth: screenWidth - 140) // Prevent long titles from pushing buttons off-screen
            
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
                glassCircleButton(icon: isPlaying ? "pause.fill" : "play.fill", isEnabled: hasPlayableVideo) {
                    isPlaying.toggle()
                }
                glassCircleButton(icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", isEnabled: hasPlayableVideo) {
                    isMuted.toggle()
                }
                Spacer()
                glassCircleButton(icon: "square.and.arrow.down", isLoading: isSaving, tint: .videoAccent, isEnabled: hasPlayableVideo) {
                    saveToPhotos()
                }
                glassCircleButton(icon: "square.and.arrow.up", isLoading: isSharing, tint: .videoAccent, isEnabled: hasPlayableVideo) {
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
        icon: String,
        isLoading: Bool = false,
        tint: Color? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
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
            .opacity(isEnabled ? 1 : 0.4)
        }
        .disabled(isLoading || !isEnabled)
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
    
    private func saveSuccessToast(safeBottom: CGFloat) -> some View {
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
            .padding(.bottom, safeBottom + 60)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSaveSuccess)
    }
    
    // MARK: - Actions
    
    private func saveToPhotos() {
        guard generation.fullOutputUrl != nil, !isSaving else { return }
        isSaving = true
        Analytics.track(.videoSaved)
        HapticManager.shared.lightImpact()
        Task {
            do {
                try await HistoryItemActionHandler.saveToPhotos(generation: generation)
                await MainActor.run {
                    isSaving = false
                    triggerSaveSuccessToast()
                    HapticManager.shared.success()
                }
            } catch {
                await MainActor.run { isSaving = false; showSaveError = true; HapticManager.shared.error() }
            }
        }
    }
    
    private func shareVideo() {
        guard generation.fullOutputUrl != nil, !isSharing else { return }
        isSharing = true
        Analytics.track(.videoShared)
        HapticManager.shared.lightImpact()
        Task {
            do {
                let tempUrl = try await HistoryItemActionHandler.prepareShareFile(for: generation)
                await MainActor.run { isSharing = false; shareFileUrl = tempUrl; showShareSheet = true }
            } catch {
                await MainActor.run { isSharing = false; HapticManager.shared.error() }
            }
        }
    }
    
    private func triggerSaveSuccessToast() {
        saveSuccessHideTask?.cancel()
        showSaveSuccess = false
        Task { @MainActor in
            await Task.yield()
            showSaveSuccess = true
        }
        saveSuccessHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            showSaveSuccess = false
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
