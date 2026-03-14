//
//  PhotoUploadView.swift
//  AIVideo
//
//  View for uploading full-body photo for generation
//

import SwiftUI
import PhotosUI

struct PhotoUploadView: View {
    let template: VideoTemplate
    
    @StateObject private var viewModel = GenerationViewModel()
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var navigateToConfirmation = false
    
    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()
            
            VStack(spacing: VideoSpacing.lg) {
                // Instructions
                instructionHeader
                    .padding(.top, VideoSpacing.md)
                
                // Photo preview / placeholder
                photoPreviewSection
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                
                Spacer()
                
                // Action buttons
                actionButtons
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                    .padding(.bottom, VideoSpacing.xxl)
            }
        }
        .navigationTitle("Your Photo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showImagePicker) {
            PHPickerViewController.View(
                selection: $viewModel.selectedPhoto,
                filter: .images
            )
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker(image: $viewModel.selectedPhoto)
        }
        .navigationDestination(isPresented: $navigateToConfirmation) {
            if let photo = viewModel.selectedPhoto {
                GenerationConfirmationView(
                    template: template,
                    photo: photo
                )
            }
        }
        .onChange(of: viewModel.selectedPhoto) { newValue in
            if newValue != nil {
                Analytics.track(.photoSelected(source: showCamera ? .camera : .gallery))
            }
        }
    }
    
    // MARK: - Instruction Header
    
    private var instructionHeader: some View {
        VStack(spacing: VideoSpacing.sm) {
            Text("Add Your Photo")
                .font(.videoDisplayMedium)
                .foregroundColor(.videoTextPrimary)
            
            Text("For best results, use a full-body photo where you're facing the camera")
                .font(.videoBody)
                .foregroundColor(.videoTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, VideoSpacing.xl)
        }
    }
    
    // MARK: - Photo Preview
    
    private var photoPreviewSection: some View {
        ZStack {
            if let photo = viewModel.selectedPhoto {
                // Selected photo
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxHeight: 400)
                    .clipped()
                    .cornerRadius(VideoSpacing.radiusLarge)
                    .overlay(
                        // Change button overlay
                        VStack {
                            HStack {
                                Spacer()
                                Button {
                                    viewModel.selectedPhoto = nil
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Circle())
                                }
                                .padding(VideoSpacing.sm)
                            }
                            Spacer()
                        }
                    )
            } else {
                // Placeholder with guidelines
                photoPlaceholder
            }
        }
    }
    
    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: VideoSpacing.radiusLarge)
            .fill(Color.videoSurface)
            .frame(maxHeight: 400)
            .aspectRatio(3/4, contentMode: .fit)
            .overlay(
                VStack(spacing: VideoSpacing.lg) {
                    // Person icon
                    Image(systemName: "person.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.videoTextTertiary)
                    
                    // Guidelines
                    VStack(spacing: VideoSpacing.sm) {
                        guidelineRow(icon: "checkmark.circle.fill", text: "Full body visible", isActive: true)
                        guidelineRow(icon: "checkmark.circle.fill", text: "Facing the camera", isActive: true)
                        guidelineRow(icon: "checkmark.circle.fill", text: "Good lighting", isActive: true)
                        guidelineRow(icon: "xmark.circle.fill", text: "Avoid dark or blurry photos", isActive: false)
                    }
                }
                .padding(VideoSpacing.xl)
            )
    }
    
    private func guidelineRow(icon: String, text: String, isActive: Bool) -> some View {
        HStack(spacing: VideoSpacing.sm) {
            Image(systemName: icon)
                .foregroundColor(isActive ? .videoAccent : .videoError)
                .font(.system(size: 16))
            
            Text(text)
                .font(.videoCaption)
                .foregroundColor(.videoTextSecondary)
            
            Spacer()
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: VideoSpacing.md) {
            if viewModel.selectedPhoto == nil {
                // Photo selection options
                HStack(spacing: VideoSpacing.md) {
                    VideoButton(title: "Gallery", icon: "photo", action: {
                        showImagePicker = true
                    }, style: .secondary)
                    
                    if ImagePickerHelper.isCameraAvailable {
                        VideoButton(title: "Camera", icon: "camera", action: {
                            Task {
                                let hasPermission = await ImagePickerHelper.requestCameraPermission()
                                if hasPermission {
                                    showCamera = true
                                }
                            }
                        }, style: .secondary)
                    }
                }
            } else {
                // Continue button
                VideoButton(title: "Continue") {
                    navigateToConfirmation = true
                }
                
                VideoButton(title: "Choose Different Photo", action: {
                    viewModel.selectedPhoto = nil
                }, style: .ghost)
            }
        }
    }
}

// MARK: - PHPicker SwiftUI Wrapper

extension PHPickerViewController {
    struct View: UIViewControllerRepresentable {
        @Binding var selection: UIImage?
        var filter: PHPickerFilter
        
        func makeUIViewController(context: Context) -> PHPickerViewController {
            var config = PHPickerConfiguration()
            config.selectionLimit = 1
            config.filter = filter
            
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            return picker
        }
        
        func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
        
        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }
        
        class Coordinator: NSObject, PHPickerViewControllerDelegate {
            let parent: View
            
            init(_ parent: View) {
                self.parent = parent
            }
            
            func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
                picker.dismiss(animated: true)
                
                guard let provider = results.first?.itemProvider,
                      provider.canLoadObject(ofClass: UIImage.self) else {
                    return
                }
                
                provider.loadObject(ofClass: UIImage.self) { image, error in
                    DispatchQueue.main.async {
                        if let uiImage = image as? UIImage {
                            self.parent.selection = uiImage.fixedOrientation()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PhotoUploadView(template: .sample)
    }
}
