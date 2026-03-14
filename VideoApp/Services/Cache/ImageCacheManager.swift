//
//  ImageCacheManager.swift
//  AIVideo
//
//  Manages image/thumbnail caching with memory and disk storage
//

import Foundation
import UIKit
import CryptoKit

/// Manages image caching for thumbnails and other images
final class ImageCacheManager {
    // MARK: - Singleton
    static let shared = ImageCacheManager()
    
    // MARK: - Configuration
    private enum Config {
        /// Maximum memory cache count
        static let memoryCacheCountLimit = 100
        /// Maximum memory cache size (100 MB)
        static let memoryCacheSizeLimit = 100 * 1024 * 1024
        /// Maximum disk cache size (200 MB)
        static let diskCacheLimit = 200 * 1024 * 1024
        /// Cache directory name
        static let cacheDirectoryName = "ImageCache"
        /// Cache version - increment to clear old cache
        static let cacheVersion = 2
        static let cacheVersionKey = "ImageCacheVersion"
    }
    
    // MARK: - Properties
    
    /// In-memory image cache
    private let imageCache = NSCache<NSString, UIImage>()
    
    /// Disk cache directory
    private let cacheDirectory: URL
    
    /// File manager
    private let fileManager = FileManager.default
    
    /// Serial queue for disk operations
    private let diskQueue = DispatchQueue(label: "com.aivideo.imagecache.disk", qos: .utility)
    
    /// Currently loading URLs to prevent duplicate fetches
    private var activeLoads = Set<String>()
    private let loadsLock = NSLock()
    
    // MARK: - Initialization
    
    private init() {
        // Configure memory cache
        imageCache.countLimit = Config.memoryCacheCountLimit
        imageCache.totalCostLimit = Config.memoryCacheSizeLimit
        
        // Setup disk cache directory
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDirectory.appendingPathComponent(Config.cacheDirectoryName)
        
        // Create directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Check cache version - clear if outdated (fixes cache key collision bug)
        let storedVersion = UserDefaults.standard.integer(forKey: Config.cacheVersionKey)
        if storedVersion != Config.cacheVersion {
            print("🖼️ ImageCacheManager: Cache version changed (\(storedVersion) -> \(Config.cacheVersion)), clearing old cache...")
            clearCacheSync()
            UserDefaults.standard.set(Config.cacheVersion, forKey: Config.cacheVersionKey)
        }
        
        print("🖼️ ImageCacheManager initialized at: \(cacheDirectory.path)")
    }
    
    /// Synchronously clear cache (used during init)
    private func clearCacheSync() {
        imageCache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Public API
    
    /// Synchronously get image from memory cache only
    func getMemoryCachedImage(for url: URL) -> UIImage? {
        let key = url.absoluteString as NSString
        return imageCache.object(forKey: key)
    }
    
    /// Load image from cache or network
    /// - Parameters:
    ///   - url: Image URL
    ///   - completion: Callback with loaded image
    func loadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
        let key = url.absoluteString as NSString
        
        // Check memory cache
        if let cached = imageCache.object(forKey: key) {
            completion(cached)
            return
        }
        
        // Check disk cache
        if let localURL = diskCacheURL(for: url),
           let data = try? Data(contentsOf: localURL),
           let image = UIImage(data: data) {
            // Store in memory cache
            imageCache.setObject(image, forKey: key, cost: data.count)
            completion(image)
            return
        }
        
        // Fetch from network
        fetchImage(from: url, completion: completion)
    }
    
    /// Async version of loadImage
    func loadImage(from url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            loadImage(from: url) { image in
                continuation.resume(returning: image)
            }
        }
    }
    
    /// Check if image is cached
    func isCached(url: URL) -> Bool {
        let key = url.absoluteString as NSString
        if imageCache.object(forKey: key) != nil { return true }
        if let localURL = diskCacheURL(for: url) {
            return fileManager.fileExists(atPath: localURL.path)
        }
        return false
    }
    
    /// Prefetch images
    func prefetch(urls: [URL]) {
        for url in urls {
            guard !isCached(url: url) else { continue }
            fetchImage(from: url) { _ in }
        }
    }
    
    /// Cache image directly
    func cacheImage(_ image: UIImage, for url: URL) {
        let key = url.absoluteString as NSString
        
        // Memory cache
        imageCache.setObject(image, forKey: key)
        
        // Disk cache
        diskQueue.async { [weak self] in
            guard let self = self,
                  let localURL = self.diskCacheURL(for: url),
                  let data = image.jpegData(compressionQuality: 0.85) else { return }
            
            try? data.write(to: localURL)
        }
    }
    
    /// Clear cache
    func clearCache() {
        imageCache.removeAllObjects()
        diskQueue.async { [weak self] in
            guard let self = self else { return }
            try? self.fileManager.removeItem(at: self.cacheDirectory)
            try? self.fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Private Methods
    
    private func diskCacheURL(for url: URL) -> URL? {
        let urlString = url.absoluteString
        guard let data = urlString.data(using: .utf8) else { return nil }
        
        // Use SHA256 hash for unique, fixed-length filename
        // CRITICAL FIX: Previously used base64.prefix(100) which caused collision
        // for URLs with same prefix (all Supabase storage URLs)
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        return cacheDirectory.appendingPathComponent("\(hashString).jpg")
    }
    
    private func fetchImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
        let urlString = url.absoluteString
        
        // Prevent duplicate fetches
        loadsLock.lock()
        guard !activeLoads.contains(urlString) else {
            loadsLock.unlock()
            completion(nil)
            return
        }
        activeLoads.insert(urlString)
        loadsLock.unlock()
        
        Task {
            defer {
                loadsLock.lock()
                activeLoads.remove(urlString)
                loadsLock.unlock()
            }
            
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let image = UIImage(data: data) else {
                    await MainActor.run { completion(nil) }
                    return
                }
                
                // Cache the image
                let key = url.absoluteString as NSString
                imageCache.setObject(image, forKey: key, cost: data.count)
                
                // Save to disk
                if let localURL = diskCacheURL(for: url) {
                    diskQueue.async { [weak self] in
                        try? data.write(to: localURL)
                    }
                }
                
                await MainActor.run { completion(image) }
            } catch {
                await MainActor.run { completion(nil) }
            }
        }
    }
}
