//
//  TemplateDetailView.swift
//  AIVideo
//
//  Detail view for a single video template
//

import SwiftUI

struct TemplateDetailView: View {
    let template: VideoTemplate
    
    @State private var navigateToPhotoUpload = false
    @State private var isMuted = false
    
    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Large video player
                videoPlayer
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                    .padding(.top, VideoSpacing.sm)
                
                // Info section
                infoSection
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                    .padding(.top, VideoSpacing.lg)
                
                Spacer()
                
                // CTA Button
                VideoButton(title: "Use This Video") {
                    HapticManager.shared.mediumImpact()
                    navigateToPhotoUpload = true
                    Analytics.track(.templateSelected(
                        templateId: template.id.uuidString,
                        templateName: template.name
                    ))
                }
                .padding(.horizontal, VideoSpacing.screenHorizontal)
                .padding(.bottom, VideoSpacing.xxl)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $navigateToPhotoUpload) {
            PhotoUploadView(template: template)
        }
    }
    
    // MARK: - Video Player
    
    private var videoPlayer: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                if let url = template.fullVideoUrl {
                    RemoteVideoPlayer(
                        url: url,
                        isPlaying: true,
                        isMuted: isMuted
                    )
                } else {
                    Color.videoSurface
                        .overlay(
                            Image(systemName: "video.slash")
                                .font(.system(size: 40))
                                .foregroundColor(.videoTextTertiary)
                        )
                }
            }
            .aspectRatio(9/16, contentMode: .fit)
            .cornerRadius(VideoSpacing.radiusLarge)
            .videoCardShadow()
            
            // Mute button
            VideoMuteButton(isMuted: $isMuted)
                .padding(VideoSpacing.sm)
        }
    }
    
    // MARK: - Info Section
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: VideoSpacing.sm) {
            Text(template.name)
                .font(.videoDisplayMedium)
                .foregroundColor(.videoTextPrimary)
            
            if let description = template.description {
                Text(description)
                    .font(.videoBody)
                    .foregroundColor(.videoTextSecondary)
            }
            
            // Metadata row
            HStack(spacing: VideoSpacing.lg) {
                if let duration = template.durationSeconds {
                    metadataItem(icon: "clock", text: "\(duration) seconds")
                }
                
                metadataItem(icon: "music.note", text: "Original audio")
            }
            .padding(.top, VideoSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func metadataItem(icon: String, text: String) -> some View {
        HStack(spacing: VideoSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(text)
                .font(.videoCaption)
        }
        .foregroundColor(.videoTextTertiary)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TemplateDetailView(template: .sample)
    }
}
