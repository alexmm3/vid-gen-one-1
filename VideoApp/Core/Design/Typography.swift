//
//  Typography.swift
//  AIVideo
//
//  Typography system with modern, bold fonts for video/viral aesthetic
//

import SwiftUI

// MARK: - Font Definitions

extension Font {
    // MARK: - Display Fonts (Bold & Impactful)
    
    /// 44pt, System, Black - Cinematic hero titles (onboarding)
    static let videoDisplayHero = Font.system(size: 44, weight: .black, design: .default)
    
    /// 32pt, System, Black - For main titles
    static let videoDisplayLarge = Font.system(size: 32, weight: .black, design: .default)
    
    /// 24pt, System, Bold - For section headers
    static let videoDisplayMedium = Font.system(size: 24, weight: .bold, design: .default)
    
    /// 20pt, System, Bold - For card titles
    static let videoDisplaySmall = Font.system(size: 20, weight: .bold, design: .default)
    
    // MARK: - Body Fonts
    
    /// 18pt, System, Semibold - For headlines
    static let videoHeadline = Font.system(size: 18, weight: .semibold, design: .default)
    
    /// 16pt, System, Medium - For subheadlines
    static let videoSubheadline = Font.system(size: 16, weight: .medium, design: .default)
    
    /// 15pt, System, Regular - For body text
    static let videoBody = Font.system(size: 15, weight: .regular, design: .default)
    
    /// 14pt, System, Regular - For secondary body
    static let videoBodySmall = Font.system(size: 14, weight: .regular, design: .default)
    
    // MARK: - Caption Fonts
    
    /// 12pt, System, Medium - For captions and labels
    static let videoCaption = Font.system(size: 12, weight: .medium, design: .default)
    
    /// 10pt, System, Medium - For small labels
    static let videoCaptionSmall = Font.system(size: 10, weight: .medium, design: .default)
    
    // MARK: - Button Font
    
    /// 16pt, System, Semibold - For button text
    static let videoButton = Font.system(size: 16, weight: .semibold, design: .default)
}

// MARK: - Text Styles for Dark Theme

extension View {
    /// Apply display large style (main titles)
    func videoDisplayLargeStyle() -> some View {
        self
            .font(.videoDisplayLarge)
            .foregroundColor(.videoTextPrimary)
    }
    
    /// Apply display medium style (section headers)
    func videoDisplayMediumStyle() -> some View {
        self
            .font(.videoDisplayMedium)
            .foregroundColor(.videoTextPrimary)
    }
    
    /// Apply headline style
    func videoHeadlineStyle() -> some View {
        self
            .font(.videoHeadline)
            .foregroundColor(.videoTextPrimary)
    }
    
    /// Apply body style
    func videoBodyStyle() -> some View {
        self
            .font(.videoBody)
            .foregroundColor(.videoTextPrimary)
            .lineSpacing(4)
    }
    
    /// Apply secondary body style
    func videoSecondaryBodyStyle() -> some View {
        self
            .font(.videoBodySmall)
            .foregroundColor(.videoTextSecondary)
            .lineSpacing(3)
    }
    
    /// Apply caption style with editorial tracking
    func videoCaptionStyle() -> some View {
        self
            .font(.videoCaption)
            .foregroundColor(.videoTextTertiary)
            .tracking(0.3)
    }
    
    /// Apply button text style
    func videoButtonTextStyle() -> some View {
        self
            .font(.videoButton)
            .fontWeight(.semibold)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.videoBackground.ignoresSafeArea()
        
        VStack(alignment: .leading, spacing: 24) {
            Text("Display Large")
                .videoDisplayLargeStyle()
            
            Text("Display Medium")
                .videoDisplayMediumStyle()
            
            Text("Headline Text")
                .videoHeadlineStyle()
            
            Text("Body text for longer content that provides detailed information.")
                .videoBodyStyle()
            
            Text("Secondary body text for supplementary information")
                .videoSecondaryBodyStyle()
            
            Text("Caption text")
                .videoCaptionStyle()
            
            Text("Button Text")
                .videoButtonTextStyle()
                .foregroundColor(.videoAccent)
        }
        .padding()
    }
}
