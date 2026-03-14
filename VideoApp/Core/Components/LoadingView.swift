//
//  LoadingView.swift
//  AIVideo
//
//  Reusable loading component
//

import SwiftUI

struct LoadingView: View {
    var message: String? = nil
    
    var body: some View {
        VStack(spacing: VideoSpacing.md) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .videoAccent))
                .scaleEffect(1.5)
            
            if let message = message {
                Text(message)
                    .font(.videoBody)
                    .foregroundColor(.videoTextSecondary)
            }
        }
    }
}

// MARK: - Full Screen Loading

struct FullScreenLoadingView: View {
    var message: String? = nil
    
    var body: some View {
        ZStack {
            Color.videoBackground
                .ignoresSafeArea()
            
            LoadingView(message: message)
        }
    }
}

// MARK: - Preview

#Preview {
    FullScreenLoadingView(message: "Loading templates...")
}
