//
//  AIDataConsentView.swift
//  AIVideo
//
//  One-time consent screen shown before the first AI video generation.
//  Discloses what data is shared, with whom, and how it's handled
//  per Apple guidelines 5.1.1(i) and 5.1.2(i).
//

import SwiftUI

struct AIDataConsentView: View {
    let onAccept: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: VideoSpacing.xl) {
                        headerSection
                            .padding(.top, VideoSpacing.xxl)
                            .onAppear { Analytics.track(.aiConsentShown) }

                        disclosureList
                        
                        privacyPolicyLink
                        
                        Spacer(minLength: VideoSpacing.huge)
                    }
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                }
                
                consentButton
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: VideoSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.videoAccent.opacity(0.12))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 36))
                    .foregroundColor(.videoAccent)
            }
            
            Text("Data & Privacy")
                .font(.videoDisplayMedium)
                .foregroundColor(.videoTextPrimary)
            
            Text("To generate your video, we need to send some of your data to a third-party service. Here's exactly what that means.")
                .font(.videoBody)
                .foregroundColor(.videoTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Disclosure List
    
    private var disclosureList: some View {
        VStack(spacing: 0) {
            disclosureRow(
                icon: "photo",
                title: "What Data Is Sent",
                detail: "Your photo and the selected reference video are uploaded from your device to our servers and then sent to a third-party AI service for video generation. No other personal data is shared."
            )
            
            rowDivider
            
            disclosureRow(
                icon: "cpu",
                title: "Third-Party Provider",
                detail: "Your data is processed by ModelsLab, a third-party AI platform. Their servers receive your photo and reference video to generate the output."
            )
            
            rowDivider
            
            disclosureRow(
                icon: "clock",
                title: "How Long Data Is Stored",
                detail: "ModelsLab automatically deletes all uploaded content within 30 days of processing. No permanent copies of your photo or video are retained by the third party."
            )
            
            rowDivider
            
            disclosureRow(
                icon: "trash",
                title: "Deleting Your Data",
                detail: "When you delete a video in the app, it is immediately removed from our servers and from ModelsLab's servers. You are in full control of your content."
            )
            
            rowDivider
            
            disclosureRow(
                icon: "lock.shield",
                title: "Privacy Responsibility",
                detail: "ModelsLab is contractually obligated to protect your data during and after processing, in accorvideo with their privacy policy and applicable data protection laws."
            )
        }
        .background(
            RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium)
                .fill(Color.videoSurface)
        )
    }
    
    private func disclosureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: VideoSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.videoAccent)
                .frame(width: 24, height: 24)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: VideoSpacing.xxs) {
                Text(title)
                    .font(.videoSubheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.videoTextPrimary)
                
                Text(detail)
                    .font(.videoBodySmall)
                    .foregroundColor(.videoTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VideoSpacing.md)
        .padding(.vertical, VideoSpacing.sm)
    }
    
    private var rowDivider: some View {
        Divider()
            .background(Color.videoTextTertiary.opacity(0.2))
            .padding(.leading, VideoSpacing.md + 24 + VideoSpacing.md)
    }
    
    // MARK: - Privacy Policy Link
    
    private var privacyPolicyLink: some View {
        Link(destination: ExternalURLs.privacyPolicy) {
            HStack(spacing: VideoSpacing.xs) {
                Text("Read our full Privacy Policy")
                    .font(.videoBodySmall)
                    .foregroundColor(.videoAccent)
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.videoAccent)
            }
        }
    }
    
    // MARK: - Consent Button
    
    private var consentButton: some View {
        VStack(spacing: VideoSpacing.sm) {
            Divider()
                .background(Color.videoTextTertiary.opacity(0.2))
            
            VideoButton(
                title: "I Agree & Continue",
                icon: "checkmark.shield",
                action: {
                    Analytics.track(.aiConsentAccepted)
                    onAccept()
                    dismiss()
                }
            )
            .padding(.horizontal, VideoSpacing.screenHorizontal)
            .padding(.top, VideoSpacing.xs)
            .padding(.bottom, VideoSpacing.lg)
        }
        .background(Color.videoBackground)
    }
}

// MARK: - Preview

#Preview {
    AIDataConsentView(onAccept: {})
}
