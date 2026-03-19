//
//  HistoryItemActionHandler.swift
//  AIVideo
//
//  Shared quick actions for My Videos items.
//  Keep save/share logic here so HistoryDetailView and HistoryListView
//  always use identical behavior.
//

import Foundation
import Photos

enum HistoryItemActionHandler {
    static func saveToPhotos(generation: LocalGeneration) async throws {
        guard let urlString = generation.outputVideoUrl else {
            throw StorageServiceError.downloadFailed
        }
        
        let data = try await StorageService.shared.downloadVideo(from: urlString)
        try await saveVideoToPhotoLibrary(data: data)
    }
    
    static func prepareShareFile(for generation: LocalGeneration) async throws -> URL {
        guard let urlString = generation.outputVideoUrl else {
            throw StorageServiceError.downloadFailed
        }
        
        let data = try await StorageService.shared.downloadVideo(from: urlString)
        let fileName = sanitizedFileName(from: generation.displayName)
        let tempUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
            .appendingPathExtension("mp4")
        
        if FileManager.default.fileExists(atPath: tempUrl.path) {
            try? FileManager.default.removeItem(at: tempUrl)
        }
        
        try data.write(to: tempUrl)
        return tempUrl
    }
    
    static func cleanupTemporaryShareFile(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
    
    private static func saveVideoToPhotoLibrary(data: Data) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let tempUrl = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            
            do {
                try data.write(to: tempUrl)
                
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempUrl)
                } completionHandler: { success, error in
                    try? FileManager.default.removeItem(at: tempUrl)
                    
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error ?? StorageServiceError.downloadFailed)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private static func sanitizedFileName(from displayName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let replacedSpaces = displayName.replacingOccurrences(of: " ", with: "_")
        let scalars = replacedSpaces.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let joined = String(scalars)
        let trimmed = joined.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let suffix = String(UUID().uuidString.prefix(6))
        return trimmed.isEmpty ? UUID().uuidString : "\(trimmed)_\(suffix)"
    }
}
