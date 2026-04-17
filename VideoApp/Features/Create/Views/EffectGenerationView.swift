//
//  EffectGenerationView.swift
//  AIVideo
//
//  Effect-based generation: effect name, photo(s), optional prompt, generate.
//  No effect preview on this screen.
//

import SwiftUI
import PhotosUI

struct EffectGenerationView: View {
    let effect: Effect

    @StateObject private var generationViewModel = GenerationViewModel()
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var primaryPhoto: UIImage?
    @State private var secondaryPhoto: UIImage?
    @State private var promptText: String = ""

    @State private var showPhotoSourceSheet = false
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var selectingSecondary = false

    @State private var showPaywall = false
    @State private var showPhotoTips = false
    @State private var showGenerationInProgressAlert = false
    @State private var showAIDataConsent = false

    private var canGenerate: Bool {
        guard primaryPhoto != nil else { return false }
        if effect.requiresSecondaryPhoto { return secondaryPhoto != nil }
        return true
    }

    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: VideoSpacing.xl) {
                    // Effect name only (no preview)
                    Text(effect.name)
                        .font(.videoDisplayMedium)
                        .foregroundColor(.videoTextPrimary)
                        .padding(.horizontal, VideoSpacing.screenHorizontal)
                        .padding(.top, VideoSpacing.sm)

                    // Photos Section
                    VStack(spacing: VideoSpacing.lg) {
                        if effect.requiresSecondaryPhoto {
                            splitPhotoSection()
                        } else {
                            photoSection(title: "Your Photo", photo: $primaryPhoto) {
                                selectingSecondary = false
                                showPhotoSourceSheet = true
                            }
                        }
                    }

                    // Prompt field
                    VStack(alignment: .leading, spacing: VideoSpacing.xs) {
                        Text("Additional prompt (optional)")
                            .font(.videoSubheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.videoTextPrimary)
                        TextField("Describe any extra details…", text: $promptText, axis: .vertical)
                            .font(.videoBody)
                            .foregroundColor(.videoTextPrimary)
                            .padding(VideoSpacing.sm)
                            .background(Color.videoSurface)
                            .cornerRadius(VideoSpacing.radiusMedium)
                            .lineLimit(3...6)
                    }
                    .padding(.horizontal, VideoSpacing.screenHorizontal)

                    Spacer(minLength: 120)
                }
            }

            VStack {
                Spacer()
                bottomBar
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Create Video")
                    .font(.videoHeadline)
                    .foregroundColor(.videoTextPrimary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    HapticManager.shared.selection()
                    showPhotoTips = true
                    Analytics.track(.photoTipsShown(effectName: effect.name))
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.videoTextSecondary)
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showPhotoTips) {
            PhotoTipsSheet(effectDescription: effect.description)
                .presentationDetents([.height(680)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPhotoSourceSheet) {
            PhotoSourceSheet(
                onCamera: {
                    Task {
                        let hasPermission = await ImagePickerHelper.requestCameraPermission()
                        if hasPermission { showCamera = true }
                    }
                },
                onGallery: { showImagePicker = true }
            )
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showImagePicker) {
            PHPickerViewController.View(
                selection: Binding(
                    get: { selectingSecondary ? secondaryPhoto : primaryPhoto },
                    set: { newImage in
                        if selectingSecondary { secondaryPhoto = newImage }
                        else { primaryPhoto = newImage }
                    }
                ),
                filter: .images
            )
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker(image: Binding(
                get: { selectingSecondary ? secondaryPhoto : primaryPhoto },
                set: { newImage in
                    if selectingSecondary { secondaryPhoto = newImage }
                    else { primaryPhoto = newImage }
                }
            ))
        }
        .fullScreenCover(isPresented: $generationViewModel.isGenerating) {
            GeneratingView(
                progress: generationViewModel.progress,
                canDismiss: generationViewModel.generationSubmitted,
                inputImage: primaryPhoto,
                onDismiss: {
                    generationViewModel.dismissGeneratingView()
                    appState.navigateToTab(.myVideos)
                    dismiss()
                }
            )
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(source: .generateBlocked) {
                showPaywall = false
                appState.setPremiumStatus(true)
                startGeneration()
            }
        }
        .navigationDestination(isPresented: $generationViewModel.showResult) {
            if let outputUrl = generationViewModel.outputVideoUrl {
                ResultView(
                    videoUrl: outputUrl,
                    templateName: effect.name
                )
            }
        }
        .alert("Error", isPresented: .init(
            get: { generationViewModel.error != nil && !(generationViewModel.error?.isSubscriptionError ?? false) },
            set: { if !$0 { generationViewModel.error = nil } }
        )) {
            Button("OK") { generationViewModel.error = nil }
            Button("Retry") { startGeneration() }
        } message: {
            Text(generationViewModel.error?.localizedDescription ?? "Unknown error")
        }
        .alert("Hold On!", isPresented: $showGenerationInProgressAlert) {
            Button("Got It") { }
        } message: {
            Text("A video is already being created for you. Check My Videos to see its progress — it should be ready soon!")
        }
        .sheet(isPresented: $showAIDataConsent) {
            AIDataConsentView {
                appState.hasAcceptedAIDataConsent = true
                startGeneration()
            }
            .interactiveDismissDisabled()
        }
        .onReceive(generationViewModel.$error) { error in
            if error?.isSubscriptionError == true {
                showPaywall = true
                generationViewModel.error = nil
            }
        }
    }

    // MARK: - Photo Section

    private func splitPhotoSection() -> some View {
        VStack(alignment: .leading, spacing: VideoSpacing.sm) {
            HStack {
                Text("Your Photos")
                    .font(.videoSubheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.videoTextPrimary)
                Spacer()
            }
            .padding(.horizontal, VideoSpacing.screenHorizontal)

            HStack(spacing: VideoSpacing.sm) {
                // Left Half: Primary Photo
                photoBox(
                    photo: $primaryPhoto,
                    placeholderIcon: "photo.badge.plus",
                    placeholderText: "Photo 1",
                    onTap: {
                        selectingSecondary = false
                        showPhotoSourceSheet = true
                    }
                )
                
                // Right Half: Secondary Photo
                photoBox(
                    photo: $secondaryPhoto,
                    placeholderIcon: "photo.badge.plus",
                    placeholderText: "Photo 2",
                    onTap: {
                        selectingSecondary = true
                        showPhotoSourceSheet = true
                    }
                )
            }
            .padding(.horizontal, VideoSpacing.screenHorizontal)
        }
    }

    private func photoBox(photo: Binding<UIImage?>, placeholderIcon: String, placeholderText: String, onTap: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.mediumImpact()
            onTap()
        } label: {
            ZStack {
                if let image = photo.wrappedValue {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium))
                    
                    // Change badge
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("Change")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule())
                                .padding(8)
                        }
                    }
                } else {
                    ZStack {
                        Color.videoSurface
                        
                        VStack(spacing: VideoSpacing.sm) {
                            ZStack {
                                Circle()
                                    .fill(Color.videoAccent.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Image(systemName: placeholderIcon)
                                    .font(.system(size: 20))
                                    .foregroundColor(.videoAccent)
                            }
                            VStack(spacing: 4) {
                                Text("Add")
                                    .font(.videoSubheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.videoTextPrimary)
                                Text(placeholderText)
                                    .font(.videoCaption)
                                    .foregroundColor(.videoTextSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .cornerRadius(VideoSpacing.radiusMedium)
                    .overlay(
                        RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium)
                            .stroke(Color.videoAccent.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                    )
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func photoSection(title: String, photo: Binding<UIImage?>, onTap: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: VideoSpacing.sm) {
            HStack {
                Text(title)
                    .font(.videoSubheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.videoTextPrimary)
                Spacer()
                if photo.wrappedValue != nil {
                    Button {
                        HapticManager.shared.selection()
                        onTap()
                    } label: {
                        Text("Change")
                            .font(.videoBody)
                            .fontWeight(.medium)
                            .foregroundColor(.videoAccent)
                    }
                }
            }
            .padding(.horizontal, VideoSpacing.screenHorizontal)

            Button {
                HapticManager.shared.mediumImpact()
                onTap()
            } label: {
                if let image = photo.wrappedValue {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: VideoSpacing.radiusLarge))
                } else {
                    ZStack {
                        Color.videoSurface
                        
                        VStack(spacing: VideoSpacing.sm) {
                            ZStack {
                                Circle()
                                    .fill(Color.videoAccent.opacity(0.15))
                                    .frame(width: 64, height: 64)
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 28))
                                    .foregroundColor(.videoAccent)
                            }
                            VStack(spacing: 4) {
                                Text("Add Photo")
                                    .font(.videoSubheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.videoTextPrimary)
                                Text("Tap to select from gallery or take a photo")
                                    .font(.videoBodySmall)
                                    .foregroundColor(.videoTextSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .cornerRadius(VideoSpacing.radiusLarge)
                    .overlay(
                        RoundedRectangle(cornerRadius: VideoSpacing.radiusLarge)
                            .stroke(Color.videoAccent.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                    )
                }
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, VideoSpacing.screenHorizontal)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.videoTextTertiary.opacity(0.2))
            VideoButton(
                title: "Generate Video",
                icon: "sparkles",
                action: { startGeneration() },
                isEnabled: canGenerate && !generationViewModel.isGenerating
            )
            .padding(.horizontal, VideoSpacing.screenHorizontal)
            .padding(.top, VideoSpacing.md)
            .padding(.bottom, VideoSpacing.lg)
            .background(Color.videoBackground)
        }
    }

    // MARK: - Actions

    private func startGeneration() {
        if !appState.hasAcceptedAIDataConsent {
            showAIDataConsent = true
            return
        }
        if !appState.isPremiumUser {
            showPaywall = true
            return
        }
        if !ActiveGenerationManager.shared.canStartNewGeneration() {
            showGenerationInProgressAlert = true
            Analytics.track(.generationBlockedByActiveJob)
            return
        }
        guard let primary = primaryPhoto else { return }

        Task {
            await generationViewModel.generateEffect(
                primaryPhoto: primary,
                secondaryPhoto: effect.requiresSecondaryPhoto ? secondaryPhoto : nil,
                userPrompt: promptText.isEmpty ? nil : promptText,
                effect: effect
            )
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        EffectGenerationView(effect: .sample)
            .environmentObject(AppState.shared)
    }
}
