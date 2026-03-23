//
//  HistoryItemCard.swift
//  AIVideo
//
//  Card view for displaying a generation in My Videos grid
//

import SwiftUI

struct HistoryItemCard: View {
    let generation: LocalGeneration
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.videoSurface
                
                if let url = generation.effectiveVideoUrl {
                    LoopingRemoteVideoPlayer(url: url)
                } else {
                    // Placeholder for failed/pending
                    Image(systemName: "video.slash")
                        .font(.system(size: 24))
                        .foregroundColor(.videoTextTertiary)
                }
                
                // Gradient overlay
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 80)
                }
                
                // Info overlay
                VStack(spacing: 0) {
                    // Custom template badge
                    if generation.isCustomTemplate {
                        HStack {
                            Spacer()
                            Text("Custom")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.videoBlack)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white)
                                .cornerRadius(4)
                                .padding(VideoSpacing.xs)
                        }
                    }
                    
                    Spacer()
                    
                    // Bottom text info - constrained to geometry width
                    VStack(alignment: .leading, spacing: 2) {
                        Text(generation.displayName)
                            .font(.videoCaption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(generation.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.videoCaptionSmall)
                            .foregroundColor(.videoTextTertiary)
                    }
                    .frame(width: geometry.size.width - (VideoSpacing.sm * 2), alignment: .leading)
                    .padding(VideoSpacing.sm)
                }
            }
            .id(generation.id) // CRITICAL: Force unique view hierarchy per generation
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(9/16, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium))
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.videoBackground.ignoresSafeArea()
        
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            ForEach(LocalGeneration.samples) { generation in
                HistoryItemCard(generation: generation)
            }
        }
        .padding()
    }
}
