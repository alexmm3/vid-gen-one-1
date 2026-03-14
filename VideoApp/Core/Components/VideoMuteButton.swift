//
//  VideoMuteButton.swift
//  AIVideo
//
//  Reusable mute/unmute button overlay for video players
//

import SwiftUI

struct VideoMuteButton: View {
    @Binding var isMuted: Bool
    var size: CGFloat = 36
    var iconSize: CGFloat = 16
    
    var body: some View {
        Button {
            HapticManager.shared.selection()
            isMuted.toggle()
        } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Play/Pause Button

struct VideoPlayPauseButton: View {
    @Binding var isPlaying: Bool
    var size: CGFloat = 36
    var iconSize: CGFloat = 16
    
    var body: some View {
        Button {
            HapticManager.shared.selection()
            isPlaying.toggle()
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Video Player with Mute Button Overlay

struct VideoWithMuteButton<Content: View>: View {
    @Binding var isMuted: Bool
    let content: Content
    var buttonPadding: CGFloat = 12
    
    init(isMuted: Binding<Bool>, buttonPadding: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self._isMuted = isMuted
        self.buttonPadding = buttonPadding
        self.content = content()
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            content
            
            VideoMuteButton(isMuted: $isMuted)
                .padding(buttonPadding)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.videoBackground.ignoresSafeArea()
        
        VStack(spacing: 20) {
            // Unmuted state
            VideoMuteButton(isMuted: .constant(false))
            
            // Muted state
            VideoMuteButton(isMuted: .constant(true))
        }
    }
}
