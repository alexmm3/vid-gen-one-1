//
//  ProfileView.swift
//  AIVideo
//
//  Profile tab — minimal editorial layout
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @State private var showPaywall = false
    
    // Warm accent — a muted sand/gold tone that feels premium without being flashy
    private let accent = Color(hex: "C8A96E")
    
    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if appState.isPremiumUser, appState.generationLimit != nil {
                        quotaCard
                            .padding(.top, VideoSpacing.xl)
                    } else if !appState.isPremiumUser {
                        upgradeCard
                            .padding(.top, VideoSpacing.xl)
                    }
                    
                    linksSection
                        .padding(.top, VideoSpacing.xxxl)
                    
                    #if DEBUG
                    debugSection
                        .padding(.top, VideoSpacing.xxl)
                        .padding(.horizontal, VideoSpacing.screenHorizontal)
                    #endif
                    
                    footerSection
                        .padding(.top, VideoSpacing.huge)
                        .padding(.bottom, 120)
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(source: .profile) {
                appState.setPremiumStatus(true)
            }
        }
    }
    
    // MARK: - Upgrade Card (Free users)
    
    private var upgradeCard: some View {
        Button { showPaywall = true } label: {
            VStack(spacing: VideoSpacing.lg) {
                VStack(spacing: 6) {
                    Text("Get More from Your Videos")
                        .font(.videoHeadline)
                        .foregroundColor(.white)
                    
                    Text("HD video  ·  40 generations  ·  All effects")
                        .font(.videoCaption)
                        .foregroundColor(.white.opacity(0.45))
                        .tracking(0.3)
                }
                
                HStack(spacing: VideoSpacing.xs) {
                    Text("Go Premium")
                        .font(.videoBody)
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.videoBlack)
                .frame(maxWidth: .infinity)
                .frame(height: VideoSpacing.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: VideoSpacing.radiusSmall)
                        .fill(accent)
                )
            }
            .padding(VideoSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: VideoSpacing.radiusLarge)
                    .fill(Color.videoSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VideoSpacing.radiusLarge)
                    .stroke(accent.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, VideoSpacing.screenHorizontal)
    }

    // MARK: - Quota Card (Subscribers)

    private var quotaCard: some View {
        let limit = appState.generationLimit ?? 0
        let used = appState.generationsUsed ?? 0
        let progress = limit > 0 ? Double(used) / Double(limit) : 0
        let isExhausted = used >= limit && limit > 0

        return VStack(spacing: VideoSpacing.md) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundColor(accent)

                Text(isExhausted ? "Generations used up" : "\(used) of \(limit) generations")
                    .font(.videoSubheadline)
                    .foregroundColor(.white)

                Spacer()
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.8), accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: max(0, geometry.size.width * min(progress, 1.0)),
                            height: 8
                        )
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 8)

            // Reset date
            if let expiresAt = appState.subscriptionExpiresAt {
                HStack {
                    Text("Resets on \(expiresAt.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.videoCaption)
                        .foregroundColor(.white.opacity(0.45))
                    Spacer()
                }
            }
        }
        .padding(VideoSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: VideoSpacing.radiusLarge)
                .fill(Color.videoSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VideoSpacing.radiusLarge)
                .stroke(accent.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, VideoSpacing.screenHorizontal)
    }

    // MARK: - Links
    
    private var linksSection: some View {
        VStack(spacing: 0) {
            linkRow(title: "Rate the App", icon: "star") {
                Analytics.track(.rateAppTapped)
                openURL(ExternalURLs.appStoreReview)
            }
            
            linkDivider
            
            linkRow(title: "Contact Support", icon: "envelope") {
                Analytics.track(.contactSupportTapped)
                openURL(ExternalURLs.support)
            }
            
            linkDivider
            
            linkRow(title: "Privacy Policy", icon: "lock.shield") {
                openURL(ExternalURLs.privacyPolicy)
            }
            
            linkDivider
            
            linkRow(title: "Terms of Use", icon: "doc.plaintext") {
                openURL(ExternalURLs.termsOfUse)
            }
        }
        .padding(.horizontal, VideoSpacing.screenHorizontal)
    }
    
    private func linkRow(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: VideoSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(width: 26)
                
                Text(title)
                    .font(.videoBody)
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.2))
            }
            .padding(.vertical, VideoSpacing.lg)
        }
    }
    
    private var linkDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
            .padding(.leading, 40)
    }
    
    // MARK: - Footer
    
    private var footerSection: some View {
        VStack(spacing: 4) {
            Text(BrandConfig.appName)
                .font(.videoCaption)
                .foregroundColor(.white.opacity(0.2))
                .tracking(1.5)
            
            Text("v\(Bundle.main.appVersion)")
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(.white.opacity(0.15))
        }
    }
    
    // DEBUG: Remove before release
    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: VideoSpacing.sm) {
            Text("DEBUG")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.orange.opacity(0.6))
                .tracking(1)
            
            VStack(spacing: 0) {
                HStack {
                    Text("Simulate Premium")
                        .font(.videoBodySmall)
                        .foregroundColor(.videoTextPrimary)
                    Spacer()
                    Toggle("", isOn: $appState.debugSimulatePremium)
                        .labelsHidden()
                        .tint(.orange)
                }
                .padding(.horizontal, VideoSpacing.md)
                .padding(.vertical, VideoSpacing.sm)
                
                Rectangle().fill(Color.orange.opacity(0.15)).frame(height: 1)
                
                Button {
                    appState.resetOnboarding()
                } label: {
                    HStack {
                        Text("Reset Onboarding")
                            .font(.videoBodySmall)
                            .foregroundColor(.videoTextPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, VideoSpacing.md)
                    .padding(.vertical, VideoSpacing.sm)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium)
                    .fill(Color.videoSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium)
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
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
