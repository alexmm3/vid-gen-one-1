//
//  VideoPosterFrameView.swift
//  AIVideo
//
//  Cached poster frame extracted from the video itself.
//

import SwiftUI
import AVFoundation
import UIKit
import CryptoKit

final class VideoPosterFrameStore {
    static let shared = VideoPosterFrameStore()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let diskQueue = DispatchQueue(label: "com.aivideo.video-poster.disk", qos: .utility)
    private let cacheDirectory: URL

    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]
    private let taskLock = NSLock()

    private init() {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDirectory.appendingPathComponent("VideoPosterCache")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func cachedImage(for url: URL) -> UIImage? {
        let key = cacheKey(for: url) as NSString
        if let image = memoryCache.object(forKey: key) {
            return image
        }

        let fileURL = diskURL(for: url)
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }

        memoryCache.setObject(image, forKey: key, cost: data.count)
        return image
    }

    func prefetch(urls: [URL]) {
        urls.forEach { prefetch(url: $0) }
    }

    func prefetch(url: URL) {
        guard cachedImage(for: url) == nil else { return }
        Task(priority: .utility) {
            _ = await poster(for: url)
        }
    }

    func poster(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) {
            return cached
        }

        let key = cacheKey(for: url)

        taskLock.lock()
        if let existingTask = inFlightTasks[key] {
            taskLock.unlock()
            return await existingTask.value
        }

        let task = Task<UIImage?, Never>(priority: .utility) { [weak self] in
            guard let self = self else { return nil }
            let image = await self.generatePoster(for: url)
            self.taskLock.lock()
            self.inFlightTasks.removeValue(forKey: key)
            self.taskLock.unlock()
            return image
        }
        inFlightTasks[key] = task
        taskLock.unlock()

        return await task.value
    }

    private func generatePoster(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) {
            return cached
        }

        VideoCacheManager.shared.prefetch(url: url)

        let sourceURL = VideoCacheManager.shared.cachedURL(for: url) ?? url
        let image: UIImage? = await Task.detached(priority: .utility) {
            let asset = AVAsset(url: sourceURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 900, height: 1600)

            let candidateTimes = [
                CMTime(seconds: 0.15, preferredTimescale: 600),
                CMTime(seconds: 0.35, preferredTimescale: 600),
                CMTime(seconds: 0.75, preferredTimescale: 600),
                .zero
            ]

            for time in candidateTimes {
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    return UIImage(cgImage: cgImage)
                }
            }

            return nil
        }.value

        guard let image else { return nil }

        cache(image, for: url)
        return image
    }

    private func cache(_ image: UIImage, for url: URL) {
        let key = cacheKey(for: url) as NSString
        memoryCache.setObject(image, forKey: key)

        diskQueue.async { [fileManager, cacheDirectory] in
            guard let data = image.jpegData(compressionQuality: 0.82) else { return }
            let fileURL = cacheDirectory.appendingPathComponent("\(Self.sha256(of: url.absoluteString)).jpg")
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func cacheKey(for url: URL) -> String {
        url.absoluteString
    }

    private func diskURL(for url: URL) -> URL {
        cacheDirectory.appendingPathComponent("\(Self.sha256(of: url.absoluteString)).jpg")
    }

    private static func sha256(of string: String) -> String {
        let hash = SHA256.hash(data: Data(string.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

struct VideoPosterFrameView: View {
    let videoURL: URL?
    var contentMode: ContentMode = .fill

    @State private var poster: UIImage?
    @State private var isLoading = false
    @State private var activeURLString: String?

    init(videoURL: URL?, contentMode: ContentMode = .fill) {
        self.videoURL = videoURL
        self.contentMode = contentMode

        if let videoURL, let cached = VideoPosterFrameStore.shared.cachedImage(for: videoURL) {
            _poster = State(initialValue: cached)
        }
    }

    var body: some View {
        Group {
            if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.videoSurface
            }
        }
        .task(id: videoURL?.absoluteString) {
            await prepareAndLoadPoster()
        }
    }

    private func prepareAndLoadPoster() async {
        let currentURLString = videoURL?.absoluteString
        activeURLString = currentURLString
        isLoading = false

        guard let videoURL else {
            poster = nil
            return
        }

        poster = VideoPosterFrameStore.shared.cachedImage(for: videoURL)
        await loadPosterIfNeeded(for: videoURL, urlString: currentURLString)
    }

    private func loadPosterIfNeeded(for videoURL: URL, urlString: String?) async {
        guard poster == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let image = await VideoPosterFrameStore.shared.poster(for: videoURL)
        guard !Task.isCancelled, activeURLString == urlString else { return }
        poster = image
    }
}
