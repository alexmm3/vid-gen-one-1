//
//  ProfileView.swift
//  AIVideo
//
//  Profile tab with subscription status and settings
//  Phase 6: Full implementation
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @State private var showPaywall = false
    
    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: VideoSpacing.lg) {
                    // Subscription card
                    subscriptionCard
                        .padding(.horizontal, VideoSpacing.screenHorizontal)
                    
                    // Settings list
                    settingsList
                        .padding(.horizontal, VideoSpacing.screenHorizontal)
                    
                    // DEBUG: Developer options - Remove before release
                    #if DEBUG
                    debugSection
                        .padding(.horizontal, VideoSpacing.screenHorizontal)
                    #endif
                    
                    // App footer
                    appFooter
                        .padding(.top, VideoSpacing.xl)
                }
                .padding(.vertical, VideoSpacing.md)
                .padding(.bottom, 100) // Space for tab bar
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(source: .profile) {
                // Update app state after successful purchase
                appState.setPremiumStatus(true)
            }
        }
    }
    
    // MARK: - Subscription Banner
    
    @ViewBuilder
    private var subscriptionCard: some View {
        if appState.isPremiumUser {
            premiumStatusCard
        } else {
            freeUserBanner
        }
    }
    
    // MARK: Premium user card
    
    private var premiumStatusCard: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(LinearGradient.videoMarketingGradient)
                    .frame(width: 44, height: 44)
                
                Image(systemName: "crown.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.videoBlack)
            }
            
            VStack(alignment: .leading, spacing: VideoSpacing.xxs) {
                Text("Premium")
                    .font(.videoHeadline)
                    .foregroundColor(.videoTextPrimary)
                
                if let remaining = appState.generationsRemaining,
                   let limit = appState.generationLimit {
                    let used = limit - remaining
                    Text("\(used) of \(limit) videos used this period")
                        .font(.videoCaption)
                        .foregroundColor(.videoAccent)
                } else {
                    Text("Premium Plan")
                        .font(.videoCaption)
                        .foregroundColor(.videoAccent)
                }
            }
            
            Spacer()
            
            if let remaining = appState.generationsRemaining,
               let limit = appState.generationLimit, limit > 0 {
                let used = limit - remaining
                let progress = CGFloat(used) / CGFloat(limit)
                ZStack {
                    Circle()
                        .stroke(Color.videoAccent.opacity(0.3), lineWidth: 4)
                        .frame(width: 50, height: 50)
                    
                    Circle()
                        .trim(from: 0, to: min(progress, 1.0))
                        .stroke(Color.videoAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(remaining)")
                        .font(.videoSubheadline)
                        .foregroundColor(.videoTextPrimary)
                }
            }
        }
        .padding(VideoSpacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium)
                .fill(Color.videoSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium)
                .stroke(Color.videoAccent.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: Free user upsell banner
    
    private var freeUserBanner: some View {
        Button {
            showPaywall = true
        } label: {
            VStack(spacing: VideoSpacing.lg) {
                // Crown icon + title
                VStack(spacing: VideoSpacing.xs) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient.videoMarketingGradient)
                            .frame(width: 56, height: 56)
                            .shadow(color: Color.videoAccent.opacity(0.4), radius: 12, x: 0, y: 0)
                        
                        Image(systemName: "crown.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.videoBlack)
                    }
                    
                    Text("Go Premium")
                        .font(.videoHeadline)
                        .foregroundColor(.videoTextPrimary)
                    
                    Text("Create stunning videos with AI")
                        .font(.videoCaption)
                        .foregroundColor(.videoTextSecondary)
                }
                
                // Benefit rows
                VStack(alignment: .leading, spacing: VideoSpacing.sm) {
                    premiumBenefitRow(icon: "video.badge.plus", text: "Up to 40 Generations")
                    premiumBenefitRow(icon: "flame.fill", text: "Trending Templates")
                    premiumBenefitRow(icon: "sparkles", text: "HD Quality Output")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, VideoSpacing.xs)
                
                // CTA
                HStack(spacing: VideoSpacing.xs) {
                    Text("Go Premium")
                        .font(.videoBody)
                        .fontWeight(.semibold)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.videoBlack)
                .frame(maxWidth: .infinity)
                .frame(height: VideoSpacing.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: VideoSpacing.radiusSmall)
                        .fill(LinearGradient.videoMarketingGradient)
                )
            }
            .padding(VideoSpacing.lg)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: VideoSpacing.radiusLarge)
                        .fill(Color.videoSurface)
                    
                    // Subtle accent glow in the top-right
                    RoundedRectangle(cornerRadius: VideoSpacing.radiusLarge)
                        .fill(
                            RadialGradient(
                                colors: [Color.videoAccent.opacity(0.08), Color.clear],
                                center: .topTrailing,
                                startRadius: 0,
                                endRadius: 250
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: VideoSpacing.radiusLarge)
                    .stroke(Color.videoAccent.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    private func premiumBenefitRow(icon: String, text: String) -> some View {
        HStack(spacing: VideoSpacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.videoAccent.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.videoAccent)
            }
            
            Text(text)
                .font(.videoSubheadline)
                .foregroundColor(.videoTextPrimary)
        }
    }
    
    private var settingsList: some View {
        VideoCard(padding: 0) {
            VStack(spacing: 0) {
                settingsRow(icon: "star.fill", title: "Rate the App") {
                    Analytics.track(.rateAppTapped)
                    openURL(ExternalURLs.appStoreReview)
                }
                
                Divider().background(Color.videoTextTertiary.opacity(0.3))
                
                settingsRow(icon: "envelope.fill", title: "Contact Support") {
                    Analytics.track(.contactSupportTapped)
                    openURL(ExternalURLs.support)
                }
                
                Divider().background(Color.videoTextTertiary.opacity(0.3))
                
                settingsRow(icon: "doc.text.fill", title: "Privacy Policy") {
                    openURL(ExternalURLs.privacyPolicy)
                }
                
                Divider().background(Color.videoTextTertiary.opacity(0.3))
                
                settingsRow(icon: "doc.text.fill", title: "Terms of Use") {
                    openURL(ExternalURLs.termsOfUse)
                }
            }
        }
    }
    
    private func settingsRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.videoAccent)
                    .frame(width: 24)
                
                Text(title)
                    .font(.videoBody)
                    .foregroundColor(.videoTextPrimary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.videoTextTertiary)
            }
            .padding(.horizontal, VideoSpacing.md)
            .padding(.vertical, VideoSpacing.lg)
        }
    }
    
    private var appFooter: some View {
        VStack(spacing: VideoSpacing.xs) {
            Text("\(BrandConfig.appName) v\(Bundle.main.appVersion)")
                .font(.videoCaption)
                .foregroundColor(.videoTextTertiary)
            
            Text(BrandConfig.appFooterMessage)
                .font(.videoCaption)
                .foregroundColor(.videoTextTertiary)
        }
    }
    
    // DEBUG: Remove before release
    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: VideoSpacing.sm) {
            Text("🛠 DEBUG OPTIONS")
                .font(.videoCaptionSmall)
                .foregroundColor(.orange)
                .padding(.leading, VideoSpacing.xs)
            
            VideoCard(padding: 0) {
                VStack(spacing: 0) {
                    // Simulate Premium Toggle
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        
                        Text("Simulate Premium")
                            .font(.videoBody)
                            .foregroundColor(.videoTextPrimary)
                        
                        Spacer()
                        
                        Toggle("", isOn: $appState.debugSimulatePremium)
                            .labelsHidden()
                            .tint(.orange)
                    }
                    .padding(.horizontal, VideoSpacing.md)
                    .padding(.vertical, VideoSpacing.sm + 2)
                    
                    Divider().background(Color.orange.opacity(0.3))
                    
                    // Reset Onboarding
                    Button {
                        appState.resetOnboarding()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            
                            Text("Reset Onboarding")
                                .font(.videoBody)
                                .foregroundColor(.videoTextPrimary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, VideoSpacing.md)
                        .padding(.vertical, VideoSpacing.sm + 2)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium)
                    .stroke(Color.orange.opacity(0.5), lineWidth: 1)
            )
        }
    }
    #endif
    
    private func openURL(_ url: URL) {
        UIApplication.shared.open(url)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProfileView()
            .environmentObject(AppState.shared)
    }
}
