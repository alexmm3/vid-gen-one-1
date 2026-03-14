//
//  VideoCard.swift
//  AIVideo
//
//  Card components for dark theme UI
//

import SwiftUI

// MARK: - Base Card

struct VideoCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = VideoSpacing.cardPadding
    var cornerRadius: CGFloat = VideoSpacing.radiusMedium
    
    init(
        padding: CGFloat = VideoSpacing.cardPadding,
        cornerRadius: CGFloat = VideoSpacing.radiusMedium,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.videoSurface)
            )
    }
}

// MARK: - Bordered Card

struct VideoBorderedCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = VideoSpacing.cardPadding
    var cornerRadius: CGFloat = VideoSpacing.radiusMedium
    var borderColor: Color = .videoTextTertiary
    
    init(
        padding: CGFloat = VideoSpacing.cardPadding,
        cornerRadius: CGFloat = VideoSpacing.radiusMedium,
        borderColor: Color = .videoTextTertiary,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.borderColor = borderColor
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.videoSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

// MARK: - Selected Card (with accent border)

struct VideoSelectedCard<Content: View>: View {
    let content: Content
    let isSelected: Bool
    var padding: CGFloat = VideoSpacing.cardPadding
    var cornerRadius: CGFloat = VideoSpacing.radiusMedium
    
    init(
        isSelected: Bool,
        padding: CGFloat = VideoSpacing.cardPadding,
        cornerRadius: CGFloat = VideoSpacing.radiusMedium,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.videoSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isSelected ? Color.videoAccent : Color.videoTextTertiary.opacity(0.5),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.videoBackground.ignoresSafeArea()
        
        VStack(spacing: VideoSpacing.lg) {
            VideoCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Basic Card")
                        .font(.videoHeadline)
                        .foregroundColor(.videoTextPrimary)
                    Text("Card content goes here")
                        .font(.videoBody)
                        .foregroundColor(.videoTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            VideoBorderedCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bordered Card")
                        .font(.videoHeadline)
                        .foregroundColor(.videoTextPrimary)
                    Text("With subtle border")
                        .font(.videoBody)
                        .foregroundColor(.videoTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            VideoSelectedCard(isSelected: true) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected Card")
                        .font(.videoHeadline)
                        .foregroundColor(.videoTextPrimary)
                    Text("With accent border")
                        .font(.videoBody)
                        .foregroundColor(.videoTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }
}
