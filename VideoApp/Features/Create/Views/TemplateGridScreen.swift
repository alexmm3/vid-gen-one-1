//
//  TemplateGridScreen.swift
//  AIVideo
//
//  Full screen template gallery with 2-column vertical grid
//

import SwiftUI
import AVFoundation

struct TemplateGridScreen: View {
    let templates: [VideoTemplate]
    let onSelect: (VideoTemplate) -> Void
    var title: String = "All Videos"
    
    @Environment(\.dismiss) private var dismiss
    
    private let columns = [
        GridItem(.flexible(), spacing: VideoSpacing.sm),
        GridItem(.flexible(), spacing: VideoSpacing.sm)
    ]
    
    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()
            
            if templates.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: VideoSpacing.sm) {
                        ForEach(templates) { template in
                            templateCard(for: template)
                        }
                    }
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                    .padding(.top, VideoSpacing.md)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
    
    private var emptyState: some View {
        VStack(spacing: VideoSpacing.md) {
            Image(systemName: "video.slash")
                .font(.system(size: 50))
                .foregroundColor(.videoTextTertiary)
            
            Text("No Videos")
                .font(.videoHeadline)
                .foregroundColor(.videoTextPrimary)
            
            Text("No videos in this category yet")
                .font(.videoBody)
                .foregroundColor(.videoTextSecondary)
        }
    }
    
    private func templateCard(for template: VideoTemplate) -> some View {
        Button {
            HapticManager.shared.selection()
            onSelect(template)
        } label: {
            GeometryReader { geometry in
                ZStack {
                    // Cached thumbnail underlay — renders instantly from image cache
                    VideoThumbnailView(thumbnailUrl: template.fullThumbnailUrl, videoUrl: template.fullPreviewUrl)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    
                    // Looping video player — uses lightweight preview URL for grid cards.
                    // Full video (template.videoUrl) is reserved for AI generation & detail view.
                    LoopingRemoteVideoPlayer(url: template.fullPreviewUrl)
                    
                    // Gradient overlay with name
                    VStack {
                        Spacer()
                        HStack {
                            Text(template.name)
                                .font(.videoCaption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(VideoSpacing.sm)
                        .background(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .id(template.id) // CRITICAL: Force unique view hierarchy per template
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .aspectRatio(9/16, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium))
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Effect Grid Screen (same layout for effects)

struct EffectGridScreen: View {
    let effects: [Effect]
    let onSelect: (Effect) -> Void
    var title: String = "All Effects"

    private let columns = [
        GridItem(.flexible(), spacing: VideoSpacing.sm),
        GridItem(.flexible(), spacing: VideoSpacing.sm)
    ]

    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()

            if effects.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: VideoSpacing.sm) {
                        ForEach(effects) { effect in
                            effectCard(for: effect)
                        }
                    }
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                    .padding(.top, VideoSpacing.md)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var emptyState: some View {
        VStack(spacing: VideoSpacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 50))
                .foregroundColor(.videoTextTertiary)
            Text("No Effects")
                .font(.videoHeadline)
                .foregroundColor(.videoTextPrimary)
            Text("No effects in this category yet")
                .font(.videoBody)
                .foregroundColor(.videoTextSecondary)
        }
    }

    private func effectCard(for effect: Effect) -> some View {
        Button {
            HapticManager.shared.selection()
            onSelect(effect)
        } label: {
            GeometryReader { geometry in
                ZStack {
                    VideoThumbnailView(thumbnailUrl: effect.fullThumbnailUrl, videoUrl: effect.fullPreviewUrl)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    LoopingRemoteVideoPlayer(url: effect.fullPreviewUrl)
                    VStack {
                        Spacer()
                        HStack {
                            Text(effect.name)
                                .font(.videoCaption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(VideoSpacing.sm)
                        .background(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .id(effect.id) // CRITICAL: Force unique view hierarchy per effect
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .aspectRatio(9/16, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium))
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TemplateGridScreen(
            templates: VideoTemplate.samples,
            onSelect: { _ in }
        )
    }
}
