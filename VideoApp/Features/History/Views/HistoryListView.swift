//
//  HistoryListView.swift
//  AIVideo
//
//  My Videos list showing past and pending generations.
//
//  ⚠️  PROVEN HERO TRANSITION — DO NOT CHANGE THE PRESENTATION PATTERN  ⚠️
//  Uses iOS 18 .fullScreenCover + .navigationTransition(.zoom) for a native
//  Photos-like hero animation. The card applies .matchedTransitionSource;
//  the detail view applies .navigationTransition(.zoom). System handles the
//  rest. See HistoryDetailView header for the full contract.
//

import SwiftUI
import StoreKit

struct HistoryListView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @ObservedObject private var activeGenerationManager = ActiveGenerationManager.shared
    @Environment(\.requestReview) private var requestReview
    @AppStorage(AppConstants.StorageKeys.hasShownPostVideoReview) private var hasShownPostVideoReview = false

    @State private var selectedGeneration: LocalGeneration?
    @State private var pendingDeleteGeneration: LocalGeneration?
    @State private var isSavingGenerationID: String?
    @State private var isSharingGenerationID: String?
    @State private var showSaveSuccess = false
    @State private var showSaveError = false
    @State private var shareFileUrl: URL?
    @State private var showShareSheet = false
    @State private var saveSuccessHideTask: Task<Void, Never>?
    @Namespace private var heroNamespace
    
    private var hasPending: Bool {
        activeGenerationManager.pendingGeneration != nil
    }
    
    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()
            
            if viewModel.generations.isEmpty && !hasPending {
                emptyState
            } else {
                historyContent
            }
        }
        .navigationTitle("My Videos")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // Keep fullScreenCover + zoom together.
        // Replacing this with an overlay / custom hero broke alignment and clipping.
        .fullScreenCover(item: $selectedGeneration, onDismiss: {
            requestPostVideoReviewIfNeeded()
        }) { generation in
            HistoryDetailView(generation: generation, namespace: heroNamespace)
                .heroZoomTarget(sourceID: generation.id, in: heroNamespace)
        }
        .sheet(isPresented: $showShareSheet) {
            if let fileUrl = shareFileUrl {
                ShareSheet(items: [fileUrl, ExternalURLs.shareAttribution]) {
                    HistoryItemActionHandler.cleanupTemporaryShareFile(fileUrl)
                }
                    .onDisappear {
                        shareFileUrl = nil
                    }
            }
        }
        .alert("Delete Video", isPresented: deleteAlertBinding) {
            Button("Cancel", role: .cancel) {
                pendingDeleteGeneration = nil
            }
            Button("Delete", role: .destructive) {
                guard let generation = pendingDeleteGeneration else { return }
                if selectedGeneration?.id == generation.id {
                    selectedGeneration = nil
                }
                viewModel.deleteGeneration(generation)
                pendingDeleteGeneration = nil
            }
        } message: {
            Text("This will remove the video from My Videos. This cannot be undone.")
        }
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK") { }
        } message: {
            Text("Unable to save video to Photos. Please check your permissions.")
        }
        .onAppear {
            viewModel.trackHistoryViewed()
            viewModel.syncPendingGeneration()
        }
        .onDisappear {
            saveSuccessHideTask?.cancel()
        }
        .overlay(alignment: .bottom) {
            if showSaveSuccess {
                saveSuccessToast
            }
        }
        .onChange(of: viewModel.generations) { _, generations in
            guard let selectedGeneration else { return }
            if !generations.contains(where: { $0.id == selectedGeneration.id }) {
                self.selectedGeneration = nil
            }
        }
        .task {
            await viewModel.syncHistory()
            await viewModel.refreshPendingStatus()
        }
        .refreshable {
            await viewModel.syncHistory()
            await viewModel.refreshPendingStatus()
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: VideoSpacing.md) {
            Spacer()
            
            Image(systemName: "film.stack")
                .font(.system(size: 60))
                .foregroundColor(.videoTextTertiary)
            
            Text("No Videos Yet")
                .font(.videoHeadline)
                .foregroundColor(.videoTextPrimary)
            
            Text("Your generated videos will appear here")
                .font(.videoBody)
                .foregroundColor(.videoTextSecondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Videos Content
    
    private var historyContent: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: VideoSpacing.sm),
                GridItem(.flexible(), spacing: VideoSpacing.sm)
            ], spacing: VideoSpacing.sm) {
                if let pending = activeGenerationManager.pendingGeneration {
                    pendingGenerationCard(pending)
                }
                
                ForEach(viewModel.generations) { generation in
                    Button {
                        HapticManager.shared.lightImpact()
                        selectedGeneration = generation
                    } label: {
                        HistoryItemCard(generation: generation)
                            .heroZoomSource(id: generation.id, in: heroNamespace)
                    }
                    .contextMenu {
                        contextMenu(for: generation)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, VideoSpacing.screenHorizontal)
            .padding(.top, VideoSpacing.sm)
            .padding(.bottom, 100)
        }
    }
    
    // MARK: - Pending Generation Card
    
    private func pendingGenerationCard(_ pending: PendingGeneration) -> some View {
        PendingGenerationCardView(pending: pending)
    }
    
    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteGeneration != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteGeneration = nil
                }
            }
        )
    }
    
    @ViewBuilder
    private func contextMenu(for generation: LocalGeneration) -> some View {
        Button {
            selectedGeneration = generation
        } label: {
            Label("Open", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        
        Button {
            save(generation: generation)
        } label: {
            Label("Save", systemImage: "square.and.arrow.down")
        }
        .disabled(generation.effectiveVideoUrl == nil || isSavingGenerationID != nil)

        Button {
            share(generation: generation)
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .disabled(generation.effectiveVideoUrl == nil || isSharingGenerationID != nil)
        
        Button(role: .destructive) {
            pendingDeleteGeneration = generation
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
    private func save(generation: LocalGeneration) {
        guard generation.effectiveVideoUrl != nil, isSavingGenerationID == nil else { return }
        isSavingGenerationID = generation.id
        Analytics.track(.videoSaved(effectName: generation.displayName))
        HapticManager.shared.lightImpact()

        Task {
            do {
                try await HistoryItemActionHandler.saveToPhotos(generation: generation)
                await MainActor.run {
                    isSavingGenerationID = nil
                    triggerSaveSuccessToast()
                    HapticManager.shared.success()
                }
            } catch {
                await MainActor.run {
                    isSavingGenerationID = nil
                    showSaveError = true
                    Analytics.track(.videoSaveFailed(error: error.localizedDescription))
                    HapticManager.shared.error()
                }
            }
        }
    }
    
    private func share(generation: LocalGeneration) {
        guard generation.effectiveVideoUrl != nil, isSharingGenerationID == nil else { return }
        isSharingGenerationID = generation.id
        Analytics.track(.videoShared(effectName: generation.displayName))
        HapticManager.shared.lightImpact()
        
        Task {
            do {
                let tempUrl = try await HistoryItemActionHandler.prepareShareFile(for: generation)
                await MainActor.run {
                    isSharingGenerationID = nil
                    shareFileUrl = tempUrl
                    showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isSharingGenerationID = nil
                    HapticManager.shared.error()
                }
            }
        }
    }
    
    private func triggerSaveSuccessToast() {
        saveSuccessHideTask?.cancel()
        showSaveSuccess = false
        Task { @MainActor in
            await Task.yield()
            showSaveSuccess = true
        }
        saveSuccessHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            showSaveSuccess = false
        }
    }
    
    private func requestPostVideoReviewIfNeeded() {
        guard !hasShownPostVideoReview else { return }
        hasShownPostVideoReview = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
            requestReview()
        }
    }

    private var saveSuccessToast: some View {
        HStack(spacing: VideoSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.videoAccent)
            Text("Saved to Photos")
                .font(.videoBody)
                .foregroundColor(.white)
        }
        .padding(.horizontal, VideoSpacing.lg)
        .padding(.vertical, VideoSpacing.md)
        .background(.ultraThinMaterial)
        .cornerRadius(VideoSpacing.radiusFull)
        .videoElevatedShadow()
        .padding(.bottom, 110)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSaveSuccess)
    }
}

// MARK: - Zoom Transition Helpers

extension View {
    // These two helpers are intentionally tiny wrappers around the system API.
    // When the hero transition was flaky, the reliable fix was NOT more custom
    // animation code - it was preserving the native matchedTransitionSource/zoom pair.
    func heroZoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        self.matchedTransitionSource(id: id, in: namespace)
    }
    
    func heroZoomTarget(sourceID: some Hashable, in namespace: Namespace.ID) -> some View {
        self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
    }
}

// MARK: - Pending Generation Card View

private struct PendingGenerationCardView: View {
    let pending: PendingGeneration

    @State private var pulseScale: CGFloat = 1.0
    @State private var backgroundScale: CGFloat = 1.0
    @State private var gradientPosition: UnitPoint = UnitPoint(x: -1, y: -1)

    var body: some View {
        Color.videoSurface
            .aspectRatio(9/16, contentMode: .fit)
            .overlay {
                ZStack {
                    CachedAsyncImage(
                        url: URL(string: pending.inputImageUrl)
                    ) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .scaleEffect(backgroundScale)
                            .blur(radius: 24)
                    } placeholder: {
                        Color.videoSurface
                    }

                    Color.black.opacity(0.4)

                    // Shimmer overlay
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: gradientPosition,
                        endPoint: UnitPoint(x: gradientPosition.x + 1, y: gradientPosition.y + 1)
                    )
                    .blendMode(.plusLighter)

                    // Pulsing icon + label
                    VStack(spacing: VideoSpacing.sm) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 44, height: 44)
                                .scaleEffect(pulseScale)

                            Image(systemName: "wand.and.sparkles")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                        }

                        Text("Generating...")
                            .font(.videoCaption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium))
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseScale = 1.2
                }
                withAnimation(.easeInOut(duration: 10.0).repeatForever(autoreverses: true)) {
                    backgroundScale = 1.12
                }
                withAnimation(.linear(duration: 5.0).repeatForever(autoreverses: false)) {
                    gradientPosition = UnitPoint(x: 2, y: 2)
                }
            }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HistoryListView()
    }
}
