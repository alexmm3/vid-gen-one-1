//
//  CategorySection.swift
//  AIVideo
//
//  Horizontal scrolling section for a video category
//

import SwiftUI

struct CategorySection: View {
    let title: String
    let icon: String?
    let templates: [VideoTemplate]
    let onSelect: (VideoTemplate) -> Void
    let onShowAll: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: VideoSpacing.sm) {
            // Section header
            HStack {
                HStack(spacing: VideoSpacing.xs) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundColor(.videoAccent)
                    }
                    
                    Text(title)
                        .font(.videoSubheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.videoTextPrimary)
                }
                
                Spacer()
                
                Button {
                    HapticManager.shared.selection()
                    onShowAll()
                } label: {
                    HStack(spacing: 2) {
                        Text("Show All")
                            .font(.videoCaptionSmall)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.videoAccent)
                }
            }
            .padding(.horizontal, VideoSpacing.screenHorizontal)
            
            // Horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: VideoSpacing.sm) {
                    ForEach(templates) { template in
                        templateCard(for: template)
                    }
                }
                .padding(.horizontal, VideoSpacing.screenHorizontal)
            }
        }
    }
    
    private func templateCard(for template: VideoTemplate) -> some View {
        Button {
            HapticManager.shared.selection()
            onSelect(template)
        } label: {
            ZStack(alignment: .bottom) {
                // Cached thumbnail underlay — renders instantly from image cache
                // and prevents a blank flash when the video player is recreated
                VideoThumbnailView(thumbnailUrl: template.fullThumbnailUrl, videoUrl: template.fullPreviewUrl)
                    .frame(width: 140, height: 200)
                    .clipped()
                
                // Looping video player — uses lightweight preview URL for cards.
                // The full video (template.videoUrl) is used for AI generation and
                // full-screen playback only — NEVER preview_url.
                LoopingRemoteVideoPlayer(url: template.fullPreviewUrl)
                    .frame(width: 140, height: 200)
                
                // Title overlay
                Text(template.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(width: 140, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .id(template.id) // CRITICAL: Force unique view hierarchy per template
            .frame(width: 140, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium))
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Effect Category Section (same layout as CategorySection, for effects)

struct EffectCategorySection: View {
    let title: String
    let icon: String?
    let effects: [Effect]
    let onSelect: (Effect) -> Void
    let onShowAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VideoSpacing.sm) {
            HStack {
                HStack(spacing: VideoSpacing.xs) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundColor(.videoAccent)
                    }
                    Text(title)
                        .font(.videoSubheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.videoTextPrimary)
                }
                Spacer()
                Button {
                    HapticManager.shared.selection()
                    onShowAll()
                } label: {
                    HStack(spacing: 2) {
                        Text("Show All")
                            .font(.videoCaptionSmall)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.videoAccent)
                }
            }
            .padding(.horizontal, VideoSpacing.screenHorizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: VideoSpacing.sm) {
                    ForEach(effects) { effect in
                        effectCard(for: effect)
                    }
                }
                .padding(.horizontal, VideoSpacing.screenHorizontal)
            }
        }
    }

    private func effectCard(for effect: Effect) -> some View {
        Button {
            HapticManager.shared.selection()
            onSelect(effect)
        } label: {
            ZStack(alignment: .bottom) {
                VideoThumbnailView(thumbnailUrl: effect.fullThumbnailUrl, videoUrl: effect.fullPreviewUrl)
                    .frame(width: 140, height: 200)
                    .clipped()
                LoopingRemoteVideoPlayer(url: effect.fullPreviewUrl)
                    .frame(width: 140, height: 200)
                Text(effect.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(width: 140, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .id(effect.id) // CRITICAL: Force unique view hierarchy per effect
            .frame(width: 140, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium))
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Your Videos Section

struct UserVideosSection: View {
    let userVideos: [LocalUserVideo]
    let onSelect: (LocalUserVideo) -> Void
    let onDelete: (LocalUserVideo) -> Void
    let onAddNew: () -> Void
    let onShowAll: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: VideoSpacing.sm) {
            // Section header
            HStack {
                HStack(spacing: VideoSpacing.xs) {
                    Image(systemName: "person.crop.rectangle.stack")
                        .font(.system(size: 14))
                        .foregroundColor(.videoAccent)
                    
                    Text("Your Videos")
                        .font(.videoSubheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.videoTextPrimary)
                }
                
                Spacer()
                
                if !userVideos.isEmpty {
                    Button {
                        HapticManager.shared.selection()
                        onShowAll()
                    } label: {
                        HStack(spacing: 2) {
                            Text("Show All")
                                .font(.videoCaptionSmall)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.videoAccent)
                    }
                }
            }
            .padding(.horizontal, VideoSpacing.screenHorizontal)
            
            // Horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: VideoSpacing.sm) {
                    // Add new button (always first)
                    addNewCard
                    
                    // User videos
                    ForEach(userVideos) { video in
                        userVideoCard(for: video)
                    }
                }
                .padding(.horizontal, VideoSpacing.screenHorizontal)
            }
        }
    }
    
    private var addNewCard: some View {
        Button {
            HapticManager.shared.selection()
            onAddNew()
        } label: {
            VStack(spacing: VideoSpacing.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.videoAccent)
                
                Text("Add Video")
                    .font(.videoCaption)
                    .foregroundColor(.videoTextSecondary)
            }
            .frame(width: 140, height: 200)
            .background(Color.videoSurface)
            .cornerRadius(VideoSpacing.radiusMedium)
            .overlay(
                RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium)
                    .stroke(Color.videoTextTertiary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    private func userVideoCard(for video: LocalUserVideo) -> some View {
        Button {
            HapticManager.shared.selection()
            onSelect(video)
        } label: {
            ZStack(alignment: .bottom) {
                // Video player with cached thumbnail underlay
                if let url = video.effectiveVideoUrl {
                    VideoThumbnailView(thumbnailUrl: nil, videoUrl: url)
                        .frame(width: 140, height: 200)
                        .clipped()
                    
                    LoopingRemoteVideoPlayer(url: url)
                        .frame(width: 140, height: 200)
                } else {
                    Rectangle()
                        .fill(Color.videoSurface)
                        .frame(width: 140, height: 200)
                }
                
                // Upload status badge
                if !video.isUploaded {
                    VStack {
                        HStack {
                            Image(systemName: "icloud.and.arrow.up")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.orange)
                                .cornerRadius(4)
                                .padding(4)
                                .padding(4)
                            Spacer()
                        }
                        Spacer()
                    }
                    .frame(width: 140, height: 200)
                }
                
                // Name overlay
                Text(video.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(width: 140, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .id(video.id) // CRITICAL: Force unique view hierarchy per video
            .frame(width: 140, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium))
        }
        .buttonStyle(ScaleButtonStyle())
        .contextMenu {
            Button(role: .destructive) {
                onDelete(video)
            } label: {
                Label("Delete Video", systemImage: "trash")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: VideoSpacing.lg) {
        CategorySection(
            title: "Trending",
            icon: "flame.fill",
            templates: VideoTemplate.samples,
            onSelect: { _ in },
            onShowAll: {}
        )
        
        UserVideosSection(
            userVideos: [],
            onSelect: { _ in },
            onDelete: { _ in },
            onAddNew: {},
            onShowAll: {}
        )
    }
    .background(Color.videoBackground)
}
