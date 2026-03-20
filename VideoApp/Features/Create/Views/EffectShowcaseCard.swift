//
//  EffectShowcaseCard.swift
//  AIVideo
//
//  Clean showcase card — pure video preview with no overlaid text or images.
//

import SwiftUI

struct EffectShowcaseCard: View {
    let effect: Effect
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let isCentered: Bool
    let shouldLoadVideo: Bool
    let shouldPlayVideo: Bool
    let onSelect: () -> Void

    @State private var isVideoReadyForDisplay = false

    var body: some View {
        Button(action: {
            HapticManager.shared.selection()
            onSelect()
        }) {
            videoLayer
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: VideoSpacing.radiusXLarge))
                .shadow(color: .black.opacity(isCentered ? 0.3 : 0.12),
                        radius: isCentered ? 20 : 10,
                        x: 0,
                        y: isCentered ? 6 : 3)
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.97))
        .onAppear {
            isVideoReadyForDisplay = false
        }
        .onChange(of: shouldLoadVideo) { _, shouldLoad in
            if !shouldLoad {
                isVideoReadyForDisplay = false
            }
        }
        .onChange(of: effect.fullPreviewUrl) { _, _ in
            isVideoReadyForDisplay = false
        }
    }

    // MARK: - Video / Thumbnail Layer

    private var videoLayer: some View {
        ZStack {
            if shouldLoadVideo {
                LoopingRemoteVideoPlayer(
                    url: effect.fullPreviewUrl,
                    isPlaying: shouldPlayVideo,
                    onReadyForDisplayChanged: { isReady in
                        guard isVideoReadyForDisplay != isReady else { return }
                        DispatchQueue.main.async {
                            guard isVideoReadyForDisplay != isReady else { return }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isVideoReadyForDisplay = isReady
                            }
                        }
                    }
                )
                .transition(.opacity)
            }

            VideoPosterFrameView(videoURL: effect.fullPreviewUrl)
                .opacity(isVideoReadyForDisplay ? 0 : 1)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.25), value: isVideoReadyForDisplay)
        .frame(width: cardWidth, height: cardHeight)
        .clipped()
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
            shouldLoadVideo: true,
            shouldPlayVideo: true,
            onSelect: {}
        )
    }
}
