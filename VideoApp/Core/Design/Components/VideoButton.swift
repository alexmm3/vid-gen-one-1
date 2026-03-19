//
//  VideoButton.swift
//  AIVideo
//
//  Primary and secondary button components for dark theme
//  Adapted from GLAM's GlamButton
//

import SwiftUI

// MARK: - Primary Button

struct VideoButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void
    var isEnabled: Bool = true
    var isLoading: Bool = false
    var style: ButtonStyle = .primary
    
    enum ButtonStyle {
        case primary    // Accent background, black text
        case secondary  // Outlined, accent border
        case ghost      // No background, white text
        case inverted   // White background, black text
        case marketing  // Marketing gradient (lime), black text
    }
    
    var body: some View {
        Button(action: {
            HapticManager.shared.lightImpact()
            action()
        }) {
            ZStack {
                // Background
                backgroundView
                
                // Content
                HStack(spacing: VideoSpacing.xs) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: textColor))
                            .scaleEffect(0.8)
                    } else {
                        if let iconName = icon {
                            Image(systemName: iconName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(textColor)
                        }
                        Text(title)
                            .videoButtonTextStyle()
                            .foregroundColor(textColor)
                    }
                }
                .padding(.horizontal, VideoSpacing.lg)
            }
            .frame(height: VideoSpacing.buttonHeight)
            .frame(maxWidth: .infinity)
        }
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1.0 : 0.5)
        .buttonStyle(VideoButtonPressStyle())
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .primary:
            RoundedRectangle(cornerRadius: VideoSpacing.radiusSmall)
                .fill(Color.videoWhite)
        case .secondary:
            RoundedRectangle(cornerRadius: VideoSpacing.radiusSmall)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: VideoSpacing.radiusSmall)
                        .fill(Color.clear)
                )
        case .ghost:
            Color.clear
        case .inverted:
            RoundedRectangle(cornerRadius: VideoSpacing.radiusSmall)
                .fill(Color.videoBlack)
        case .marketing:
            RoundedRectangle(cornerRadius: VideoSpacing.radiusSmall)
                .fill(Color.videoWhite)
        }
    }
    
    private var textColor: Color {
        switch style {
        case .primary:
            return .videoBlack
        case .secondary:
            return .videoTextPrimary
        case .ghost:
            return .videoTextPrimary
        case .inverted:
            return .videoWhite
        case .marketing:
            return .videoBlack
        }
    }
}

// MARK: - Small Button Variant

struct VideoSmallButton: View {
    let title: String
    let action: () -> Void
    var icon: String? = nil
    var style: VideoButton.ButtonStyle = .secondary
    
    var body: some View {
        Button(action: {
            HapticManager.shared.lightImpact()
            action()
        }) {
            HStack(spacing: VideoSpacing.xs) {
                if let iconName = icon {
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(textColor)
                }
                
                Text(title)
                    .font(.videoCaption)
                    .fontWeight(.semibold)
                    .foregroundColor(textColor)
            }
            .padding(.horizontal, VideoSpacing.md)
            .padding(.vertical, VideoSpacing.sm)
            .background(backgroundView)
        }
        .buttonStyle(VideoButtonPressStyle())
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .primary:
            RoundedRectangle(cornerRadius: VideoSpacing.radiusSmall)
                .fill(Color.videoWhite)
        case .secondary:
            RoundedRectangle(cornerRadius: VideoSpacing.radiusSmall)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: VideoSpacing.radiusSmall)
                        .fill(Color.clear)
                )
        case .ghost:
            Color.clear
        case .inverted:
            RoundedRectangle(cornerRadius: VideoSpacing.radiusSmall)
                .fill(Color.videoBlack)
        case .marketing:
            RoundedRectangle(cornerRadius: VideoSpacing.radiusSmall)
                .fill(Color.videoWhite)
        }
    }
    
    private var textColor: Color {
        switch style {
        case .primary:
            return .videoBlack
        case .secondary:
            return .videoTextPrimary
        case .ghost:
            return .videoTextPrimary
        case .inverted:
            return .videoWhite
        case .marketing:
            return .videoBlack
        }
    }
}

// MARK: - Icon Button

struct VideoIconButton: View {
    let icon: String
    let action: () -> Void
    var size: CGFloat = VideoSpacing.minTouchTarget
    var style: IconStyle = .default
    
    enum IconStyle {
        case `default`   // White icon
        case filled      // Accent background, black icon
        case outlined    // Border
    }
    
    var body: some View {
        Button(action: {
            HapticManager.shared.lightImpact()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: size, height: size)
                .background(backgroundView)
        }
        .buttonStyle(VideoButtonPressStyle())
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .default:
            Color.clear
        case .filled:
            Circle()
                .fill(Color.videoWhite)
        case .outlined:
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                .background(Circle().fill(Color.videoSurface))
        }
    }
    
    private var iconColor: Color {
        switch style {
        case .default:
            return .videoTextPrimary
        case .filled:
            return .videoBlack
        case .outlined:
            return .videoTextPrimary
        }
    }
}

// MARK: - Button Press Animation Style

struct VideoButtonPressStyle: SwiftUI.ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: SwiftUI.ButtonStyle {
    var scale: CGFloat = 0.95
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.videoBackground.ignoresSafeArea()
        
        VStack(spacing: VideoSpacing.lg) {
            VideoButton(title: "Generate Video", action: {})
            
            VideoButton(title: "Choose Template", action: {}, style: .secondary)
            
            VideoButton(title: "Loading...", action: {}, isLoading: true)
            
            VideoButton(title: "Disabled", action: {}, isEnabled: false)
            
            HStack(spacing: VideoSpacing.md) {
                VideoSmallButton(title: "Change", action: {}, icon: "arrow.triangle.2.circlepath")
                VideoSmallButton(title: "Remove", action: {}, icon: "xmark", style: .ghost)
            }
            
            HStack(spacing: VideoSpacing.lg) {
                VideoIconButton(icon: "xmark", action: {})
                VideoIconButton(icon: "play.fill", action: {}, style: .filled)
                VideoIconButton(icon: "square.and.arrow.up", action: {}, style: .outlined)
            }
        }
        .padding()
    }
}
