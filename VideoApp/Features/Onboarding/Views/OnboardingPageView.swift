//
//  OnboardingPageView.swift
//  AIVideo
//
//  Individual onboarding page — cinematic single-title layout
//

import SwiftUI

struct OnboardingPageView: View {
    let page: OnboardingPage
    let isCurrentPage: Bool
    
    @State private var titleVisible = false
    
    var body: some View {
        ZStack {
            backgroundView
            
            VStack {
                Spacer()
                
                Text(page.title)
                    .font(.videoDisplayHero)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .tracking(0.5)
                    .shadow(color: .black.opacity(0.6), radius: 12, x: 0, y: 4)
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 20)
                    .animation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1), value: titleVisible)
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                    .padding(.bottom, 150)
            }
        }
        .onChange(of: isCurrentPage) { _, isCurrent in
            if isCurrent {
                titleVisible = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation {
                        titleVisible = true
                    }
                }
            } else {
                titleVisible = false
            }
        }
        .onAppear {
            if isCurrentPage {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation {
                        titleVisible = true
                    }
                }
            }
        }
    }
    
    // MARK: - Background
    
    @ViewBuilder
    private var backgroundView: some View {
        if let videoName = page.videoName {
            ZStack {
                LoopingVideoPlayer(
                    videoName: videoName,
                    videoExtension: "mp4",
                    isPlaying: isCurrentPage
                )
                .ignoresSafeArea()
                
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.15),
                        Color.black.opacity(0.65)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        } else {
            Color.videoBackground
                .ignoresSafeArea()
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingPageView(
        page: OnboardingPage.pages[0],
        isCurrentPage: true
    )
}
