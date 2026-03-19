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

// MARK: - Preview

#Preview {
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
    .padding()
    .background(Color.videoBackground)
}
