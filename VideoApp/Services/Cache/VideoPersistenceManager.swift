//
//  VideoPersistenceManager.swift
//  AIVideo
//
//  Permanently stores generated videos in Documents/ so they survive
//  cache eviction and never need to be re-downloaded from the backend.
//

import Foundation

final class VideoPersistenceManager {
    static let shared = VideoPersistenceManager()

    private let fileManager = FileManager.default
    private let directory: URL
    /// Guards against duplicate concurrent persist calls for the same generation
    private var activePersists = Set<String>()
    private let lock = NSLock()

    private init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        directory = docs.appendingPathComponent("GeneratedVideos", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Local file URL for a generation (may or may not exist yet)
    func localURL(for generationId: String) -> URL {
        directory.appendingPathComponent("\(generationId).mp4")
    }

    /// Check if a video is already persisted locally
    func isPersisted(generationId: String) -> Bool {
        fileManager.fileExists(atPath: localURL(for: generationId).path)
    }

    /// Persist video data to Documents/GeneratedVideos/{generationId}.mp4
    /// Returns the local file path on success, nil on failure.
    /// MUST be called on a background thread — performs synchronous file I/O.
    private func persist(videoData: Data, generationId: String) -> String? {
        let url = localURL(for: generationId)
        do {
            try videoData.write(to: url, options: .atomic)
            // Exclude from iCloud backup to avoid eating user's iCloud quota
            var resourceURL = url
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try resourceURL.setResourceValues(resourceValues)
            print("💾 VideoPersistenceManager: Persisted \(generationId) (\(videoData.count / 1024)KB)")
            return url.lastPathComponent
        } catch {
            print("❌ VideoPersistenceManager: Failed to persist \(generationId): \(error)")
            return nil
        }
    }

    /// Persist video from its remote URL — downloads if not in cache.
    /// All file I/O runs off the main thread. Calls completion on main thread.
    func persistFromRemote(
        remoteUrlString: String,
        generationId: String,
        completion: @escaping (String?) -> Void
    ) {
        // Already persisted?
        if isPersisted(generationId: generationId) {
            DispatchQueue.main.async {
                completion(self.localURL(for: generationId).lastPathComponent)
            }
            return
        }

        // Dedup: skip if already persisting this generation
        lock.lock()
        guard !activePersists.contains(generationId) else {
            lock.unlock()
            return
        }
        activePersists.insert(generationId)
        lock.unlock()

        guard let remoteUrl = URL(string: remoteUrlString) else {
            removePersistGuard(generationId)
            DispatchQueue.main.async { completion(nil) }
            return
        }

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer { self.removePersistGuard(generationId) }

            let data: Data

            // Try disk cache first (read off main thread)
            if let cachedURL = VideoCacheManager.shared.cachedURL(for: remoteUrl),
               let cachedData = try? Data(contentsOf: cachedURL) {
                data = cachedData
            } else {
                // Download from network
                do {
                    let (downloaded, response) = try await URLSession.shared.data(from: remoteUrl)
                    guard let http = response as? HTTPURLResponse,
                          (200...299).contains(http.statusCode),
                          downloaded.count > 1000 else {
                        await MainActor.run { completion(nil) }
                        return
                    }
                    data = downloaded
                } catch {
                    print("❌ VideoPersistenceManager: Download failed for \(generationId): \(error)")
                    await MainActor.run { completion(nil) }
                    return
                }
            }

            let path = self.persist(videoData: data, generationId: generationId)
            await MainActor.run { completion(path) }
        }
    }

    /// Delete a persisted video
    func delete(generationId: String) {
        let url = localURL(for: generationId)
        try? fileManager.removeItem(at: url)
    }

    private func removePersistGuard(_ id: String) {
        lock.lock()
        activePersists.remove(id)
        lock.unlock()
    }
}
