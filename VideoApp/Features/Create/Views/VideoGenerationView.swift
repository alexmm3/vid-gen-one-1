//
//  VideoGenerationView.swift
//  AIVideo
//
//  Screen for preparing video generation after template selection
//  Integrates generation flow directly (no confirmation screen)
//

import SwiftUI
import PhotosUI
import AVFoundation

struct VideoGenerationView: View {
    let template: VideoTemplate
    
    @StateObject private var photoViewModel = VideoGenerationViewModel()
    @StateObject private var generationViewModel = GenerationViewModel()
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    // Photo selection
    @State private var showPhotoSourceSheet = false
    @State private var showImagePicker = false
    @State private var showCamera = false
    
    // Full screen video
    @State private var showFullScreenVideo = false
    
    // Paywall
    @State private var showPaywall = false
    
    // Video audio - play with sound by default
    @State private var isMuted = false
    
    // Time provider for seamless inline → fullscreen transition
    @State private var timeProvider = VideoTimeProvider()
    @State private var capturedTime: CMTime = .zero
    
    // Photo tips
    @State private var showPhotoTips = false
    
    // Generation in progress alert
    @State private var showGenerationInProgressAlert = false
    
    // AI data consent
    @State private var showAIDataConsent = false
    
    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: VideoSpacing.xl) {
                    // Video preview section
                    videoPreviewSection
                    
                    // Photo selection section
                    photoSelectionSection
                    
                    Spacer(minLength: 120)
                }
                .padding(.top, VideoSpacing.md)
            }
            
            // Bottom generate button
            VStack {
                Spacer()
                bottomBar
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Create Video")
                    .font(.videoHeadline)
                    .foregroundColor(.videoTextPrimary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    HapticManager.shared.selection()
                    showPhotoTips = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.videoTextSecondary)
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showPhotoTips) {
            PhotoTipsSheet()
                .presentationDetents([.height(600)])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            photoViewModel.loadSavedPhoto()
        }
        // Photo source sheet
        .sheet(isPresented: $showPhotoSourceSheet) {
            PhotoSourceSheet(
                onCamera: {
                    Task {
                        let hasPermission = await ImagePickerHelper.requestCameraPermission()
                        if hasPermission {
                            showCamera = true
                        }
                    }
                },
                onGallery: {
                    showImagePicker = true
                }
            )
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.hidden)
        }
        // Image picker
        .sheet(isPresented: $showImagePicker) {
            PHPickerViewController.View(
                selection: Binding(
                    get: { photoViewModel.selectedPhoto },
                    set: { photoViewModel.setPhoto($0) }
                ),
                filter: .images
            )
        }
        // Camera
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker(image: Binding(
                get: { photoViewModel.selectedPhoto },
                set: { photoViewModel.setPhoto($0) }
            ))
        }
        // Full screen video preview
        .fullScreenCover(isPresented: $showFullScreenVideo) {
            FullScreenVideoView(
                videoUrl: URL(string: template.videoUrl),
                title: template.name,
                startTime: capturedTime,
                initialMuted: isMuted
            )
        }
        // Full screen generating view - hides nav bar completely
        // Only allow dismiss once generation is confirmed started on backend
        .fullScreenCover(isPresented: $generationViewModel.isGenerating) {
            GeneratingView(
                progress: generationViewModel.progress,
                canDismiss: generationViewModel.generationSubmitted,
                inputImage: photoViewModel.selectedPhoto,
                onDismiss: {
                    generationViewModel.dismissGeneratingView()
                    appState.navigateToTab(.myVideos)
                    dismiss()
                }
            )
        }
        // Paywall
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(source: .generateBlocked) {
                showPaywall = false
                appState.setPremiumStatus(true)
                // After purchase, start generation
                startGeneration()
            }
        }
        // Result navigation
        .navigationDestination(isPresented: $generationViewModel.showResult) {
            if let outputUrl = generationViewModel.outputVideoUrl {
                ResultView(
                    videoUrl: outputUrl,
                    templateName: template.name
                )
            }
        }
        // Error alert
        .alert("Error", isPresented: .init(
            get: { generationViewModel.error != nil && !(generationViewModel.error?.isSubscriptionError ?? false) },
            set: { if !$0 { generationViewModel.error = nil } }
        )) {
            Button("OK") { generationViewModel.error = nil }
            Button("Retry") { startGeneration() }
        } message: {
            Text(generationViewModel.error?.localizedDescription ?? "Unknown error")
        }
        // Generation already in progress alert
        .alert("Hold On!", isPresented: $showGenerationInProgressAlert) {
            Button("Got It") { }
        } message: {
            Text("A video is already being created for you. Check My Videos to see its progress — it should be ready soon!")
        }
        // AI data consent sheet (first generation only)
        .sheet(isPresented: $showAIDataConsent) {
            AIDataConsentView {
                appState.hasAcceptedAIDataConsent = true
                startGeneration()
            }
            .interactiveDismissDisabled()
        }
        // Handle subscription error separately
        .onReceive(generationViewModel.$error) { error in
            if error?.isSubscriptionError == true {
                showPaywall = true
                generationViewModel.error = nil
            }
        }
    }
    
    // MARK: - Video Preview Section
    
    private var videoPreviewSection: some View {
        VStack(alignment: .center, spacing: VideoSpacing.sm) {
            // Video preview card - tap to open full screen
            Button {
                HapticManager.shared.selection()
                // Capture current playback position before opening fullscreen
                capturedTime = timeProvider.currentTime()
                showFullScreenVideo = true
            } label: {
                ZStack {
                    // Looping video – pause when fullscreen is open or generation starts
                    if let url = URL(string: template.videoUrl) {
                        RemoteVideoPlayer(
                            url: url,
                            isPlaying: !showFullScreenVideo && !generationViewModel.isGenerating,
                            isMuted: isMuted,
                            videoGravity: .resizeAspectFill,
                            timeProvider: timeProvider
                        )
                        .aspectRatio(9/16, contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color.videoSurface)
                            .aspectRatio(9/16, contentMode: .fill)
                    }
                    
                    // Title overlay at bottom
                    VStack {
                        Spacer()
                        HStack {
                            Text(template.name)
                                .font(.videoSubheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                            
                            if let duration = template.formattedDuration {
                                Text(duration)
                                    .font(.videoCaptionSmall)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding(VideoSpacing.sm)
                        .background(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .frame(width: 200, height: 280)
                .cornerRadius(20)
                .clipped()
            }
            .buttonStyle(ScaleButtonStyle())
            .overlay(alignment: .bottomTrailing) {
                VideoMuteButton(isMuted: $isMuted)
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, VideoSpacing.screenHorizontal)
    }
    
    // MARK: - Photo Selection Section
    
    private var photoSelectionSection: some View {
        VStack(alignment: .leading, spacing: VideoSpacing.sm) {
            HStack {
                Text("Your Character Photo")
                    .font(.videoSubheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.videoTextPrimary)
                
                Spacer()
                
                if photoViewModel.selectedPhoto != nil {
                    Button {
                        HapticManager.shared.selection()
                        showPhotoSourceSheet = true
                    } label: {
                        Text("Change")
                            .font(.videoCaptionSmall)
                            .foregroundColor(.videoAccent)
                    }
                }
            }
            .padding(.horizontal, VideoSpacing.screenHorizontal)
            
            // Photo card
            photoCard
                .padding(.horizontal, VideoSpacing.screenHorizontal)
        }
    }
    
    private var photoCard: some View {
        Button {
            HapticManager.shared.mediumImpact()
            showPhotoSourceSheet = true
        } label: {
            ZStack {
                if let photo = photoViewModel.selectedPhoto {
                    // Selected photo - stroke follows the actual photo shape
                    Image(uiImage: photo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium))
                        .overlay(
                            RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium)
                                .stroke(Color.videoAccent, lineWidth: 2)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                } else {
                    // Empty state
                    VStack(spacing: VideoSpacing.md) {
                        ZStack {
                            Circle()
                                .fill(Color.videoAccent.opacity(0.15))
                                .frame(width: 70, height: 70)
                            
                            Image(systemName: "person.crop.rectangle.badge.plus")
                                .font(.system(size: 30))
                                .foregroundColor(.videoAccent)
                        }
                        
                        VStack(spacing: 4) {
                            Text("Add Your Photo")
                                .font(.videoSubheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.videoTextPrimary)
                            
                            Text("Tap to select from gallery or take a photo")
                                .font(.videoCaptionSmall)
                                .foregroundColor(.videoTextSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .background(Color.videoSurface)
                    .cornerRadius(VideoSpacing.radiusMedium)
                    .overlay(
                        RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium)
                            .stroke(Color.videoAccent.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                    )
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.videoTextTertiary.opacity(0.2))
            
            VideoButton(
                title: "Generate Video",
                icon: "sparkles",
                action: {
                    startGeneration()
                },
                isEnabled: photoViewModel.selectedPhoto != nil && !generationViewModel.isGenerating
            )
            .padding(.horizontal, VideoSpacing.screenHorizontal)
            .padding(.top, VideoSpacing.md)
            .padding(.bottom, VideoSpacing.lg)
            .background(Color.videoBackground)
        }
    }
    
    // MARK: - Actions
    
    private func startGeneration() {
        // Show AI data consent on first generation
        if !appState.hasAcceptedAIDataConsent {
            showAIDataConsent = true
            return
        }
        
        // Check subscription
        if !appState.isPremiumUser {
            showPaywall = true
            return
        }
        
        // Block if another generation is already in progress (auto-clears expired ones)
        if !ActiveGenerationManager.shared.canStartNewGeneration() {
            showGenerationInProgressAlert = true
            return
        }
        
        guard let photo = photoViewModel.selectedPhoto else { return }
        
        Task {
            await generationViewModel.generate(photo: photo, template: template)
        }
    }
}

// MARK: - Full Screen Video View

struct FullScreenVideoView: View {
    let videoUrl: URL?
    let title: String
    /// Optional time to start playback from (for seamless detail → fullscreen transitions)
    var startTime: CMTime?
    /// Initial mute state inherited from the presenting view
    var initialMuted: Bool = false
    
    @Environment(\.dismiss) private var dismiss
    @State private var isMuted = false
    @State private var isPlaying = true
    @State private var showPlayPauseIndicator = false
    
    // Swipe-to-dismiss state
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    
    /// Threshold in points the user must drag down to trigger dismiss
    private let dismissThreshold: CGFloat = 150
    
    var body: some View {
        let dragProgress = min(max(dragOffset.height / dismissThreshold, 0), 1)
        let scale = 1.0 - (dragProgress * 0.15)
        let opacity = 1.0 - (dragProgress * 0.5)
        
        ZStack {
            Color.black.opacity(opacity).ignoresSafeArea()
            
            LoopingRemoteVideoPlayer(url: videoUrl, isMuted: isMuted, isPlaying: isPlaying, videoGravity: .resizeAspect, startTime: startTime)
                .ignoresSafeArea()
                .scaleEffect(scale)
                .offset(y: max(dragOffset.height, 0))
                .onTapGesture {
                    isPlaying.toggle()
                    HapticManager.shared.lightImpact()
                    showPlayPauseIndicator = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showPlayPauseIndicator = false
                        }
                    }
                }
            
            // Play/pause indicator
            if showPlayPauseIndicator {
                Image(systemName: isPlaying ? "play.fill" : "pause.fill")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 90, height: 90)
                    .background(.ultraThinMaterial.opacity(0.6))
                    .clipShape(Circle())
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            
            // Close button only
            VStack {
                HStack {
                    Button {
                        HapticManager.shared.selection()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, VideoSpacing.screenHorizontal)
                .padding(.top, 60)
                
                Spacer()
            }
            .opacity(1.0 - dragProgress)
            .offset(y: max(dragOffset.height, 0))
        }
        .animation(.easeInOut(duration: 0.2), value: showPlayPauseIndicator)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        isDragging = true
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    isDragging = false
                    if value.translation.height > dismissThreshold {
                        HapticManager.shared.selection()
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .onAppear {
            isMuted = initialMuted
        }
    }
}

// MARK: - Photo Tips Sheet

struct PhotoTipsSheet: View {
    var effectDescription: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.videoBackground.ignoresSafeArea()

                VStack(spacing: VideoSpacing.lg) {
                    // Header icon
                    ZStack {
                        Circle()
                            .fill(Color.videoAccent.opacity(0.15))
                            .frame(width: 80, height: 80)

                        Image(systemName: "person.fill.viewfinder")
                            .font(.system(size: 36))
                            .foregroundColor(.videoAccent)
                    }
                    .padding(.top, VideoSpacing.md)

                    Text("Tips for Best Results")
                        .font(.videoDisplayMedium)
                        .foregroundColor(.videoTextPrimary)

                    // Effect description (dynamic from backend)
                    if let description = effectDescription, !description.isEmpty {
                        Text(description)
                            .font(.videoBody)
                            .foregroundColor(.videoTextSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, VideoSpacing.lg)
                    }

                    // Tips list
                    VStack(alignment: .leading, spacing: VideoSpacing.md) {
                        tipRow(icon: "person.crop.rectangle", text: "Portraits work best")
                        tipRow(icon: "sun.max.fill", text: "Good lighting, better magic")
                        tipRow(icon: "photo.artframe", text: "Clear face = stunning result")
                        tipRow(icon: "arrow.up.left.and.arrow.down.right", text: "Use high-res photos")
                    }
                    .padding(.horizontal, VideoSpacing.lg)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Text("Got it")
                            .font(.videoBody)
                            .fontWeight(.semibold)
                            .foregroundColor(.videoBlack)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, VideoSpacing.md)
                            .background(Color.videoAccent)
                            .cornerRadius(VideoSpacing.radiusMedium)
                    }
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                    .padding(.bottom, VideoSpacing.lg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.videoTextSecondary)
                    }
                }
            }
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: VideoSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.videoAccent)
                .frame(width: 28)

            Text(text)
                .font(.videoBody)
                .foregroundColor(.videoTextPrimary)

            Spacer()
        }
        .padding(.vertical, VideoSpacing.xs)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        VideoGenerationView(template: VideoTemplate.sample)
            .environmentObject(AppState.shared)
    }
}
