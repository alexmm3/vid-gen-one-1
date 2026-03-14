//
//  TemplateGalleryView.swift
//  AIVideo
//
//  Template gallery for browsing video templates
//

import SwiftUI

struct TemplateGalleryView: View {
    @StateObject private var viewModel = TemplateGalleryViewModel()
    @EnvironmentObject var appState: AppState
    @State private var selectedSource: TemplateSource = .templates
    
    enum TemplateSource: String, CaseIterable {
        case templates = "Templates"
        case myVideo = "My Video"
    }
    
    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Generations remaining banner (for premium users)
                if appState.isPremiumUser {
                    generationsRemainingBanner
                        .padding(.horizontal, VideoSpacing.screenHorizontal)
                        .padding(.top, VideoSpacing.sm)
                }
                
                // Source toggle
                sourceToggle
                    .padding(.horizontal, VideoSpacing.screenHorizontal)
                    .padding(.top, VideoSpacing.sm)
                
                // Content
                if selectedSource == .templates {
                    templateGrid
                } else {
                    customVideoSection
                }
            }
        }
        .navigationTitle("Create")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await viewModel.loadTemplates()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
    
    // MARK: - Generations Remaining Banner
    
    private var generationsRemainingBanner: some View {
        HStack(spacing: VideoSpacing.sm) {
            Image(systemName: "film")
                .font(.system(size: 16))
                .foregroundColor(.videoAccent)
            
            if let remaining = appState.generationsRemaining {
                Text("\(remaining) videos remaining this period")
                    .font(.videoCaption)
                    .foregroundColor(.videoTextPrimary)
            } else {
                Text("Unlimited videos available")
                    .font(.videoCaption)
                    .foregroundColor(.videoTextPrimary)
            }
            
            Spacer()
        }
        .padding(.horizontal, VideoSpacing.md)
        .padding(.vertical, VideoSpacing.sm)
        .background(Color.videoAccent.opacity(0.1))
        .cornerRadius(VideoSpacing.radiusMedium)
    }
    
    // MARK: - Source Toggle
    
    private var sourceToggle: some View {
        HStack(spacing: 0) {
            ForEach(TemplateSource.allCases, id: \.self) { source in
                toggleButton(source: source)
            }
        }
        .background(Color.videoSurface)
        .cornerRadius(VideoSpacing.radiusMedium)
    }
    
    private func toggleButton(source: TemplateSource) -> some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSource = source
            }
        } label: {
            Text(source.rawValue)
                .font(.videoBody)
                .fontWeight(selectedSource == source ? .semibold : .regular)
                .foregroundColor(selectedSource == source ? .videoAccent : .videoTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, VideoSpacing.sm)
                .background(selectedSource == source ? Color.videoAccent.opacity(0.1) : Color.clear)
        }
    }
    
    // MARK: - Template Grid
    
    private var templateGrid: some View {
        Group {
            if viewModel.isLoading && viewModel.templates.isEmpty {
                loadingView
            } else if viewModel.templates.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: VideoSpacing.sm),
                        GridItem(.flexible(), spacing: VideoSpacing.sm)
                    ], spacing: VideoSpacing.sm) {
                        ForEach(viewModel.templates) { template in
                            NavigationLink(destination: TemplateDetailView(template: template)) {
                                TemplateCardView(template: template)
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                    }
                    .padding(VideoSpacing.screenHorizontal)
                    .padding(.bottom, 100) // Space for tab bar
                }
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: VideoSpacing.md) {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .videoAccent))
                .scaleEffect(1.5)
            Text("Loading templates...")
                .font(.videoBody)
                .foregroundColor(.videoTextSecondary)
            Spacer()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: VideoSpacing.md) {
            Spacer()
            
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.videoTextTertiary)
            
            Text("No Templates Available")
                .font(.videoHeadline)
                .foregroundColor(.videoTextPrimary)
            
            Text("Check back soon for new video templates")
                .font(.videoBody)
                .foregroundColor(.videoTextSecondary)
                .multilineTextAlignment(.center)
            
            VideoButton(title: "Refresh", action: {
                Task {
                    await viewModel.refresh()
                }
            }, style: .secondary)
            .padding(.horizontal, VideoSpacing.xxl)
            .padding(.top, VideoSpacing.md)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Custom Video Section
    
    private var customVideoSection: some View {
        VStack(spacing: VideoSpacing.lg) {
            Spacer()
            
            Image(systemName: "video.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.videoTextTertiary)
            
            Text("Use Your Own Video")
                .font(.videoHeadline)
                .foregroundColor(.videoTextPrimary)
            
            Text("Upload a custom video as reference")
                .font(.videoBody)
                .foregroundColor(.videoTextSecondary)
                .multilineTextAlignment(.center)
            
            Text("Coming Soon")
                .font(.videoCaption)
                .foregroundColor(.videoAccent)
                .padding(.horizontal, VideoSpacing.md)
                .padding(.vertical, VideoSpacing.xs)
                .background(Color.videoAccent.opacity(0.1))
                .cornerRadius(VideoSpacing.radiusSmall)
            
            Spacer()
            Spacer()
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TemplateGalleryView()
    }
}
