//
//  UserVideoService.swift
//  AIVideo
//
//  Service for managing user-uploaded custom videos
//  Handles local storage and Supabase sync
//

import Foundation
import UIKit
import AVFoundation

@MainActor
final class UserVideoService: ObservableObject {
    // MARK: - Singleton
    static let shared = UserVideoService()
    
    // MARK: - Constants
    static let maxFileSizeBytes: Int64 = 50 * 1024 * 1024  // 50 MB
    static let videosDirectory = "UserVideos"
    static let thumbnailsDirectory = "UserVideoThumbnails"
    static let localStorageKey = "localUserVideos"
    
    // MARK: - Published Properties
    @Published private(set) var localVideos: [LocalUserVideo] = []
    @Published private(set) var remoteVideos: [UserVideo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isUploading = false
    @Published private(set) var uploadProgress: Double = 0
    @Published private(set) var error: Error?
    
    // MARK: - Private
    private let fileManager = FileManager.default
    private let deviceId: String
    
    private var videosDirectoryURL: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent(Self.videosDirectory)
    }
    
    private var thumbnailsDirectoryURL: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent(Self.thumbnailsDirectory)
    }
    
    // MARK: - Initialization
    
    private init() {
        self.deviceId = DeviceManager.shared.deviceId
        setupDirectories()
        loadLocalVideos()
    }
    
    // MARK: - Setup
    
    private func setupDirectories() {
        try? fileManager.createDirectory(at: videosDirectoryURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: thumbnailsDirectoryURL, withIntermediateDirectories: true)
    }
    
    // MARK: - Public Methods
    
    /// Load all videos (local + remote)
    func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        
        loadLocalVideos()
        await fetchRemoteVideos()
    }
    
    /// Import a video from URL (gallery picker)
    func importVideo(from sourceURL: URL, name: String? = nil) async throws -> LocalUserVideo {
        // Check file size
        let attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        guard fileSize <= Self.maxFileSizeBytes else {
            throw UserVideoServiceError.fileTooLarge(maxMB: Int(Self.maxFileSizeBytes / 1024 / 1024))
        }
        
        // Generate unique filename
        let videoId = UUID()
        let filename = "\(videoId.uuidString).mp4"
        let destinationURL = videosDirectoryURL.appendingPathComponent(filename)
        
        // Copy video to local storage
        if sourceURL.startAccessingSecurityScopedResource() {
            defer { sourceURL.stopAccessingSecurityScopedResource() }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } else {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
        
        // Crop video to 9:16 aspect ratio (center crop) for API compatibility
        try await cropVideoTo9by16(at: destinationURL)
        
        // Generate thumbnail (from cropped video)
        let thumbnailPath = await generateThumbnail(for: destinationURL, videoId: videoId)
        
        // Get video duration
        let duration = await getVideoDuration(url: destinationURL)
        
        // Create local video record
        let videoName = name ?? sourceURL.deletingPathExtension().lastPathComponent
        let localVideo = LocalUserVideo(
            id: videoId,
            localVideoPath: destinationURL.path,
            localThumbnailPath: thumbnailPath,
            name: videoName,
            durationSeconds: duration,
            fileSizeBytes: fileSize,
            createdAt: Date()
        )
        
        // Save to local storage
        localVideos.insert(localVideo, at: 0)
        saveLocalVideos()
        
        print("✅ UserVideoService: Imported video '\(videoName)'")
        
        return localVideo
    }
    
    /// Upload a local video to Supabase
    func uploadVideo(_ localVideo: LocalUserVideo) async throws {
        guard !localVideo.isUploaded else { return }
        
        isUploading = true
        uploadProgress = 0
        defer { 
            isUploading = false
            uploadProgress = 0
        }
        
        // Read video data
        let videoURL = URL(fileURLWithPath: localVideo.localVideoPath)
        let videoData = try Data(contentsOf: videoURL)
        
        // Upload to Supabase Storage
        let filename = "\(deviceId)/\(localVideo.id.uuidString).mp4"
        let storageUrl = "\(Secrets.supabaseUrl)/storage/v1/object/user-videos/\(filename)"
        
        var request = URLRequest(url: URL(string: storageUrl)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        request.httpBody = videoData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorStr = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ UserVideoService: Upload failed with status \((response as? HTTPURLResponse)?.statusCode ?? 0): \(errorStr)")
            throw UserVideoServiceError.uploadFailed
        }
        
        uploadProgress = 0.7
        
        // Get public URL
        let publicUrl = "\(Secrets.supabaseUrl)/storage/v1/object/public/user-videos/\(filename)"
        
        // Upload thumbnail if exists
        var thumbnailUrl: String? = nil
        if let thumbnailPath = localVideo.localThumbnailPath,
           let thumbnailData = try? Data(contentsOf: URL(fileURLWithPath: thumbnailPath)) {
            let thumbFilename = "\(deviceId)/\(localVideo.id.uuidString)_thumb.jpg"
            let thumbStorageUrl = "\(Secrets.supabaseUrl)/storage/v1/object/user-videos/\(thumbFilename)"
            
            var thumbRequest = URLRequest(url: URL(string: thumbStorageUrl)!)
            thumbRequest.httpMethod = "POST"
            thumbRequest.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            thumbRequest.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
            thumbRequest.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            thumbRequest.httpBody = thumbnailData
            
            let (_, thumbResponse) = try await URLSession.shared.data(for: thumbRequest)
            if let httpThumbResponse = thumbResponse as? HTTPURLResponse,
               (200...299).contains(httpThumbResponse.statusCode) {
                thumbnailUrl = "\(Secrets.supabaseUrl)/storage/v1/object/public/user-videos/\(thumbFilename)"
            }
        }
        
        uploadProgress = 0.9
        
        // Save metadata to database and get the remote ID
        let deviceUUID = await getOrCreateDeviceUUID()
        let remoteId = try await saveVideoMetadata(
            localVideo: localVideo,
            deviceUUID: deviceUUID,
            videoUrl: publicUrl,
            thumbnailUrl: thumbnailUrl
        )
        
        // Update local record
        if let index = localVideos.firstIndex(where: { $0.id == localVideo.id }) {
            localVideos[index].isUploaded = true
            localVideos[index].remoteVideoUrl = publicUrl
            localVideos[index].remoteThumbnailUrl = thumbnailUrl
            localVideos[index].remoteId = remoteId
            localVideos[index].uploadedAt = Date()
            saveLocalVideos()
        }
        
        uploadProgress = 1.0
        
        print("✅ UserVideoService: Uploaded video '\(localVideo.name)'")
    }
    
    /// Ensure a video is uploaded to Supabase and return its public URL.
    /// If already uploaded, returns the existing remote URL immediately.
    /// This is the primary method to call before generation to guarantee a public URL.
    func ensureUploaded(_ localVideo: LocalUserVideo) async throws -> String {
        // Already uploaded — return the remote URL
        if let remoteUrl = localVideo.remoteVideoUrl {
            print("✅ UserVideoService: Video '\(localVideo.name)' already uploaded")
            return remoteUrl
        }
        
        // Upload now
        try await uploadVideo(localVideo)
        
        // After upload, fetch the updated record
        guard let updated = localVideos.first(where: { $0.id == localVideo.id }),
              let remoteUrl = updated.remoteVideoUrl else {
            throw UserVideoServiceError.uploadFailed
        }
        
        return remoteUrl
    }
    
    /// Check if a URL is a local file path (not a remote HTTP(S) URL)
    static func isLocalFileURL(_ urlString: String) -> Bool {
        return urlString.hasPrefix("file://") || urlString.hasPrefix("/")
    }
    
    /// Find a local video by its effective URL (local path or remote URL)
    func findVideo(byEffectiveUrl urlString: String) -> LocalUserVideo? {
        return localVideos.first { video in
            video.effectiveVideoUrl?.absoluteString == urlString ||
            video.localVideoPath == urlString
        }
    }
    
    /// Delete a local video and sync deletion with backend
    func deleteVideo(_ video: LocalUserVideo) {
        // Remove local files
        try? fileManager.removeItem(atPath: video.localVideoPath)
        if let thumbnailPath = video.localThumbnailPath {
            try? fileManager.removeItem(atPath: thumbnailPath)
        }
        
        // Remove from local list
        localVideos.removeAll { $0.id == video.id }
        saveLocalVideos()
        
        // Sync deletion with backend (async, fire-and-forget)
        if video.isUploaded {
            let videoId = video.id
            let deviceId = self.deviceId
            Task {
                await self.deleteVideoFromBackend(video: video, deviceId: deviceId)
                await self.deleteVideoFromStorage(videoId: videoId, deviceId: deviceId)
            }
        }
        
        print("✅ UserVideoService: Deleted video '\(video.name)'")
    }
    
    // MARK: - Backend Deletion Helpers
    
    /// Mark video as inactive on the backend (soft delete)
    private func deleteVideoFromBackend(video: LocalUserVideo, deviceId: String) async {
        guard let remoteId = video.remoteId else {
            // Try to find by video URL instead
            guard let remoteUrl = video.remoteVideoUrl else { return }
            await deactivateVideoByUrl(remoteUrl)
            return
        }
        
        do {
            let url = URL(string: "\(Secrets.supabaseUrl)/rest/v1/user_videos?id=eq.\(remoteId.uuidString)")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = ["is_active": false]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                print("✅ UserVideoService: Marked video as inactive on backend (id: \(remoteId))")
            }
        } catch {
            print("⚠️ UserVideoService: Failed to mark video as inactive on backend - \(error)")
        }
    }
    
    /// Deactivate a video by its URL (fallback when remoteId is not available)
    private func deactivateVideoByUrl(_ videoUrl: String) async {
        do {
            guard let encodedUrl = videoUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
            let url = URL(string: "\(Secrets.supabaseUrl)/rest/v1/user_videos?video_url=eq.\(encodedUrl)")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = ["is_active": false]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                print("✅ UserVideoService: Marked video as inactive on backend (by URL)")
            }
        } catch {
            print("⚠️ UserVideoService: Failed to deactivate video by URL - \(error)")
        }
    }
    
    /// Delete the actual files from Supabase Storage
    private func deleteVideoFromStorage(videoId: UUID, deviceId: String) async {
        // Delete video file
        let videoPath = "\(deviceId)/\(videoId.uuidString).mp4"
        await deleteStorageObject(path: videoPath)
        
        // Delete thumbnail file
        let thumbPath = "\(deviceId)/\(videoId.uuidString)_thumb.jpg"
        await deleteStorageObject(path: thumbPath)
    }
    
    /// Delete a single object from the user-videos storage bucket
    private func deleteStorageObject(path: String) async {
        do {
            let url = URL(string: "\(Secrets.supabaseUrl)/storage/v1/object/user-videos/\(path)")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                print("✅ UserVideoService: Deleted storage object '\(path)'")
            }
        } catch {
            print("⚠️ UserVideoService: Failed to delete storage object '\(path)' - \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    private func loadLocalVideos() {
        guard let data = UserDefaults.standard.data(forKey: Self.localStorageKey) else {
            localVideos = []
            return
        }
        
        do {
            let decoded = try JSONDecoder().decode([LocalUserVideo].self, from: data)
            
            // Prune entries whose local file is gone and have no remote fallback
            let accessible = decoded.filter { video in
                let localExists = fileManager.fileExists(atPath: video.localVideoPath)
                let hasRemote = video.remoteVideoUrl != nil
                if !localExists && !hasRemote {
                    print("⚠️ UserVideoService: Pruning inaccessible video '\(video.name)' — local file missing, no remote URL")
                }
                return localExists || hasRemote
            }
            
            localVideos = accessible
            
            // Persist the cleaned list if any were pruned
            if accessible.count < decoded.count {
                print("✅ UserVideoService: Pruned \(decoded.count - accessible.count) inaccessible video(s)")
                saveLocalVideos()
            }
            
            print("✅ UserVideoService: Loaded \(localVideos.count) local videos")
        } catch {
            print("❌ UserVideoService: Failed to load local videos - \(error)")
            localVideos = []
        }
    }
    
    private func saveLocalVideos() {
        do {
            let data = try JSONEncoder().encode(localVideos)
            UserDefaults.standard.set(data, forKey: Self.localStorageKey)
        } catch {
            print("❌ UserVideoService: Failed to save local videos - \(error)")
        }
    }
    
    private func fetchRemoteVideos() async {
        guard let deviceUUID = await getDeviceUUIDIfExists() else {
            remoteVideos = []
            return
        }
        
        do {
            let url = URL(string: "\(Secrets.supabaseUrl)/rest/v1/user_videos?device_id=eq.\(deviceUUID)&is_active=eq.true&order=created_at.desc")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            remoteVideos = try decoder.decode([UserVideo].self, from: data)
            
            print("✅ UserVideoService: Fetched \(remoteVideos.count) remote videos")
            
        } catch {
            print("❌ UserVideoService: Failed to fetch remote videos - \(error)")
        }
    }
    
    /// Crop video to 9:16 aspect ratio using center crop.
    /// Overwrites the file at the given URL with the cropped version.
    /// If the video is already 9:16 (within tolerance), this is a no-op.
    private func cropVideoTo9by16(at videoURL: URL) async throws {
        let asset = AVAsset(url: videoURL)
        
        // Load video track
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            print("⚠️ UserVideoService: No video track found, skipping crop")
            return
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        
        // Apply transform to get actual dimensions (handles rotation)
        let transformedSize = naturalSize.applying(transform)
        let videoWidth = abs(transformedSize.width)
        let videoHeight = abs(transformedSize.height)
        
        let targetRatio: CGFloat = 9.0 / 16.0  // 0.5625
        let currentRatio = videoWidth / videoHeight
        
        // Already 9:16 within tolerance — skip
        if abs(currentRatio - targetRatio) < 0.02 {
            print("✅ UserVideoService: Video already 9:16, no crop needed")
            return
        }
        
        // Calculate crop rect (in natural size coordinates, before transform)
        let cropRect: CGRect
        if currentRatio > targetRatio {
            // Video is too wide — crop sides
            let newWidth = videoHeight * targetRatio
            let xOffset = (videoWidth - newWidth) / 2.0
            cropRect = CGRect(x: xOffset, y: 0, width: newWidth, height: videoHeight)
        } else {
            // Video is too tall — crop top/bottom
            let newHeight = videoWidth / targetRatio
            let yOffset = (videoHeight - newHeight) / 2.0
            cropRect = CGRect(x: 0, y: yOffset, width: videoWidth, height: newHeight)
        }
        
        // Build video composition with crop
        let composition = AVMutableComposition()
        let duration = try await asset.load(.duration)
        
        // Add video track
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            print("⚠️ UserVideoService: Failed to create composition video track")
            return
        }
        
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: videoTrack,
            at: .zero
        )
        
        // Add audio track if present
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let audioTrack = audioTracks.first {
            if let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: audioTrack,
                    at: .zero
                )
            }
        }
        
        // Create video composition for the crop
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: cropRect.width, height: cropRect.height)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30 fps
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        
        // Apply the original transform, then translate to crop
        var cropTransform = transform
        cropTransform = cropTransform.concatenating(CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
        layerInstruction.setTransform(cropTransform, at: .zero)
        
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        // Export cropped video to temp file
        let tempURL = videoURL.deletingLastPathComponent()
            .appendingPathComponent("crop_temp_\(UUID().uuidString).mp4")
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            print("⚠️ UserVideoService: Failed to create export session")
            return
        }
        
        exportSession.videoComposition = videoComposition
        exportSession.outputURL = tempURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        print("🎬 UserVideoService: Cropping video from \(Int(videoWidth))x\(Int(videoHeight)) to \(Int(cropRect.width))x\(Int(cropRect.height)) (9:16)")
        
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            let errorMsg = exportSession.error?.localizedDescription ?? "Unknown export error"
            print("⚠️ UserVideoService: Video crop export failed: \(errorMsg)")
            // Don't throw — use the original uncropped video as fallback
            try? fileManager.removeItem(at: tempURL)
            return
        }
        
        // Replace original with cropped version
        try fileManager.removeItem(at: videoURL)
        try fileManager.moveItem(at: tempURL, to: videoURL)
        
        print("✅ UserVideoService: Video cropped to 9:16 successfully")
    }
    
    private func generateThumbnail(for videoURL: URL, videoId: UUID) async -> String? {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 600)
        
        do {
            let cgImage = try await generator.image(at: .zero).image
            let uiImage = UIImage(cgImage: cgImage)
            
            guard let jpegData = uiImage.jpegData(compressionQuality: 0.7) else {
                return nil
            }
            
            let thumbnailURL = thumbnailsDirectoryURL.appendingPathComponent("\(videoId.uuidString).jpg")
            try jpegData.write(to: thumbnailURL)
            
            return thumbnailURL.path
        } catch {
            print("❌ UserVideoService: Failed to generate thumbnail - \(error)")
            return nil
        }
    }
    
    private func getVideoDuration(url: URL) async -> Int? {
        let asset = AVAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return Int(CMTimeGetSeconds(duration))
        } catch {
            return nil
        }
    }
    
    private func getOrCreateDeviceUUID() async -> UUID {
        // Check if device already registered
        if let existing = await getDeviceUUIDIfExists() {
            return existing
        }
        
        // Register new device
        do {
            let url = URL(string: "\(Secrets.supabaseUrl)/rest/v1/devices")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
            
            let body = ["device_id": deviceId]
            request.httpBody = try JSONEncoder().encode(body)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            struct DeviceResponse: Codable {
                let id: UUID
            }
            
            let response = try JSONDecoder().decode([DeviceResponse].self, from: data)
            return response.first?.id ?? UUID()
            
        } catch {
            print("❌ UserVideoService: Failed to create device - \(error)")
            return UUID()
        }
    }
    
    private func getDeviceUUIDIfExists() async -> UUID? {
        do {
            let url = URL(string: "\(Secrets.supabaseUrl)/rest/v1/devices?device_id=eq.\(deviceId)&select=id")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            struct DeviceResponse: Codable {
                let id: UUID
            }
            
            let response = try JSONDecoder().decode([DeviceResponse].self, from: data)
            return response.first?.id
            
        } catch {
            return nil
        }
    }
    
    @discardableResult
    private func saveVideoMetadata(
        localVideo: LocalUserVideo,
        deviceUUID: UUID,
        videoUrl: String,
        thumbnailUrl: String?
    ) async throws -> UUID? {
        let url = URL(string: "\(Secrets.supabaseUrl)/rest/v1/user_videos")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        
        var body: [String: Any] = [
            "device_id": deviceUUID.uuidString,
            "name": localVideo.name,
            "video_url": videoUrl
        ]
        
        if let thumbnailUrl = thumbnailUrl {
            body["thumbnail_url"] = thumbnailUrl
        }
        if let duration = localVideo.durationSeconds {
            body["duration_seconds"] = duration
        }
        if let size = localVideo.fileSizeBytes {
            body["file_size_bytes"] = size
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw UserVideoServiceError.uploadFailed
        }
        
        // Parse the returned ID
        struct VideoResponse: Codable {
            let id: UUID
        }
        
        if let records = try? JSONDecoder().decode([VideoResponse].self, from: data),
           let first = records.first {
            return first.id
        }
        
        return nil
    }
}

// MARK: - Errors

enum UserVideoServiceError: Error, LocalizedError {
    case fileTooLarge(maxMB: Int)
    case uploadFailed
    case importFailed
    
    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let maxMB):
            return "Video must be under \(maxMB) MB"
        case .uploadFailed:
            return "Failed to upload video"
        case .importFailed:
            return "Failed to import video"
        }
    }
}
