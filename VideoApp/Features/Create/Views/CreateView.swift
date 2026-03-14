//
//  CreateView.swift
//  AIVideo
//
//  Main creation screen with effect categories and effect catalog
//

import SwiftUI
import PhotosUI
import AVFoundation

struct CreateView: View {
    @StateObject private var viewModel = CreateViewModel()
    @EnvironmentObject var appState: AppState

    @State private var showPaywall = false
    @State private var selectedEffect: Effect?
    @State private var showEffectGenerationView = false
    @State private var centeredEffectID: UUID?

    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()

            if viewModel.allEffects.isEmpty && !viewModel.isLoadingEffects {
                emptyState
            } else {
                showcaseCarousel
            }

            if viewModel.isLoadingEffects && viewModel.allEffects.isEmpty {
                loadingOverlay
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Create")
                    .font(.videoHeadline)
                    .foregroundColor(.videoTextPrimary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !appState.isPremiumUser {
                    goProButton
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await viewModel.loadAll()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(source: .profile) {
                showPaywall = false
            }
        }
        .navigationDestination(isPresented: $showEffectGenerationView) {
            if let effect = selectedEffect {
                EffectGenerationView(effect: effect)
            }
        }
        .onChange(of: viewModel.allEffects) { _, newEffects in
            if centeredEffectID == nil, let first = newEffects.first {
                centeredEffectID = first.id
            }
        }
    }

    // MARK: - Showcase Carousel

    private var showcaseCarousel: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width * 0.82
            let cardHeight = geo.size.height * 0.78
            let sidePadding = (geo.size.width - cardWidth) / 2

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: VideoSpacing.sm) {
                    ForEach(viewModel.allEffects) { effect in
                        EffectShowcaseCard(
                            effect: effect,
                            cardWidth: cardWidth,
                            cardHeight: cardHeight,
                            isCentered: centeredEffectID == effect.id,
                            onSelect: {
                                selectedEffect = effect
                                showEffectGenerationView = true
                            }
                        )
                        .id(effect.id)
                        .scrollTransition(.animated(.spring())) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.6)
                                .scaleEffect(phase.isIdentity ? 1 : 0.92)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, sidePadding)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centeredEffectID)
            .frame(maxHeight: .infinity)
            .onAppear {
                if centeredEffectID == nil {
                    centeredEffectID = viewModel.allEffects.first?.id
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: VideoSpacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundColor(.videoTextTertiary)

            Text("No Effects Available")
                .font(.videoHeadline)
                .foregroundColor(.videoTextPrimary)

            Text("Check back soon for new effects")
                .font(.videoBody)
                .foregroundColor(.videoTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Go Pro Button
    
    private var goProButton: some View {
        Button {
            HapticManager.shared.selection()
            showPaywall = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10))
                Text("PRO")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(.videoBackground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.videoAccent)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Loading Overlay
    
    private var loadingOverlay: some View {
        VStack(spacing: VideoSpacing.md) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .videoAccent))
                .scaleEffect(1.2)
            
            Text("Loading...")
                .font(.videoCaption)
                .foregroundColor(.videoTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.videoBackground.opacity(0.8))
    }
}

// MARK: - Video Picker

struct VideoPickerView: UIViewControllerRepresentable {
    let onSelect: (URL) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .videos
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPickerView
        
        init(_ parent: VideoPickerView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                return
            }
            
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                guard let url = url else { return }
                
                // Copy to temp location (provider URL is temporary)
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: tempURL)
                try? FileManager.default.copyItem(at: url, to: tempURL)
                
                DispatchQueue.main.async {
                    self.parent.onSelect(tempURL)
                }
            }
        }
    }
}

import UniformTypeIdentifiers

// MARK: - User Videos Grid Screen

struct UserVideosGridScreen: View {
    let userVideos: [LocalUserVideo]
    let onSelect: (LocalUserVideo) -> Void
    let onDelete: (LocalUserVideo) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    private let columns = [
        GridItem(.flexible(), spacing: VideoSpacing.sm),
        GridItem(.flexible(), spacing: VideoSpacing.sm)
    ]
    
    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()
            
            if userVideos.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: VideoSpacing.sm) {
                        ForEach(userVideos) { video in
                            videoCard(for: video)
                        }
                    }
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                    .padding(.top, VideoSpacing.md)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationTitle("Your Videos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
    
    private var emptyState: some View {
        VStack(spacing: VideoSpacing.md) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 50))
                .foregroundColor(.videoTextTertiary)
            
            Text("No Videos Yet")
                .font(.videoHeadline)
                .foregroundColor(.videoTextPrimary)
            
            Text("Upload your own videos\nto use as templates")
                .font(.videoBody)
                .foregroundColor(.videoTextSecondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private func videoCard(for video: LocalUserVideo) -> some View {
        Button {
            HapticManager.shared.selection()
            onSelect(video)
            dismiss()
        } label: {
            ZStack {
                if let url = video.effectiveVideoUrl {
                    LoopingRemoteVideoPlayer(url: url)
                        .id(video.id) // CRITICAL: Force unique view per video
                        .aspectRatio(9/16, contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.videoSurface)
                }
                
                VStack {
                    Spacer()
                    HStack {
                        Text(video.name)
                            .font(.videoCaption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(VideoSpacing.sm)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .aspectRatio(9/16, contentMode: .fit)
            .cornerRadius(VideoSpacing.radiusMedium)
        }
        .buttonStyle(ScaleButtonStyle())
        .contextMenu {
            Button(role: .destructive) {
                onDelete(video)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CreateView()
            .environmentObject(AppState.shared)
    }
}
