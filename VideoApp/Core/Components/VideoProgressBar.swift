//
//  VideoProgressBar.swift
//  AIVideo
//
//  Thin / expanded progress bar for immersive video detail.
//  Compact mode: always-visible 3pt bar.
//  Expanded mode: scrubbable bar with thumb and time labels.
//

import SwiftUI

struct VideoProgressBar: View {
    let progress: Double
    let elapsedSeconds: Double
    let totalSeconds: Double
    var isExpanded: Bool = false
    var accentColor: Color = .videoAccent
    var onScrub: ((Double) -> Void)?
    var onScrubStarted: (() -> Void)?
    var onScrubEnded: (() -> Void)?
    
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    
    private var displayProgress: Double {
        isDragging ? dragProgress : progress
    }
    
    var body: some View {
        if isExpanded {
            expandedBar
        } else {
            compactBar
        }
    }
    
    // MARK: - Compact (thin, passive)
    
    private var compactBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.15))
                
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accentColor.opacity(0.8))
                    .frame(width: geo.size.width * clampedProgress(progress))
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
        .frame(height: 3)
    }
    
    // MARK: - Expanded (interactive, scrubable)
    
    private var expandedBar: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                    
                    Capsule()
                        .fill(accentColor)
                        .frame(width: geo.size.width * clampedProgress(displayProgress))
                        .animation(isDragging ? nil : .linear(duration: 0.1), value: displayProgress)
                    
                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: isDragging ? 16 : 10, height: isDragging ? 16 : 10)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .offset(x: thumbOffset(in: geo.size.width))
                        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isDragging)
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle().inset(by: -12))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                onScrubStarted?()
                                HapticManager.shared.selection()
                            }
                            let fraction = min(max(value.location.x / geo.size.width, 0), 1)
                            dragProgress = fraction
                            onScrub?(fraction)
                        }
                        .onEnded { _ in
                            isDragging = false
                            onScrubEnded?()
                        }
                )
            }
            .frame(height: 24)
            
            HStack {
                Text(formatTime(isDragging ? dragProgress * totalSeconds : elapsedSeconds))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text(formatTime(totalSeconds))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
    
    // MARK: - Helpers
    
    private func clampedProgress(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
    
    private func thumbOffset(in width: CGFloat) -> CGFloat {
        let thumbRadius: CGFloat = isDragging ? 8 : 5
        let filled = width * clampedProgress(displayProgress)
        return min(max(filled - thumbRadius, 0), width - thumbRadius * 2)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 40) {
            VideoProgressBar(
                progress: 0.4,
                elapsedSeconds: 3.2,
                totalSeconds: 8.0,
                isExpanded: false
            )
            .padding(.horizontal, 20)
            
            VideoProgressBar(
                progress: 0.4,
                elapsedSeconds: 3.2,
                totalSeconds: 8.0,
                isExpanded: true
            )
            .padding(.horizontal, 20)
        }
    }
}
