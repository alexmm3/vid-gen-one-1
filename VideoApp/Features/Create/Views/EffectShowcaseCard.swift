//
//  EffectShowcaseCard.swift
//  AIVideo
//
//  Large showcase card for the horizontal effect carousel.
//  Displays a looping video preview with an optional "before" input image
//  and the effect name overlaid on a gradient.
//

import SwiftUI

struct EffectShowcaseCard: View {
    let effect: Effect
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let isCentered: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.shared.selection()
            onSelect()
        }) {
            ZStack(alignment: .bottom) {
                videoLayer
                gradientOverlay
                contentOverlay
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: VideoSpacing.radiusXLarge))
            .shadow(color: .black.opacity(isCentered ? 0.5 : 0.25),
                    radius: isCentered ? 24 : 12,
                    x: 0,
                    y: isCentered ? 8 : 4)
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.97))
    }

    // MARK: - Video / Thumbnail Layer

    private var videoLayer: some View {
        ZStack {
            VideoThumbnailView(
                thumbnailUrl: effect.fullThumbnailUrl,
                videoUrl: effect.fullPreviewUrl
            )

            if isCentered {
                LoopingRemoteVideoPlayer(url: effect.fullPreviewUrl)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipped()
    }

    // MARK: - Bottom Gradient

    private var gradientOverlay: some View {
        LinearGradient(
            colors: [
                .clear,
                .clear,
                .black.opacity(0.3),
                .black.opacity(0.85)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Text + Before Image Overlay

    private var contentOverlay: some View {
        HStack(alignment: .bottom, spacing: VideoSpacing.sm) {
            beforeImageBadge
            effectInfo
            Spacer(minLength: 0)
        }
        .padding(VideoSpacing.md)
    }

    @ViewBuilder
    private var beforeImageBadge: some View {
        if let url = effect.fullSampleInputImageUrl {
            VStack(spacing: 4) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.videoSurface
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)

                Text("Original")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private var effectInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(effect.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)

            if let description = effect.description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.videoBackground.ignoresSafeArea()
        EffectShowcaseCard(
            effect: .sample,
            cardWidth: 320,
            cardHeight: 480,
            isCentered: true,
            onSelect: {}
        )
    }
}
