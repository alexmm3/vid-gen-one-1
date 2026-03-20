//
//  TemplateCardView.swift
//  AIVideo
//
//  Card view for displaying template in gallery grid
//

import SwiftUI

struct TemplateCardView: View {
    let template: VideoTemplate
    
    var body: some View {
        Color.videoSurface
            .aspectRatio(9/16, contentMode: .fit)
            .overlay {
                ZStack {
                    LoopingRemoteVideoPlayer(url: template.fullPreviewUrl)
                    
                    // Gradient overlay at bottom
                    VStack {
                        Spacer()
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 80)
                    }
                    
                    // Play icon indicator
                    Image(systemName: "play.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                    
                    // Template info
                    VStack {
                        Spacer()
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .font(.videoCaption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                
                                if let duration = template.formattedDuration {
                                    Text(duration)
                                        .font(.videoCaptionSmall)
                                        .foregroundColor(.videoTextTertiary)
                                }
                            }
                            Spacer()
                        }
                        .padding(VideoSpacing.sm)
                    }
                }
                .id(template.id) // CRITICAL: Force unique view hierarchy per template
            }
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
            ForEach(VideoTemplate.samples) { template in
                TemplateCardView(template: template)
            }
        }
        .padding()
    }
}
