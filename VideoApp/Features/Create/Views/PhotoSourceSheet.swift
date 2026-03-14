//
//  PhotoSourceSheet.swift
//  AIVideo
//
//  Sheet for selecting photo source (camera or gallery)
//

import SwiftUI

struct PhotoSourceSheet: View {
    let onCamera: () -> Void
    let onGallery: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.videoTextTertiary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, VideoSpacing.md)
            
            // Header
            Text("Add Your Photo")
                .font(.videoHeadline)
                .foregroundColor(.videoTextPrimary)
                .padding(.top, VideoSpacing.lg)
                .padding(.bottom, VideoSpacing.md)
            
            // Options
            VStack(spacing: VideoSpacing.sm) {
                // Camera option
                if ImagePickerHelper.isCameraAvailable {
                    optionButton(
                        icon: "camera.fill",
                        title: "Take Photo",
                        subtitle: "Use your camera"
                    ) {
                        HapticManager.shared.selection()
                        dismiss()
                        onCamera()
                    }
                }
                
                // Gallery option
                optionButton(
                    icon: "photo.on.rectangle",
                    title: "Choose from Gallery",
                    subtitle: "Select from your photos"
                ) {
                    HapticManager.shared.selection()
                    dismiss()
                    onGallery()
                }
            }
            .padding(.horizontal, VideoSpacing.screenHorizontal)
            
            // Cancel button
            Button {
                HapticManager.shared.lightImpact()
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.videoBody)
                    .foregroundColor(.videoTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, VideoSpacing.md)
            }
            .padding(.top, VideoSpacing.lg)
            .padding(.bottom, VideoSpacing.xl)
        }
        .background(Color.videoSurface)
    }
    
    // MARK: - Option Button
    
    private func optionButton(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: VideoSpacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.videoAccent.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(.videoAccent)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.videoSubheadline)
                        .foregroundColor(.videoTextPrimary)
                    
                    Text(subtitle)
                        .font(.videoCaption)
                        .foregroundColor(.videoTextSecondary)
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.videoTextTertiary)
            }
            .padding(VideoSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium)
                    .fill(Color.videoBackground)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    PhotoSourceSheet(
        onCamera: {},
        onGallery: {}
    )
    .background(Color.videoBackground)
}
