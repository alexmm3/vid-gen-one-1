//
//  OnboardingPageView.swift
//  AIVideo
//
//  Individual onboarding page view
//

import SwiftUI

struct OnboardingPageView: View {
    let page: OnboardingPage
    let isCurrentPage: Bool
    
    var body: some View {
        ZStack {
            // Background - video or gradient
            backgroundView
            
            // Content overlay
            VStack {
                Spacer()
                
                // Content card
                contentCard
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                    .padding(.bottom, 140) // Space for controls - closer to bottom
            }
        }
    }
    
    // MARK: - Background
    
    @ViewBuilder
    private var backgroundView: some View {
        if let videoName = page.videoName {
            // Video background (if video exists in bundle)
            ZStack {
                LoopingVideoPlayer(
                    videoName: videoName,
                    videoExtension: "mp4",
                    isPlaying: isCurrentPage
                )
                .ignoresSafeArea()
                
                // Dark overlay
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.3),
                        Color.black.opacity(0.6),
                        Color.black.opacity(0.9)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        } else {
            // Fallback gradient background
            ZStack {
                Color.videoBackground
                
                // Animated gradient circles
                GeometryReader { geometry in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.videoAccent.opacity(0.3), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: geometry.size.width * 0.5
                            )
                        )
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .offset(x: geometry.size.width * 0.3, y: -geometry.size.height * 0.1)
                    
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.videoAccentSecondary.opacity(0.2), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: geometry.size.width * 0.4
                            )
                        )
                        .frame(width: geometry.size.width * 0.8, height: geometry.size.width * 0.8)
                        .offset(x: -geometry.size.width * 0.2, y: geometry.size.height * 0.5)
                }
            }
            .ignoresSafeArea()
        }
    }
    
    // MARK: - Content Card
    
    private var contentCard: some View {
        VStack(spacing: VideoSpacing.lg) {
            // Icon
            Image(systemName: page.icon)
                .font(.system(size: 50))
                .foregroundColor(.videoAccent)
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 4)
            
            // Title
            Text(page.title)
                .font(.videoDisplayLarge)
                .foregroundColor(.videoTextPrimary)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 2)
            
            // Subtitle
            Text(page.subtitle)
                .font(.videoBody)
                .foregroundColor(.videoTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 2)
        }
        .padding(VideoSpacing.xl)
    }
}

// MARK: - Preview

#Preview {
    OnboardingPageView(
        page: OnboardingPage.pages[0],
        isCurrentPage: true
    )
}
