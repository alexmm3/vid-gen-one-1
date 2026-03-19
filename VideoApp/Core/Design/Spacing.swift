//
//  Spacing.swift
//  AIVideo
//
//  Spacing system for consistent layout throughout the app
//  Based on 4pt grid system
//

import SwiftUI

// MARK: - Spacing Constants

enum VideoSpacing {
    // MARK: - Base Units (4pt Grid)
    
    /// 4pt - Minimum spacing
    static let xxs: CGFloat = 4
    
    /// 8pt - Tight spacing
    static let xs: CGFloat = 8
    
    /// 12pt - Compact spacing
    static let sm: CGFloat = 12
    
    /// 16pt - Standard spacing
    static let md: CGFloat = 16
    
    /// 20pt - Comfortable spacing
    static let lg: CGFloat = 20
    
    /// 24pt - Relaxed spacing
    static let xl: CGFloat = 24
    
    /// 32pt - Generous spacing
    static let xxl: CGFloat = 32
    
    /// 40pt - Section spacing
    static let xxxl: CGFloat = 40
    
    /// 48pt - Large section spacing
    static let huge: CGFloat = 48
    
    // MARK: - Semantic Spacing
    
    /// Standard horizontal padding for screens
    static let screenHorizontal: CGFloat = 20
    
    /// Standard vertical padding for screens
    static let screenVertical: CGFloat = 16
    
    /// Spacing between cards
    static let cardGap: CGFloat = 16
    
    /// Internal padding for cards
    static let cardPadding: CGFloat = 16
    
    /// Spacing between sections
    static let sectionGap: CGFloat = 32
    
    /// Spacing between form elements
    static let formElementGap: CGFloat = 16
    
    /// Spacing between list items
    static let listItemGap: CGFloat = 12
    
    // MARK: - Corner Radius
    
    /// Small radius for buttons (pill-ish)
    static let radiusSmall: CGFloat = 14
    
    /// Medium radius for cards
    static let radiusMedium: CGFloat = 12
    
    /// Large radius for modals
    static let radiusLarge: CGFloat = 16
    
    /// Extra large radius for sheets
    static let radiusXLarge: CGFloat = 24
    
    /// Full rounded (pill shape)
    static let radiusFull: CGFloat = 999
    
    // MARK: - Button Dimensions
    
    /// Standard button height
    static let buttonHeight: CGFloat = 56
    
    /// Small button height
    static let buttonHeightSmall: CGFloat = 44
    
    /// Minimum touch target
    static let minTouchTarget: CGFloat = 44
    
    // MARK: - Icon Sizes
    
    /// Small icon
    static let iconSmall: CGFloat = 16
    
    /// Medium icon
    static let iconMedium: CGFloat = 24
    
    /// Large icon
    static let iconLarge: CGFloat = 32
    
    /// Extra large icon
    static let iconXLarge: CGFloat = 48
}

// MARK: - Convenience Padding Modifiers

extension View {
    /// Apply standard screen padding
    func videoScreenPadding() -> some View {
        self.padding(.horizontal, VideoSpacing.screenHorizontal)
            .padding(.vertical, VideoSpacing.screenVertical)
    }
    
    /// Apply standard card padding
    func videoCardPadding() -> some View {
        self.padding(VideoSpacing.cardPadding)
    }
    
    /// Apply horizontal screen padding only
    func videoHorizontalPadding() -> some View {
        self.padding(.horizontal, VideoSpacing.screenHorizontal)
    }
    
    /// Apply vertical section padding
    func videoVerticalPadding() -> some View {
        self.padding(.vertical, VideoSpacing.lg)
    }
}

// MARK: - Shadow Definitions (Dark Theme Optimized)

struct VideoShadow {
    /// Subtle shadow for cards on dark background
    static let card = Shadow(
        color: Color.black.opacity(0.15),
        radius: 12,
        x: 0,
        y: 4
    )
    
    /// Elevated shadow for floating elements
    static let elevated = Shadow(
        color: Color.black.opacity(0.2),
        radius: 20,
        x: 0,
        y: 8
    )
    
    /// Soft neutral glow (replaces accent glow)
    static let glow = Shadow(
        color: Color.white.opacity(0.06),
        radius: 16,
        x: 0,
        y: 0
    )
}

struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func videoCardShadow() -> some View {
        self.shadow(
            color: VideoShadow.card.color,
            radius: VideoShadow.card.radius,
            x: VideoShadow.card.x,
            y: VideoShadow.card.y
        )
    }
    
    func videoElevatedShadow() -> some View {
        self.shadow(
            color: VideoShadow.elevated.color,
            radius: VideoShadow.elevated.radius,
            x: VideoShadow.elevated.x,
            y: VideoShadow.elevated.y
        )
    }
    
    func videoGlowShadow() -> some View {
        self.shadow(
            color: VideoShadow.glow.color,
            radius: VideoShadow.glow.radius,
            x: VideoShadow.glow.x,
            y: VideoShadow.glow.y
        )
    }
}
