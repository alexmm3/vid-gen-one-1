//
//  Colors.swift
//  AIVideo
//
//  Design system: dark theme with neon polycolor accents and gradients
//  Primary: electric cyan. Secondary: violet & fuchsia for gradients.
//

import SwiftUI

extension Color {
    // MARK: - Primary Colors
    
    /// Deep black background (#0A0A0A)
    static let videoBlack = Color(hex: "0A0A0A")
    
    /// Slightly cool dark for depth (#0D0E12)
    static let videoBlackCool = Color(hex: "0D0E12")
    
    /// Pure black for contrast (#000000)
    static let videoPureBlack = Color(hex: "000000")
    
    /// Clean white for text (#FFFFFF)
    static let videoWhite = Color(hex: "FFFFFF")
    
    // MARK: - Accent Colors (Neon Polycolor)
    
    /// Primary accent – electric cyan (#C8A96E). Used for icons, links, borders.
    static let videoAccent = Color(hex: "C8A96E")
    
    /// Secondary accent – violet (#A855F7). Used in gradients and secondary highlights.
    static let videoAccentSecondary = Color(hex: "A855F7")
    
    /// Tertiary accent – fuchsia (#D946EF). Used in marketing and CTA gradients.
    static let videoAccentTertiary = Color(hex: "D946EF")
    
    /// Marketing gradient start – bright cyan
    static let videoMarketing = Color(hex: "C8A96E")
    
    /// Marketing gradient end – fuchsia
    static let videoMarketingEnd = Color(hex: "D946EF")
    
    // MARK: - Surface Colors
    
    /// Dark surface for cards (#1A1A1A)
    static let videoSurface = Color(hex: "1A1A1A")
    
    /// Slightly lighter surface (#242424)
    static let videoSurfaceLight = Color(hex: "242424")
    
    // MARK: - Text Colors
    
    /// Primary text – white
    static let videoTextPrimary = Color.white
    
    /// Secondary text – 70% white
    static let videoTextSecondary = Color.white.opacity(0.7)
    
    /// Tertiary text – 50% white
    static let videoTextTertiary = Color.white.opacity(0.5)
    
    /// Disabled text – 30% white
    static let videoTextDisabled = Color.white.opacity(0.3)
    
    // MARK: - Semantic Colors
    
    /// Primary background
    static let videoBackground = videoBlack
    
    /// Card background
    static let videoCardBackground = videoSurface
    
    /// Primary accent for CTAs (same as videoAccent for compatibility)
    static let videoPrimary = videoAccent
    
    // MARK: - Status Colors
    
    /// Success – bright cyan to match accent
    static let videoSuccess = Color(hex: "C8A96E")
    
    /// Warning – neon amber
    static let videoWarning = Color(hex: "FBBF24")
    
    /// Error – coral red
    static let videoError = Color(hex: "F87171")
}

// MARK: - Hex Color Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Gradient Definitions

extension LinearGradient {
    /// Subtle white-to-gray gradient (decorative use only)
    static let videoAccentGradient = LinearGradient(
        colors: [Color.white, Color.white.opacity(0.85)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Marketing gradient — kept as alias for compatibility, now solid white
    static let videoMarketingGradient = LinearGradient(
        colors: [Color.white, Color.white],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Dark overlay gradient for video backgrounds
    static let videoVideoOverlay = LinearGradient(
        colors: [.clear, Color.videoBlack.opacity(0.7), Color.videoBlack],
        startPoint: .center,
        endPoint: .bottom
    )
    
    /// Subtle surface gradient
    static let videoSurfaceGradient = LinearGradient(
        colors: [Color(hex: "1A1A1A"), Color(hex: "0A0A0A")],
        startPoint: .top,
        endPoint: .bottom
    )
    
    /// Processing / loading gradient — subtle white pulse
    static let videoProcessingGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.6),
            Color.white.opacity(0.9),
            Color.white.opacity(0.6)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Soft neutral glow gradient (replaces neon glow)
    static let videoNeonGlowGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.08),
            Color.white.opacity(0.04),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
