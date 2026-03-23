//
//  PaywallView.swift
//  AIVideo
//
//  Subscription paywall view
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    let source: AnalyticsEvent.PaywallSource
    var onComplete: (() -> Void)?

    @StateObject private var viewModel = PaywallViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geometry in
            let sectionSpacing = Self.dynamicSectionSpacing(for: geometry.size.height)

            ZStack {
                // Video background with overlay - fill entire screen
                Color.black
                    .ignoresSafeArea()

                LoopingVideoPlayer(videoName: "paywall_bg")
                    .ignoresSafeArea(.all)

                // Gradient black overlay (50% at top to 100% at bottom)
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.5),
                        Color.black.opacity(1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: sectionSpacing) {
                            // Header
                            headerSection

                            // Benefits
                            benefitsSection

                            // Pricing cards
                            pricingSection

                            // Subscribe button + legal (same section spacing as above)
                            subscribeSection
                        }
                        .padding(.horizontal, VideoSpacing.screenHorizontal)
                        .padding(.top, sectionSpacing)
                        .padding(.bottom, sectionSpacing)
                    }

                    // "Maybe later" dismiss button
                    maybeLaterButton
                        .padding(.bottom, VideoSpacing.md)
                }
            }
        }
        .task {
            await viewModel.loadProducts()
            Analytics.track(.paywallShown(source: source))
        }
        .onChange(of: viewModel.purchaseComplete) { complete in
            if complete {
                onComplete?()
                dismiss()
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.showError = false }
        } message: {
            Text(viewModel.error ?? "Unknown error")
        }
    }

    // MARK: - Dynamic Spacing

    /// Computes section spacing proportional to available screen height.
    /// On regular devices (iPhone 14/15/16), spacing stays at the default 24pt.
    /// On smaller screens (iPhone SE), spacing compresses to ~17-18pt,
    /// saving ~30pt total to help keep the legal footer visible without scrolling.
    private static func dynamicSectionSpacing(for availableHeight: CGFloat) -> CGFloat {
        max(VideoSpacing.sm, min(VideoSpacing.xl, availableHeight * 0.028))
    }

    // MARK: - Maybe Later Button

    private var maybeLaterButton: some View {
        Button {
            Analytics.track(.paywallDismissed(source: source))
            dismiss()
        } label: {
            Text("Maybe later")
                .font(.videoSubheadline)
                .underline()
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Subscribe Section

    private var subscribeSection: some View {
        VStack(spacing: VideoSpacing.sm) {
            subscribeButton
            legalFooter
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: VideoSpacing.xs) {
            ZStack {
                Circle()
                    .fill(Color.videoWhite)
                    .frame(width: 50, height: 50)

                Image(systemName: "crown.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.videoBlack)
            }

            Text("Unlock All Effects")
                .font(.videoDisplayLarge)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("Effects you won't find anywhere else")
                .font(.videoBody)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Benefits Section

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: VideoSpacing.md) {
            benefitRow(
                icon: "video.badge.plus",
                title: viewModel.planInfo(for: .monthly)
                    .map { "Up to \($0.generationLimit) Generations" } ?? "More Generations",
                subtitle: "Create up to 50 videos per month"
            )
            benefitRow(icon: "bolt.fill", title: "Skip the Line", subtitle: "Your videos render first")
            benefitRow(icon: "flame.fill", title: "Exclusive Effects", subtitle: "New drops every week")
            benefitRow(icon: "sparkles", title: "Full HD Export", subtitle: "Crisp, share-ready quality")
        }
        .padding(VideoSpacing.md)
        .background(Color.black.opacity(0.85))
        .cornerRadius(VideoSpacing.radiusLarge)
    }

    private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: VideoSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.videoMarketing.opacity(0.2))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.videoMarketing)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.videoSubheadline)
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.videoCaption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()
        }
    }

    // MARK: - Pricing Section

    private var pricingSection: some View {
        VStack(spacing: VideoSpacing.sm) {
            ForEach(SubscriptionPlan.allCases, id: \.self) { plan in
                pricingCard(for: plan)
            }
        }
    }

    private func pricingCard(for plan: SubscriptionPlan) -> some View {
        let isSelected = viewModel.selectedPlan == plan
        let product = plan == .weekly ? viewModel.weeklyProduct : viewModel.monthlyProduct
        let planInfo = viewModel.planInfo(for: plan)
        let limitDescription = planInfo?.limitDescription ?? plan.defaultLimitDescription

        return Button {
            viewModel.selectPlan(plan)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.displayName)
                        .font(.videoHeadline)
                        .foregroundColor(.white)

                    // Show limit description (e.g., "10 videos per week")
                    Text(limitDescription)
                        .font(.videoCaption)
                        .foregroundColor(.videoMarketing)
                }

                Spacer()

                // Price from StoreKit, spinner while loading
                if let product = product {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(product.displayPrice)
                            .font(.videoHeadline)
                            .foregroundColor(.white)
                        Text(plan == .monthly ? "per month" : "per week")
                            .font(.videoCaptionSmall)
                            .foregroundColor(.white.opacity(0.6))
                    }
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.5)))
                        .scaleEffect(0.8)
                }

                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.videoMarketing : Color.white.opacity(0.5), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(Color.videoMarketing)
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .padding(VideoSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium)
                    .fill(Color.black.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium)
                    .stroke(
                        isSelected ? Color.videoMarketing : Color.white.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                // Best Value badge on upper right edge
                if plan == .monthly {
                    Text("Save 20%")
                        .font(.videoCaptionSmall)
                        .fontWeight(.semibold)
                        .foregroundColor(.videoBlack)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "C8A96E"))
                        .cornerRadius(4)
                        .padding(.trailing, 12) // 10% gap from right edge
                        .offset(y: -10)
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Subscribe Button

    private var subscribeButton: some View {
        VideoButton(
            title: buttonTitle,
            action: {
                Task { await viewModel.purchase() }
            },
            isLoading: viewModel.isPurchasing,
            style: .marketing
        )
        .opacity(viewModel.selectedProduct == nil ? 0.5 : 1)
        .disabled(viewModel.selectedProduct == nil)
    }

    private var buttonTitle: String {
        if let product = viewModel.selectedProduct {
            return "Start Creating — \(product.displayPrice)"
        }
        if viewModel.isLoading {
            return "Loading..."
        }
        return "Start Creating"
    }

    // MARK: - Legal Footer

    private var legalFooter: some View {
        VStack(spacing: VideoSpacing.xs) {
            Text("Subscription auto-renews. Cancel anytime.")
                .font(.videoCaptionSmall)
                .foregroundColor(.white.opacity(0.6))

            HStack(spacing: VideoSpacing.md) {
                Link("Terms", destination: ExternalURLs.termsOfUse)
                Text("•")
                Link("Privacy", destination: ExternalURLs.privacyPolicy)
                Text("•")
                Button("Restore") {
                    Task { await viewModel.restore() }
                }
            }
            .font(.videoCaptionSmall)
            .foregroundColor(.white.opacity(0.6))
        }
    }
}

// MARK: - Preview

#Preview {
    PaywallView(source: .onboarding)
}
