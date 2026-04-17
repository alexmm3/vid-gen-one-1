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

    @State private var selectedEffect: Effect?
    @State private var showEffectGenerationView = false
    @State private var centeredEffectID: UUID?
    @State private var swipeDirection: SwipeDirection = .forward

    private enum SwipeDirection {
        case forward, backward
    }

    private var centeredEffect: Effect? {
        guard let id = centeredEffectID else { return nil }
        return viewModel.allEffects.first { $0.id == id }
    }

    private var warmedEffectIDs: Set<UUID> {
        let effects = viewModel.allEffects
        guard !effects.isEmpty else { return [] }

        guard let id = centeredEffectID,
              let idx = effects.firstIndex(where: { $0.id == id }) else {
            return Set(effects.prefix(1).map(\.id))
        }

        let range = max(0, idx - 1)...min(effects.count - 1, idx + 1)
        return Set(range.map { effects[$0].id })
    }

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
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await viewModel.loadAll()
        }
        .refreshable {
            await viewModel.refresh()
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
        .onChange(of: centeredEffectID) { oldValue, newValue in
            if let oldVal = oldValue, let newVal = newValue,
               let oldIdx = viewModel.allEffects.firstIndex(where: { $0.id == oldVal }),
               let newIdx = viewModel.allEffects.firstIndex(where: { $0.id == newVal }) {
                swipeDirection = newIdx > oldIdx ? .forward : .backward
            }
            HapticManager.shared.selection()
            prefetchNearbyAssets()
            // Track effect scroll
            if let id = centeredEffectID,
               let effect = viewModel.allEffects.first(where: { $0.id == id }),
               let position = viewModel.allEffects.firstIndex(where: { $0.id == id }) {
                Analytics.track(.effectScrolled(
                    effectId: effect.id.uuidString,
                    effectName: effect.name,
                    position: position
                ))
            }
        }
    }

    // MARK: - Showcase Carousel

    private var showcaseCarousel: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width * 0.82
            let cardHeight = geo.size.height * 0.72
            let sidePadding = (geo.size.width - cardWidth) / 2

            ZStack {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    effectTitleSection(maxWidth: cardWidth)

                    Spacer(minLength: 0)

                    ZStack {
                        // Ambient glow directly behind the active card
                        ambientGlow(cardWidth: cardWidth, cardHeight: cardHeight)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: VideoSpacing.sm) {
                                ForEach(viewModel.allEffects) { effect in
                                    EffectShowcaseCard(
                                        effect: effect,
                                        cardWidth: cardWidth,
                                        cardHeight: cardHeight,
                                        isCentered: centeredEffectID == effect.id,
                                        shouldLoadVideo: warmedEffectIDs.contains(effect.id),
                                        shouldPlayVideo: centeredEffectID == effect.id,
                                        onSelect: {
                                            selectedEffect = effect
                                            showEffectGenerationView = true
                                            Analytics.track(.effectDetailOpened(
                                                effectId: effect.id.uuidString,
                                                effectName: effect.name
                                            ))
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
                        .frame(height: cardHeight)
                        .scrollTargetBehavior(.viewAligned)
                        .scrollPosition(id: $centeredEffectID)
                        .onAppear {
                            if centeredEffectID == nil {
                                centeredEffectID = viewModel.allEffects.first?.id
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Ambient Glow

    @ViewBuilder
    private func ambientGlow(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        if let effect = centeredEffect {
            let hex = effect.displayThemeColor
            RoundedRectangle(cornerRadius: VideoSpacing.radiusXLarge)
                .fill(Color(hex: hex))
                .frame(width: cardWidth, height: cardHeight)
                // Scale up so it bleeds outside the card
                .scaleEffect(x: 1.15, y: 1.1)
                // Massive blur to make it a soft aura
                .blur(radius: 80)
                // Subtle opacity
                .opacity(0.15)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.6), value: hex)
        } else {
            Color.clear
                .frame(width: cardWidth, height: cardHeight)
        }
    }

    private func prefetchNearbyAssets() {
        guard let id = centeredEffectID,
              let idx = viewModel.allEffects.firstIndex(where: { $0.id == id }) else { return }

        let effects = viewModel.allEffects
        let videoRange = max(0, idx - 1)...min(effects.count - 1, idx + 1)
        let videoUrls = videoRange.compactMap { effects[$0].fullPreviewUrl }
        VideoCacheManager.shared.prefetch(urls: videoUrls)
        VideoPosterFrameStore.shared.prefetch(urls: videoUrls)
    }

    // MARK: - Animated Effect Title

    private func effectTitleSection(maxWidth: CGFloat) -> some View {
        VStack(spacing: 5) {
            if let effect = centeredEffect {
                Text(effect.name)
                    .font(.videoDisplayMedium)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(width: maxWidth)
                    .id("name-\(effect.id)")
                    .transition(.asymmetric(
                        insertion: .move(edge: swipeDirection == .forward ? .trailing : .leading)
                            .combined(with: .opacity),
                        removal: .move(edge: swipeDirection == .forward ? .leading : .trailing)
                            .combined(with: .opacity)
                    ))

                if let description = effect.description, !description.isEmpty {
                    Text(description)
                        .font(.videoBodySmall)
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: maxWidth * 0.88)
                        .id("desc-\(effect.id)")
                        .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: centeredEffectID)
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

    // MARK: - Loading Skeleton

    private var loadingOverlay: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width * 0.82
            let cardHeight = geo.size.height * 0.72

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.videoSurface)
                        .frame(width: 140, height: 24)
                        .shimmer()

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.videoSurface)
                        .frame(width: 200, height: 16)
                        .shimmer()
                }

                Spacer(minLength: 0)

                RoundedRectangle(cornerRadius: VideoSpacing.radiusXLarge)
                    .fill(Color.videoSurface)
                    .frame(width: cardWidth, height: cardHeight)
                    .shimmer()

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
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
