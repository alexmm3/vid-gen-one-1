//
//  GeneratingView.swift
//  AIVideo
//
//  Full-screen view shown during video generation
//  Designed to allow user to leave - generation continues in background
//

import SwiftUI

struct GeneratingView: View {
    let progress: GenerationViewModel.GenerationProgress
    let onDismiss: (() -> Void)?
    let canDismiss: Bool
    let inputImage: UIImage?
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var shimmerOffset: CGFloat = -1.0
    
    @State private var currentTitleIndex: Int = 0
    @State private var titleTimer: Timer?
    
    private static let statusTitles: [String] = [
        "Creating your video...",
        "Analyzing your photo...",
        "Building your character...",
        "Rendering video frames...",
        "Applying finishing touches..."
    ]
    
    init(
        progress: GenerationViewModel.GenerationProgress,
        canDismiss: Bool = false,
        inputImage: UIImage? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.progress = progress
        self.canDismiss = canDismiss
        self.inputImage = inputImage
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        ZStack {
            // Blurred input image background or dark fallback
            if let image = inputImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .blur(radius: 40)
                    .overlay(Color.black.opacity(0.55).ignoresSafeArea())
            } else {
                Color.videoBackground
                    .ignoresSafeArea()
            }
            
            VStack(spacing: 0) {
                // Top bar with close button
                HStack {
                    Spacer()
                    if canDismiss, let onDismiss = onDismiss {
                        Button {
                            HapticManager.shared.selection()
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 32, height: 32)
                                .background(.ultraThinMaterial.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .padding(.trailing, VideoSpacing.screenHorizontal)
                        .padding(.top, VideoSpacing.lg)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: canDismiss)
                
                Spacer()
                
                // Centered content
                VStack(spacing: VideoSpacing.xl) {
                    // Minimal animated indicator
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 80, height: 80)
                            .scaleEffect(pulseScale)
                        
                        Image(systemName: "wand.and.sparkles")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: VideoSpacing.sm) {
                        Text(Self.statusTitles[currentTitleIndex])
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .id(currentTitleIndex)
                            .transition(.opacity)
                        
                        Text("Usually takes 4–5 minutes")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, VideoSpacing.xl)
                }
                
                Spacer()
                
                // Continue browsing button (pill style)
                if canDismiss, let onDismiss = onDismiss {
                    Button {
                        HapticManager.shared.mediumImpact()
                        onDismiss()
                    } label: {
                        HStack(spacing: VideoSpacing.xs) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Continue Browsing")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(Color(.darkGray))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.white.opacity(0.92))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                    .padding(.bottom, VideoSpacing.xxl)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Spacer()
                        .frame(height: VideoSpacing.xxl)
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: canDismiss)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
            startTitleRotation()
        }
        .onDisappear {
            titleTimer?.invalidate()
            titleTimer = nil
        }
    }
    
    // MARK: - Title Rotation
    
    private func startTitleRotation() {
        scheduleNextTitleChange()
    }
    
    private func scheduleNextTitleChange() {
        guard currentTitleIndex < Self.statusTitles.count - 1 else { return }
        
        let delay = Double.random(in: 25...40)
        
        titleTimer?.invalidate()
        titleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            Task { @MainActor in
                let nextIndex = currentTitleIndex + 1
                guard nextIndex < Self.statusTitles.count else { return }
                
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentTitleIndex = nextIndex
                }
                
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
        inputImage: nil,
        onDismiss: {}
    )
}

#Preview("Uploading") {
    GeneratingView(
        progress: .uploading,
        canDismiss: false,
        inputImage: nil,
        onDismiss: nil
    )
}
