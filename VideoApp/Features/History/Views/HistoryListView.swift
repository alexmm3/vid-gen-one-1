//
//  HistoryListView.swift
//  AIVideo
//
//  My Videos list showing past and pending generations.
//  Uses iOS 18 .zoom transition for seamless hero animation from card → fullscreen.
//

import SwiftUI

struct HistoryListView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @ObservedObject private var activeGenerationManager = ActiveGenerationManager.shared
    
    @State private var selectedGeneration: LocalGeneration?
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
        .fullScreenCover(item: $selectedGeneration) { generation in
            HistoryDetailView(generation: generation, namespace: heroNamespace)
                .heroZoomTarget(sourceID: generation.id, in: heroNamespace)
        }
        .onAppear {
            viewModel.trackHistoryViewed()
            viewModel.syncPendingGeneration()
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
}

// MARK: - Zoom Transition Helpers

extension View {
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
                            .blur(radius: 24)
                    } placeholder: {
                        Color.videoSurface
                    }
                    
                    Color.black.opacity(0.3)
                    
                    VStack(spacing: VideoSpacing.md) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.3)
                        
                        Text("Generating...")
                            .font(.videoCaption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HistoryListView()
    }
}
