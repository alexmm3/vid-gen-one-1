//
//  VideoTabBar.swift
//  AIVideo
//
//  Custom tab bar with dark theme styling
//

import SwiftUI

struct VideoTabBar: View {
    @Binding var selectedTab: VideoTab
    
    var body: some View {
        HStack {
            ForEach(VideoTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, VideoSpacing.md)
        .padding(.vertical, VideoSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: VideoSpacing.radiusLarge)
                .fill(Color.videoSurface)
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: -5)
        )
        .padding(.horizontal, VideoSpacing.screenHorizontal)
        .padding(.bottom, VideoSpacing.xs)
    }
    
    private func tabButton(for tab: VideoTab) -> some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: selectedTab == tab ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(selectedTab == tab ? .videoAccent : .videoTextTertiary)
                
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(selectedTab == tab ? .videoAccent : .videoTextTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, VideoSpacing.xs)
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.95))
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.videoBackground.ignoresSafeArea()
        
        VStack {
            Spacer()
            VideoTabBar(selectedTab: .constant(.create))
        }
    }
}
