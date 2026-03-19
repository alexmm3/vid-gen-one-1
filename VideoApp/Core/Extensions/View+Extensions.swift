//
//  View+Extensions.swift
//  AIVideo
//
//  SwiftUI View extensions for common patterns
//  Adapted from GLAM reference
//

import SwiftUI

// MARK: - Conditional Modifiers

extension View {
    /// Apply a modifier conditionally
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    /// Apply a modifier conditionally with else clause
    @ViewBuilder
    func `if`<TrueContent: View, FalseContent: View>(
        _ condition: Bool,
        if ifTransform: (Self) -> TrueContent,
        else elseTransform: (Self) -> FalseContent
    ) -> some View {
        if condition {
            ifTransform(self)
        } else {
            elseTransform(self)
        }
    }
    
    /// Apply modifier if value is not nil
    @ViewBuilder
    func ifLet<Value, Content: View>(_ value: Value?, transform: (Self, Value) -> Content) -> some View {
        if let value = value {
            transform(self, value)
        } else {
            self
        }
    }
}

// MARK: - Navigation Helpers

extension View {
    /// Hide navigation bar
    func hideNavigationBar() -> some View {
        self
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
    }
    
    /// Standard AI Video navigation bar styling (dark theme)
    func videoNavigationBar(title: String = "", showBack: Bool = false) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.videoBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - Frame Helpers

extension View {
    /// Expand to fill available space
    func fillMaxSize(alignment: Alignment = .center) -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
    
    /// Expand to fill available width
    func fillMaxWidth(alignment: Alignment = .center) -> some View {
        self.frame(maxWidth: .infinity, alignment: alignment)
    }
    
    /// Expand to fill available height
    func fillMaxHeight(alignment: Alignment = .center) -> some View {
        self.frame(maxHeight: .infinity, alignment: alignment)
    }
}

// MARK: - Keyboard Handling

extension View {
    /// Dismiss keyboard on tap
    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

// MARK: - Loading Overlay (Dark Theme)

extension View {
    /// Show loading overlay
    func loadingOverlay(isLoading: Bool, message: String? = nil) -> some View {
        self.overlay(
            Group {
                if isLoading {
                    ZStack {
                        Color.videoBlack.opacity(0.85)
                            .ignoresSafeArea()
                        
                        VStack(spacing: VideoSpacing.md) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            
                            if let message = message {
                                Text(message)
                                    .font(.videoBody)
                                    .foregroundColor(.videoTextPrimary)
                            }
                        }
                        .padding(VideoSpacing.xl)
                        .background(
                            RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium)
                                .fill(Color.videoSurface)
                        )
                    }
                }
            }
        )
    }
}

// MARK: - Card & Container Styles

extension View {
    /// Standard AI Video card styling
    func videoCardStyle(
        cornerRadius: CGFloat = VideoSpacing.radiusMedium,
        backgroundColor: Color = .videoSurface
    ) -> some View {
        self
            .padding(VideoSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backgroundColor)
            )
    }
    
    /// Bordered card style
    func videoBorderedCardStyle(
        cornerRadius: CGFloat = VideoSpacing.radiusMedium,
        borderColor: Color = .videoTextTertiary
    ) -> some View {
        self
            .videoCardStyle(cornerRadius: cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

// MARK: - Minimum Touch Target

extension View {
    /// Ensure minimum touch target size (44pt) for accessibility
    func videoMinTouchTarget(width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
        self.frame(
            minWidth: width ?? VideoSpacing.minTouchTarget,
            minHeight: height ?? VideoSpacing.minTouchTarget
        )
    }
}

// MARK: - Rounded Corners (Specific Corners)

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Snapshot for Sharing

extension View {
    @MainActor
    func snapshot() -> UIImage {
        let controller = UIHostingController(rootView: self)
        let view = controller.view
        
        let targetSize = controller.view.intrinsicContentSize
        view?.bounds = CGRect(origin: .zero, size: targetSize)
        view?.backgroundColor = .clear
        
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            view?.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}

// MARK: - Shimmer Effect

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.08),
                            Color.white.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * (geo.size.width * 1.6))
                    .clipped()
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

// MARK: - UIImage Dominant Color

extension UIImage {
    /// Extracts the dominant color by down-sampling to 1x1 pixel.
    var dominantColor: UIColor? {
        guard let cgImage = self.cgImage else { return nil }
        let size = CGSize(width: 4, height: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel = [UInt8](repeating: 0, count: 64)
        guard let context = CGContext(
            data: &pixel,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 16,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        for i in stride(from: 0, to: 64, by: 4) {
            r += CGFloat(pixel[i])
            g += CGFloat(pixel[i + 1])
            b += CGFloat(pixel[i + 2])
        }
        let count: CGFloat = 16
        return UIColor(red: r / count / 255, green: g / count / 255, blue: b / count / 255, alpha: 1)
    }
    
    /// Extracts 3 vertical colors (top, middle, bottom) by down-sampling to 1x3 pixels.
    var verticalColors: [UIColor]? {
        guard let cgImage = self.cgImage else { return nil }
        let size = CGSize(width: 1, height: 3)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel = [UInt8](repeating: 0, count: 12)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 3,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        
        var colors: [UIColor] = []
        for i in stride(from: 0, to: 12, by: 4) {
            let r = CGFloat(pixel[i]) / 255
            let g = CGFloat(pixel[i + 1]) / 255
            let b = CGFloat(pixel[i + 2]) / 255
            
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0
            
            let color = UIColor(red: r, green: g, blue: b, alpha: 1)
            if color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
                // Boost saturation and brightness slightly for a better ambient effect
                let finalSat = saturation > 0.05 ? min(saturation * 1.3, 1.0) : saturation
                let finalBri = min(brightness * 1.2 + 0.1, 1.0)
                let boostedColor = UIColor(
                    hue: hue,
                    saturation: finalSat,
                    brightness: finalBri,
                    alpha: 1.0
                )
                colors.append(boostedColor)
            } else {
                colors.append(color)
            }
        }
        return colors
    }
}

// MARK: - Collection Safe Subscript

extension Collection {
    /// Returns the element at the specified index if it exists, otherwise nil.
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
