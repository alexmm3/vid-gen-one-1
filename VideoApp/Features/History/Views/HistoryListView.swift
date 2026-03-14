//
//  HistoryListView.swift
//  AIVideo
//
//  My Videos list showing past and pending generations
//

import SwiftUI

struct HistoryListView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @ObservedObject private var activeGenerationManager = ActiveGenerationManager.shared
    
    // Navigation state for lazy destination loading
    @State private var selectedGeneration: LocalGeneration?
    
    /// Direct check for pending generation from the singleton
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
        .onAppear {
            viewModel.trackHistoryViewed()
            // Force sync with ActiveGenerationManager on appear
            viewModel.syncPendingGeneration()
        }
        .task {
            // Sync history from server, then check pending status
            await viewModel.syncHistory()
            await viewModel.refreshPendingStatus()
        }
        .refreshable {
            await viewModel.syncHistory()
            await viewModel.refreshPendingStatus()
        }
        // Lazy navigation destination - only creates HistoryDetailView when needed
        .navigationDestination(item: $selectedGeneration) { generation in
            HistoryDetailView(generation: generation)
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
                // Pending generation card (if any) - shown as first item in grid
                if let pending = activeGenerationManager.pendingGeneration {
                    pendingGenerationCard(pending)
                }
                
                // Completed generations - uses lazy navigation via Button + navigationDestination
                ForEach(viewModel.generations) { generation in
                    Button {
                        selectedGeneration = generation
                    } label: {
                        HistoryItemCard(generation: generation)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, VideoSpacing.screenHorizontal)
            .padding(.top, VideoSpacing.sm)
            .padding(.bottom, 100) // Space for tab bar
        }
    }
    
    // MARK: - Pending Generation Card
    // Matches the same size as completed video cards (9/16 aspect ratio)
    // Shows blurred user photo with centered spinner
    
    private func pendingGenerationCard(_ pending: PendingGeneration) -> some View {
        PendingGenerationCardView(pending: pending)
    }
}

// MARK: - Pending Generation Card View
// Extracted to its own struct for clarity

private struct PendingGenerationCardView: View {
    let pending: PendingGeneration
    
    var body: some View {
        Color.videoSurface
            .aspectRatio(9/16, contentMode: .fit)
            .overlay {
                ZStack {
                    // Blurred user photo background
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
                    
                    // Dark overlay to ensure text readability on bright photos
                    Color.black.opacity(0.3)
                    
                    // Centered generating indicator
                    VStack(spacing: VideoSpacing.md) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .videoAccent))
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
