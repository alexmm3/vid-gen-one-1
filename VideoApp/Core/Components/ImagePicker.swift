//
//  ImagePicker.swift
//  AIVideo
//
//  Image picker components for camera and photo library access
//  Adapted from GLAM reference
//

import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

// MARK: - Camera Image Picker (UIKit Bridge)

struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    var sourceType: UIImagePickerController.SourceType = .camera
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraImagePicker
        
        init(_ parent: CameraImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                let fixedImage = image.fixedOrientation()
                parent.image = fixedImage
                
                if parent.sourceType == .camera {
                    UIImageWriteToSavedPhotosAlbum(fixedImage, nil, nil, nil)
                }
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Photos Picker (SwiftUI Native)

struct VideoPhotosPicker: View {
    @Binding var selectedImage: UIImage?
    var selectionLimit: Int = 1
    var title: String = "Select Photo"
    var icon: String = "photo.on.rectangle"
    
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoading = false
    
    var body: some View {
        PhotosPicker(
            selection: $selectedItems,
            maxSelectionCount: selectionLimit,
            matching: .images,
            photoLibrary: .shared()
        ) {
            HStack(spacing: VideoSpacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .videoTextPrimary))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                }
                
                Text(title)
                    .font(.videoSubheadline)
            }
            .foregroundColor(.videoTextPrimary)
            .padding(.horizontal, VideoSpacing.lg)
            .padding(.vertical, VideoSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium)
                    .fill(Color.videoSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium)
                    .stroke(Color.videoTextTertiary, lineWidth: 1)
            )
        }
        .onChange(of: selectedItems) { newItems in
            guard let item = newItems.first else { return }
            loadImage(from: item)
        }
    }
    
    private func loadImage(from item: PhotosPickerItem) {
        isLoading = true
        
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                await MainActor.run {
                    selectedImage = uiImage.fixedOrientation()
                    isLoading = false
                    selectedItems.removeAll()
                }
            } else {
                await MainActor.run {
                    isLoading = false
                    selectedItems.removeAll()
                }
            }
        }
    }
}

// MARK: - Camera Availability Check

enum ImagePickerHelper {
    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }
    
    static var isPhotoLibraryAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.photoLibrary)
    }
    
    @MainActor
    static func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

// MARK: - Aspect Ratio Classification

/// Maps an image's natural aspect ratio to the nearest standard ratio supported
/// by both Gemini image editing and Grok video generation APIs.
enum AspectRatioCategory: String, CaseIterable {
    case portrait = "9:16"
    case mildPortrait = "3:4"
    case square = "1:1"
    case mildLandscape = "4:3"
    case landscape = "16:9"
    
    var widthOverHeight: CGFloat {
        switch self {
        case .portrait:       return 9.0 / 16.0   // 0.5625
        case .mildPortrait:   return 3.0 / 4.0    // 0.75
        case .square:         return 1.0
        case .mildLandscape:  return 4.0 / 3.0    // 1.333
        case .landscape:      return 16.0 / 9.0   // 1.778
        }
    }

    /// API-compatible string value (e.g. "9:16", "16:9")
    var apiValue: String { rawValue }

    /// Classify a width/height ratio to the nearest supported category.
    /// Boundaries are geometric midpoints between adjacent standard ratios.
    static func classify(_ widthOverHeight: CGFloat) -> AspectRatioCategory {
        switch widthOverHeight {
        case ..<0.66:          return .portrait       // < midpoint(9:16, 3:4)
        case 0.66..<0.87:     return .mildPortrait   // < midpoint(3:4, 1:1)
        case 0.87..<1.15:     return .square         // < midpoint(1:1, 4:3)
        case 1.15..<1.55:     return .mildLandscape  // < midpoint(4:3, 16:9)
        default:               return .landscape
        }
    }
}

// MARK: - UIImage Extensions

extension UIImage {
    /// Fix image orientation
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return normalizedImage ?? self
    }
    
    /// Crop image to 9:16 aspect ratio (portrait) by center-cropping.
    /// Used by the motion-video (Kling) flow which always requires portrait input.
    func croppedTo9by16() -> UIImage {
        return croppedToRatio(9.0 / 16.0)
    }

    /// Crop to the nearest standard aspect ratio, preserving as much content as possible.
    /// Returns both the cropped image and the detected category for API metadata.
    func croppedToStandardRatio() -> (image: UIImage, category: AspectRatioCategory) {
        let currentRatio = size.width / size.height
        let category = AspectRatioCategory.classify(currentRatio)

        if abs(currentRatio - category.widthOverHeight) < 0.01 {
            return (self, category)
        }

        return (croppedToRatio(category.widthOverHeight), category)
    }

    /// Center-crop to an exact width/height ratio
    private func croppedToRatio(_ targetRatio: CGFloat) -> UIImage {
        let currentRatio = size.width / size.height

        if abs(currentRatio - targetRatio) < 0.01 {
            return self
        }

        let cropRect: CGRect

        if currentRatio > targetRatio {
            let newWidth = size.height * targetRatio
            let xOffset = (size.width - newWidth) / 2.0
            cropRect = CGRect(x: xOffset, y: 0, width: newWidth, height: size.height)
        } else {
            let newHeight = size.width / targetRatio
            let yOffset = (size.height - newHeight) / 2.0
            cropRect = CGRect(x: 0, y: yOffset, width: size.width, height: newHeight)
        }

        let scaledRect = CGRect(
            x: cropRect.origin.x * scale,
            y: cropRect.origin.y * scale,
            width: cropRect.width * scale,
            height: cropRect.height * scale
        )

        guard let cgImage = cgImage?.cropping(to: scaledRect) else { return self }
        return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
    }
    
    /// Resize image maintaining aspect ratio
    func resizedToMax(dimension: CGFloat) -> UIImage {
        let currentMax = max(size.width, size.height)
        
        guard currentMax > dimension else { return self }
        
        let scale = dimension / currentMax
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage ?? self
    }
    
    /// Compress to JPEG data with quality
    func compressedJPEGData(quality: CGFloat = 0.8) -> Data? {
        return jpegData(compressionQuality: quality)
    }
}
