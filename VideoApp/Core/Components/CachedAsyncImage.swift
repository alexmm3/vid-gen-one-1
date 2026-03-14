//
//  CachedAsyncImage.swift
//  AIVideo
//
//  Async image view with disk + memory caching
//

import SwiftUI

/// Async image loader with caching support
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    var body: some View {
        CachedAsyncImageContent(url: url, content: content, placeholder: placeholder)
            .id(url?.absoluteString ?? "nil_url")
    }
}

private struct CachedAsyncImageContent<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var image: UIImage?
    @State private var isLoading = false
    
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        
        if let url = url, let cached = ImageCacheManager.shared.getMemoryCachedImage(for: url) {
            _image = State(initialValue: cached)
        }
    }
    
    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else {
                placeholder()
                    .onAppear {
                        loadImage()
                    }
            }
        }
        .onChange(of: url) { _, newUrl in
            if let url = newUrl, let cached = ImageCacheManager.shared.getMemoryCachedImage(for: url) {
                image = cached
                isLoading = false
            } else {
                // Reset and reload when URL changes
                image = nil
                isLoading = false
                loadImage()
            }
        }
    }
    
    private func loadImage() {
        guard let url = url, !isLoading else { return }
        
        isLoading = true
        
        Task {
            let loadedImage = await ImageCacheManager.shared.loadImage(from: url)
            await MainActor.run {
                self.image = loadedImage
                self.isLoading = false
            }
        }
    }
}

// MARK: - Convenience Initializers

extension CachedAsyncImage where Placeholder == Color {
    /// Simple initializer with default placeholder
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(url: url, content: content) {
            Color.videoSurface
        }
    }
}

extension CachedAsyncImage where Content == Image, Placeholder == Color {
    /// Simplest initializer - just pass URL
    init(url: URL?) {
        self.init(url: url) { image in
            image
        } placeholder: {
            Color.videoSurface
        }
    }
}

// MARK: - Video Thumbnail View

/// View that displays video thumbnail with caching
/// Falls back to video first frame if no thumbnail URL provided
struct VideoThumbnailView: View {
    let thumbnailUrl: URL?
    let videoUrl: URL?
    
    var body: some View {
        VideoThumbnailContentView(thumbnailUrl: thumbnailUrl, videoUrl: videoUrl)
            .id(thumbnailUrl?.absoluteString ?? videoUrl?.absoluteString ?? "nil_url")
    }
}

private struct VideoThumbnailContentView: View {
    let thumbnailUrl: URL?
    let videoUrl: URL?
    
    @State private var thumbnail: UIImage?
    @State private var isLoading = false
    
    init(thumbnailUrl: URL?, videoUrl: URL?) {
        self.thumbnailUrl = thumbnailUrl
        self.videoUrl = videoUrl
        
        // Try to load synchronously from memory cache to avoid flashes during scroll
        if let url = thumbnailUrl, let cached = ImageCacheManager.shared.getMemoryCachedImage(for: url) {
            _thumbnail = State(initialValue: cached)
        } else if let url = videoUrl {
            let thumbnailKey = URL(string: url.absoluteString + "_thumb")!
            if let cached = ImageCacheManager.shared.getMemoryCachedImage(for: thumbnailKey) {
                _thumbnail = State(initialValue: cached)
            }
        }
    }
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Loading placeholder
                Color.videoSurface
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .videoTextTertiary))
                    )
            }
        }
        .onAppear {
            loadThumbnail()
        }
        .onChange(of: thumbnailUrl) { _, _ in
            reload()
        }
        .onChange(of: videoUrl) { _, _ in
            reload()
        }
    }
    
    private func reload() {
        if let url = thumbnailUrl, let cached = ImageCacheManager.shared.getMemoryCachedImage(for: url) {
            thumbnail = cached
            isLoading = false
            return
        }
        if let url = videoUrl {
            let thumbnailKey = URL(string: url.absoluteString + "_thumb")!
            if let cached = ImageCacheManager.shared.getMemoryCachedImage(for: thumbnailKey) {
                thumbnail = cached
                isLoading = false
                return
            }
        }
        thumbnail = nil
        isLoading = false
        loadThumbnail()
    }
    
    private func loadThumbnail() {
        guard !isLoading, thumbnail == nil else { return }
        isLoading = true
        
        Task {
            // First try thumbnail URL
            if let url = thumbnailUrl {
                if let image = await ImageCacheManager.shared.loadImage(from: url) {
                    await MainActor.run {
                        self.thumbnail = image
                        self.isLoading = false
                    }
                    return
                }
            }
            
            // Fall back to extracting from video
            if let url = videoUrl {
                let image = await extractVideoThumbnail(from: url)
                await MainActor.run {
                    self.thumbnail = image
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func extractVideoThumbnail(from url: URL) async -> UIImage? {
        // Check if we have a cached thumbnail for this video URL
        let thumbnailKey = URL(string: url.absoluteString + "_thumb")!
        if let cached = await ImageCacheManager.shared.loadImage(from: thumbnailKey) {
            return cached
        }
        
        // Extract thumbnail from video on a background thread.
        // copyCGImage(at:actualTime:) is synchronous and would block
        // the main thread if run in a MainActor-inherited Task.
        let thumbnail: UIImage? = await Task.detached(priority: .utility) {
            let asset = AVAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 400, height: 400)
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
                return UIImage(cgImage: cgImage)
            } catch {
                print("🖼️ Failed to extract video thumbnail: \(error.localizedDescription)")
                return nil
            }
        }.value
        
        // Cache the extracted thumbnail (back on caller's context)
        if let thumbnail = thumbnail {
            ImageCacheManager.shared.cacheImage(thumbnail, for: thumbnailKey)
        }
        
        return thumbnail
    }
}

import AVFoundation

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        CachedAsyncImage(
            url: URL(string: "https://via.placeholder.com/300")
        ) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Color.gray
        }
        .frame(width: 150, height: 200)
        .cornerRadius(12)
        
        VideoThumbnailView(
            thumbnailUrl: nil,
            videoUrl: URL(string: "https://example.com/video.mp4")
        )
        .frame(width: 150, height: 200)
        .cornerRadius(12)
    }
    .padding()
    .background(Color.videoBackground)
}
