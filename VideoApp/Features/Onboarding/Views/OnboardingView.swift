//
//  OnboardingView.swift
//  AIVideo
//
//  Onboarding flow with video backgrounds
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentPage: Int = 0
    
    private let pages = OnboardingPage.pages
    
    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()
            
            // Page content
            TabView(selection: $currentPage) {
                ForEach(pages) { page in
                    OnboardingPageView(
                        page: page,
                        isCurrentPage: currentPage == page.id
                    )
                    .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            
            // Overlay controls
            VStack {
                Spacer()
                
                VStack(spacing: VideoSpacing.md) {
                    // Page indicator
                    VideoPageIndicator(
                        totalPages: pages.count,
                        currentPage: $currentPage
                    )
                    
                    // Continue button
                    VideoButton(title: buttonTitle) {
                        nextPage()
                    }
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                }
                .padding(.bottom, VideoSpacing.huge)
            }
        }
        .onAppear {
            Analytics.track(.onboardingStarted)
        }
    }
    
    private var buttonTitle: String {
        currentPage == pages.count - 1 ? "Let's Go" : "Continue"
    }
    
    private func nextPage() {
        HapticManager.shared.lightImpact()
        
        if currentPage < pages.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPage += 1
            }
            Analytics.track(.onboardingPageViewed(page: currentPage))
        } else {
            // Complete onboarding immediately and signal RootView to show paywall.
            // This ensures the paywall is presented over MainTabView (not OnboardingView),
            // so when the user dismisses it, they land directly on the main screen.
            appState.hasReachedPaywall = true
            appState.showOnboardingPaywall = true
            appState.hasCompletedOnboarding = true
            Analytics.track(.onboardingCompleted)
            Analytics.setUserProperty("true", for: .onboardingCompleted)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
        .environmentObject(AppState.shared)
}
