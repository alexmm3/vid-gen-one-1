//
//  EmptyStateView.swift
//  AIVideo
//
//  Reusable empty state component
//

import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: VideoSpacing.md) {
            Spacer()
            
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.videoTextTertiary)
            
            Text(title)
                .font(.videoHeadline)
                .foregroundColor(.videoTextPrimary)
            
            Text(subtitle)
                .font(.videoBody)
                .foregroundColor(.videoTextSecondary)
                .multilineTextAlignment(.center)
            
            if let actionTitle = actionTitle, let action = action {
                VideoButton(title: actionTitle, action: action, style: .secondary)
                    .padding(.horizontal, VideoSpacing.xxl)
                    .padding(.top, VideoSpacing.md)
            }
            
            Spacer()
            Spacer()
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.videoBackground.ignoresSafeArea()
        
        EmptyStateView(
            icon: "film.stack",
            title: "No Videos Yet",
            subtitle: "Your generated videos will appear here",
            actionTitle: "Create Video",
            action: {}
        )
    }
}
