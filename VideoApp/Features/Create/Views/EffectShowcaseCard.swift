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
    let onSelect: () -> Void

    @State private var showVideoPlayer = false

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
            showVideoPlayer = isCentered
        }
        .onChange(of: isCentered) { _, centered in
            if !centered { showVideoPlayer = false }
        }
        .task(id: isCentered) {
            guard isCentered, !showVideoPlayer else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            showVideoPlayer = true
        }
    }

    // MARK: - Video / Thumbnail Layer

    private var videoLayer: some View {
        ZStack {
            Color.videoSurface

            if showVideoPlayer {
                LoopingRemoteVideoPlayer(url: effect.fullPreviewUrl)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showVideoPlayer)
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
            onSelect: {}
        )
    }
}
