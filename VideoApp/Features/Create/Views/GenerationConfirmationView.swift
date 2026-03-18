//
//  GenerationConfirmationView.swift
//  AIVideo
//
//  Confirmation screen before starting generation
//

import SwiftUI

struct GenerationConfirmationView: View {
    let template: VideoTemplate
    let photo: UIImage
    
    @StateObject private var viewModel = GenerationViewModel()
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()
            
            VStack(spacing: VideoSpacing.xl) {
                // Summary card
                summaryCard
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                    .padding(.top, VideoSpacing.lg)
                
                // Explanation text
                explanationText
                    .padding(.horizontal, VideoSpacing.xl)
                
                Spacer()
                
                // Generate button
                VideoButton(title: "Generate Video") {
                    startGeneration()
                }
                .padding(.horizontal, VideoSpacing.screenHorizontal)
                .padding(.bottom, VideoSpacing.xxl)
            }
            
        }
        // Full screen generating view
        .fullScreenCover(isPresented: $viewModel.isGenerating) {
            GeneratingView(
                progress: viewModel.progress,
                canDismiss: viewModel.generationSubmitted,
                inputImage: photo,
                onDismiss: {
                    viewModel.dismissGeneratingView()
                    appState.navigateToTab(.myVideos)
                    dismiss()
                }
            )
        }
        .navigationTitle("Confirm")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(isPresented: $viewModel.showPaywall) {
            PaywallView(source: .generateBlocked) {
                // Purchase successful - continue with generation
                viewModel.showPaywall = false
                appState.setPremiumStatus(true)
                startGeneration()
            }
        }
        .navigationDestination(isPresented: $viewModel.showResult) {
            if let outputUrl = viewModel.outputVideoUrl {
                ResultView(
                    videoUrl: outputUrl,
                    templateName: template.name
                )
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.error != nil && !viewModel.error!.isSubscriptionError },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
            Button("Retry") { startGeneration() }
        } message: {
            Text(viewModel.error?.localizedDescription ?? "Unknown error")
        }
    }
    
    // MARK: - Summary Card
    
    private var summaryCard: some View {
        VideoCard {
            HStack(spacing: VideoSpacing.md) {
                // User photo
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 140)
                    .clipped()
                    .cornerRadius(VideoSpacing.radiusMedium)
                
                // Arrow
                VStack {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.videoAccent)
                }
                
                // Template preview
                ZStack {
                    if let url = template.fullVideoUrl {
                        RemoteVideoPlayer(
                            url: url,
                            isPlaying: !viewModel.isGenerating,
                            isMuted: true
                        )
                    } else {
                        Color.videoSurfaceLight
                    }
                }
                .frame(width: 100, height: 140)
                .cornerRadius(VideoSpacing.radiusMedium)
            }
        }
    }
    
    // MARK: - Explanation
    
    private var explanationText: some View {
        VStack(spacing: VideoSpacing.sm) {
            Text("Ready to video!")
                .font(.videoHeadline)
                .foregroundColor(.videoTextPrimary)
            
            Text("This will create a video of you dancing to \"\(template.name)\" with the original music.")
                .font(.videoBody)
                .foregroundColor(.videoTextSecondary)
                .multilineTextAlignment(.center)
            
            Text("Generation typically takes 4-5 minutes")
                .font(.videoCaption)
                .foregroundColor(.videoTextTertiary)
                .padding(.top, VideoSpacing.xs)
        }
    }
    
    // MARK: - Actions
    
    private func startGeneration() {
        // Check subscription
        if !appState.isPremiumUser {
            viewModel.showPaywall = true
            return
        }
        
        Task {
            await viewModel.generate(photo: photo, template: template)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        GenerationConfirmationView(
            template: .sample,
            photo: UIImage(systemName: "person.fill")!
        )
        .environmentObject(AppState.shared)
    }
}
