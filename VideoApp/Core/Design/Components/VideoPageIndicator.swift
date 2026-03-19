//
//  VideoPageIndicator.swift
//  AIVideo
//
//  Custom page indicator for onboarding and carousels
//

import SwiftUI

struct VideoPageIndicator: View {
    let totalPages: Int
    @Binding var currentPage: Int
    var activeColor: Color = .white
    var inactiveColor: Color = .white.opacity(0.3)
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? activeColor : inactiveColor)
                    .frame(
                        width: index == currentPage ? 20 : 6,
                        height: 6
                    )
                    .animation(.easeInOut(duration: 0.3), value: currentPage)
            }
        }
    }
}

// MARK: - Alternative Dot Style

struct VideoDotIndicator: View {
    let totalPages: Int
    @Binding var currentPage: Int
    var activeColor: Color = .white
    var inactiveColor: Color = .white.opacity(0.3)
    
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? activeColor : inactiveColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == currentPage ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: currentPage)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.videoBackground.ignoresSafeArea()
        
        VStack(spacing: 40) {
            VStack(spacing: 16) {
                Text("Page Indicator")
                    .font(.videoCaption)
                    .foregroundColor(.videoTextSecondary)
                
                VideoPageIndicator(totalPages: 4, currentPage: .constant(1))
            }
            
            VStack(spacing: 16) {
                Text("Dot Indicator")
                    .font(.videoCaption)
                    .foregroundColor(.videoTextSecondary)
                
                VideoDotIndicator(totalPages: 4, currentPage: .constant(2))
            }
        }
    }
}
