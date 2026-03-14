//
//  VideoCacheManager.swift
//  AIVideo
//
//  Manages video caching with both memory and disk storage
//

import Foundation
import AVFoundation
import UIKit
import CryptoKit

/// Manages video asset caching for improved performance
final class VideoCacheManager {
    // MARK: - Singleton
    static let shared = VideoCacheManager()
    
    // MARK: - Configuration
    private enum Config {
        /// Maximum memory cache size (50 MB)
        static let memoryCacheLimit = 50 * 1024 * 1024
        /// Maximum disk cache size (500 MB)
        static let diskCacheLimit = 500 * 1024 * 1024
        /// Cache expiry time (7 days)
        static let cacheExpirySeconds: TimeInterval = 7 * 24 * 60 * 60
        /// Cache directory name
        static let cacheDirectoryName = "VideoCache"
        /// Cache version - increment when cache key algorithm changes or to force fresh downloads
        static let cacheVersion = 5 // v5: Fixed CWalk template video_url to correct R2 source
        static let cacheVersionKey = "VideoCacheVersion"
    }
    
    // MARK: - Properties
    
    /// In-memory cache for AVAssets (keyed by URL string)
    private let assetCache = NSCache<NSString, AVURLAsset>()
    
    /// In-memory cache for video data
    private let dataCache = NSCache<NSString, NSData>()
    
    /// Disk cache directory
    private let cacheDirectory: URL
    
    /// File manager
    private let fileManager = FileManager.default
    
    /// Serial queue for thread-safe disk operations
    private let diskQueue = DispatchQueue(label: "com.aivideo.videocache.disk", qos: .utility)
    
    /// Currently downloading URLs to prevent duplicate downloads
    private var activeDownloads = Set<String>()
    private let downloadsLock = NSLock()
    
    // MARK: - Initialization
    
    private init() {
        // Configure memory cache limits
        assetCache.totalCostLimit = Config.memoryCacheLimit
        dataCache.totalCostLimit = Config.memoryCacheLimit
        
        // Setup disk cache directory
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDirectory.appendingPathComponent(Config.cacheDirectoryName)
        
        // Create directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Check cache version - clear if outdated (fixes cache key collision bug)
        let storedVersion = UserDefaults.standard.integer(forKey: Config.cacheVersionKey)
        if storedVersion != Config.cacheVersion {
            print("📦 VideoCacheManager: Cache version changed (\(storedVersion) -> \(Config.cacheVersion)), clearing old cache...")
            clearCacheSync()
            UserDefaults.standard.set(Config.cacheVersion, forKey: Config.cacheVersionKey)
        }
        
        // Clean up expired cache on init
        cleanExpiredCache()
        
        print("📦 VideoCacheManager initialized at: \(cacheDirectory.path)")
    }
    
    /// Synchronously clear cache (used during init)
    private func clearCacheSync() {
        assetCache.removeAllObjects()
        dataCache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        print("📦 VideoCacheManager: Cache cleared due to version upgrade")
    }
    
    // MARK: - Public API
    
    /// Get cached AVAsset or create one with caching
    /// - Parameter url: Remote video URL
    /// - Returns: AVURLAsset (from cache or newly created)
    func asset(for url: URL) -> AVURLAsset {
        let key = url.absoluteString as NSString
        
        // Check memory cache first
        if let cached = assetCache.object(forKey: key) {
            return cached
        }
        
        // Check disk cache
        if let localURL = diskCacheURL(for: url), fileManager.fileExists(atPath: localURL.path) {
            // Update access time
            touchFile(at: localURL)
            
            let asset = AVURLAsset(url: localURL)
            assetCache.setObject(asset, forKey: key)
            return asset
        }
        
        // Create asset from remote URL and start background download
        let asset = AVURLAsset(url: url)
        assetCache.setObject(asset, forKey: key)
        
        // Start background download for future use
        downloadToCache(url: url)
        
        return asset
    }
    
    /// Check if video is cached on disk
    /// - Parameter url: Remote video URL
    /// - Returns: True if cached on disk
    func isCached(url: URL) -> Bool {
        guard let localURL = diskCacheURL(for: url) else { return false }
        return fileManager.fileExists(atPath: localURL.path)
    }
    
    /// Get local cached URL if available
    /// - Parameter url: Remote video URL
    /// - Returns: Local file URL if cached, nil otherwise
    func cachedURL(for url: URL) -> URL? {
        guard let localURL = diskCacheURL(for: url),
              fileManager.fileExists(atPath: localURL.path) else {
            return nil
        }
        touchFile(at: localURL)
        return localURL
    }
    
    /// Prefetch video to cache (non-blocking)
    /// - Parameter url: Remote video URL to prefetch
    func prefetch(url: URL) {
        guard !isCached(url: url) else { return }
        downloadToCache(url: url)
    }
    
    /// Prefetch multiple videos
    /// - Parameter urls: Array of URLs to prefetch
    func prefetch(urls: [URL]) {
        urls.forEach { prefetch(url: $0) }
    }
    
    /// Cache video data directly (e.g., after generation completes)
    /// - Parameters:
    ///   - data: Video data to cache
    ///   - url: Original remote URL (used as cache key)
    func cacheVideoData(_ data: Data, for url: URL) {
        diskQueue.async { [weak self] in
            guard let self = self,
                  let localURL = self.diskCacheURL(for: url) else { return }
            
            do {
                try data.write(to: localURL)
                print("📦 Cached video data for: \(url.lastPathComponent)")
            } catch {
                print("📦 Failed to cache video: \(error.localizedDescription)")
            }
        }
    }
    
    /// Clear all cached videos
    func clearCache() {
        // Clear memory caches
        assetCache.removeAllObjects()
        dataCache.removeAllObjects()
        
        // Clear disk cache
        diskQueue.async { [weak self] in
            guard let self = self else { return }
            try? self.fileManager.removeItem(at: self.cacheDirectory)
            try? self.fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
            print("📦 Cache cleared")
        }
    }
    
    /// Get current cache size in bytes
    func cacheSize() -> Int {
        var totalSize = 0
        
        if let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += size
                }
            }
        }
        
        return totalSize
    }
    
    /// Formatted cache size string
    var formattedCacheSize: String {
        let bytes = cacheSize()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // MARK: - Private Methods
    
    /// Generate local cache URL for a remote URL
    private func diskCacheURL(for url: URL) -> URL? {
        // Create a safe filename using SHA256 hash of the full URL
        // This ensures unique cache keys even for URLs with same prefix
        // CRITICAL FIX: Previously used base64.prefix(100) which caused collision
        // for URLs with same prefix (all Supabase storage URLs)
        let urlString = url.absoluteString
        guard let data = urlString.data(using: .utf8) else { return nil }
        
        // Use SHA256 hash for unique, fixed-length filename
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        // Preserve extension
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        return cacheDirectory.appendingPathComponent("\(hashString).\(ext)")
    }
    
    /// Download video to disk cache
    private func downloadToCache(url: URL) {
        let urlString = url.absoluteString
        
        // Check if already downloading
        downloadsLock.lock()
        guard !activeDownloads.contains(urlString) else {
            downloadsLock.unlock()
            return
        }
        activeDownloads.insert(urlString)
        downloadsLock.unlock()
        
        // Download in background
        Task(priority: .utility) { [weak self] in
            defer {
                self?.downloadsLock.lock()
                self?.activeDownloads.remove(urlString)
                self?.downloadsLock.unlock()
            }
            
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    return
                }
                
                // Verify we have valid video data (check for common video signatures)
                guard data.count > 1000 else { return }
                
                self?.cacheVideoData(data, for: url)
            } catch {
                print("📦 Background download failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// Update file access time (for LRU tracking)
    private func touchFile(at url: URL) {
        diskQueue.async { [weak self] in
            try? self?.fileManager.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: url.path
            )
        }
    }
    
    /// Clean expired cache files
    private func cleanExpiredCache() {
        diskQueue.async { [weak self] in
            guard let self = self else { return }
            
            let expiryDate = Date().addingTimeInterval(-Config.cacheExpirySeconds)
            var totalSize = 0
            var files: [(url: URL, date: Date, size: Int)] = []
            
            // Enumerate cache files
            if let enumerator = self.fileManager.enumerator(
                at: self.cacheDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            ) {
                while let fileURL = enumerator.nextObject() as? URL {
                    guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                          let modDate = values.contentModificationDate,
                          let size = values.fileSize else { continue }
                    
                    // Remove expired files
                    if modDate < expiryDate {
                        try? self.fileManager.removeItem(at: fileURL)
                        print("📦 Removed expired cache: \(fileURL.lastPathComponent)")
                    } else {
                        files.append((fileURL, modDate, size))
                        totalSize += size
                    }
                }
            }
            
            // If over disk limit, remove oldest files (LRU)
            if totalSize > Config.diskCacheLimit {
                files.sort { $0.date < $1.date } // Oldest first
                
                for file in files {
                    if totalSize <= Config.diskCacheLimit { break }
                    try? self.fileManager.removeItem(at: file.url)
                    totalSize -= file.size
                    print("📦 LRU evicted: \(file.url.lastPathComponent)")
                }
            }
        }
    }
}
