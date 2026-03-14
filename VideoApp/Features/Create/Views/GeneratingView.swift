//
//  GeneratingView.swift
//  AIVideo
//
//  Full-screen view shown during video generation
//  Designed to allow user to leave - generation continues in background
//  Shows rotating status titles to simulate processing activity
//

import SwiftUI

struct GeneratingView: View {
    let progress: GenerationViewModel.GenerationProgress
    let onDismiss: (() -> Void)?
    let canDismiss: Bool
    
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    
    /// Index into the status titles array
    @State private var currentTitleIndex: Int = 0
    /// Timer that drives title rotation
    @State private var titleTimer: Timer?
    
    // MARK: - Status Titles
    // Abstract processing phrases shown in sequence during generation.
    // Each title displays for a random duration (20-35s).
    // The last title persists indefinitely for long generations.
    
    private static let statusTitles: [String] = [
        "Creating your video...",
        "Analyzing facial features...",
        "Mapping body movements...",
        "Extracting motion frames...",
        "Building character model...",
        "Aligning pose sequences...",
        "Blending motion layers...",
        "Rendering frame transitions...",
        "Enhancing visual details...",
        "Synchronizing with music...",
        "Smoothing animations...",
        "Compositing final layers...",
        "Calibrating color tones...",
        "Assembling video sequence...",
        "Applying finishing touches..."
    ]
    
    init(
        progress: GenerationViewModel.GenerationProgress,
        canDismiss: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) {
        self.progress = progress
        self.canDismiss = canDismiss
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        ZStack {
            // Full black background
            Color.videoBackground
                .ignoresSafeArea()
            
            VStack(spacing: VideoSpacing.xxl) {
                // Top bar with close button (shown when can dismiss)
                HStack {
                    Spacer()
                    if canDismiss, let onDismiss = onDismiss {
                        Button {
                            HapticManager.shared.selection()
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.videoTextSecondary)
                                .frame(width: 36, height: 36)
                                .background(Color.videoSurface)
                                .clipShape(Circle())
                        }
                        .padding(.trailing, VideoSpacing.screenHorizontal)
                        .padding(.top, VideoSpacing.lg)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: canDismiss)
                
                Spacer()
                
                // Animated loader - always shows the processing visual
                animatedLoader
                
                // Status text
                VStack(spacing: VideoSpacing.md) {
                    Text(Self.statusTitles[currentTitleIndex])
                        .font(.videoHeadline)
                        .foregroundColor(.videoTextPrimary)
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut(duration: 0.4), value: currentTitleIndex)
                        .id(currentTitleIndex) // Force view replacement for clean fade transition
                        .transition(.opacity)
                    
                    Text("This usually takes 4-5 minutes")
                        .font(.videoCaption)
                        .foregroundColor(.videoTextTertiary)
                    
                    // Hint that they can leave (shown when can dismiss)
                    if canDismiss {
                        Text("We'll notify you when your video is ready")
                            .font(.videoCaption)
                            .foregroundColor(.videoAccent)
                            .multilineTextAlignment(.center)
                            .padding(.top, VideoSpacing.sm)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, VideoSpacing.xl)
                .animation(.easeInOut(duration: 0.4), value: canDismiss)
                
                Spacer()
                
                // Continue browsing button (shown when can dismiss)
                if canDismiss, let onDismiss = onDismiss {
                    VStack(spacing: VideoSpacing.md) {
                        Button {
                            HapticManager.shared.mediumImpact()
                            onDismiss()
                        } label: {
                            HStack(spacing: VideoSpacing.xs) {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Continue Browsing")
                                    .font(.videoBody)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.videoTextPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, VideoSpacing.md)
                            .background(Color.videoSurface)
                            .cornerRadius(VideoSpacing.radiusMedium)
                        }
                        .padding(.horizontal, VideoSpacing.screenHorizontal)
                        
                        Text("Check progress in My Videos tab")
                            .font(.videoCaptionSmall)
                            .foregroundColor(.videoTextTertiary)
                    }
                    .padding(.bottom, VideoSpacing.xxl)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Spacer()
                }
            }
        }
        .onAppear {
            startAnimations()
            startTitleRotation()
        }
        .onDisappear {
            titleTimer?.invalidate()
            titleTimer = nil
        }
    }
    
    // MARK: - Animated Loader
    // Always shows the "processing" visual (wand icon) regardless of actual progress state.
    // This avoids the jarring flash of upload/submit icons during the first few seconds.
    
    private var animatedLoader: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(
                    LinearGradient.videoProcessingGradient,
                    lineWidth: 4
                )
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(rotation))
            
            // Inner pulsing circle
            Circle()
                .fill(Color.videoAccent.opacity(0.2))
                .frame(width: 60, height: 60)
                .scaleEffect(scale)
            
            // Always show the wand icon for a consistent processing look
            Image(systemName: "wand.and.sparkles")
                .font(.system(size: 30))
                .foregroundColor(.videoAccent)
        }
    }
    
    // MARK: - Animations
    
    private func startAnimations() {
        // Rotation animation
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
            rotation = 360
        }
        
        // Pulse animation
        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
            scale = 1.2
        }
    }
    
    // MARK: - Title Rotation
    
    /// Schedules the next title change after a random interval (20-35 seconds).
    /// Stops scheduling once we reach the last title (it stays indefinitely).
    private func startTitleRotation() {
        scheduleNextTitleChange()
    }
    
    private func scheduleNextTitleChange() {
        // If we're already at the last title, don't schedule another change
        guard currentTitleIndex < Self.statusTitles.count - 1 else { return }
        
        let delay = Double.random(in: 20...35)
        
        titleTimer?.invalidate()
        titleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            Task { @MainActor in
                let nextIndex = currentTitleIndex + 1
                guard nextIndex < Self.statusTitles.count else { return }
                
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentTitleIndex = nextIndex
                }
                
                // Schedule the next change (will stop at the last title)
                scheduleNextTitleChange()
            }
        }
    }
}

// MARK: - Preview

#Preview("Processing - Can Dismiss") {
    GeneratingView(
        progress: .processing(eta: 60),
        canDismiss: true,
        onDismiss: {}
    )
}

#Preview("Uploading - Shows Processing Visual") {
    GeneratingView(
        progress: .uploading,
        canDismiss: false,
        onDismiss: nil
    )
}

#Preview("Submitting - Shows Processing Visual") {
    GeneratingView(
        progress: .submitting,
        canDismiss: false,
        onDismiss: {}
    )
}
