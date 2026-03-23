//
//  GenerationHistoryService.swift
//  AIVideo
//
//  Local persistence for generation history
//

import Foundation

@MainActor
final class GenerationHistoryService: ObservableObject {
    // MARK: - Singleton
    static let shared = GenerationHistoryService()
    
    // MARK: - Published Properties
    @Published private(set) var generations: [LocalGeneration] = []
    
    // MARK: - Private
    private let storageKey = AppConstants.StorageKeys.generationHistory
    private let maxHistoryItems = AppConstants.History.maxGenerationHistory
    
    // MARK: - Initialization
    
    private init() {
        loadHistory()
    }
    
    // MARK: - Public Methods
    
    /// Save a new generation to history
    func saveGeneration(
        templateName: String,
        templateId: String?,
        inputImageUrl: String,
        outputVideoUrl: String?,
        isCustomTemplate: Bool = false
    ) {
        let generation = LocalGeneration(
            id: UUID().uuidString,
            templateName: templateName,
            templateId: templateId,
            inputImageUrl: inputImageUrl,
            outputVideoUrl: outputVideoUrl,
            createdAt: Date(),
            isCustomTemplate: isCustomTemplate,
            localVideoPath: nil
        )
        
        // Add to beginning of list
        generations.insert(generation, at: 0)
        
        // Trim if exceeds max, cleaning up local files for evicted entries
        if generations.count > maxHistoryItems {
            let evicted = Array(generations.suffix(from: maxHistoryItems))
            for gen in evicted {
                VideoPersistenceManager.shared.delete(generationId: gen.id)
            }
            generations = Array(generations.prefix(maxHistoryItems))
        }

        persistHistory()

        print("✅ GenerationHistoryService: Saved generation \(generation.id)")
    }
    
    /// Delete a generation from history
    func deleteGeneration(_ id: String) {
        // Delete local video file if it exists
        VideoPersistenceManager.shared.delete(generationId: id)

        generations.removeAll { $0.id == id }
        persistHistory()

        print("✅ GenerationHistoryService: Deleted generation \(id)")
    }

    /// Update the local video file path for a generation
    func updateLocalVideoPath(_ path: String, forGenerationId id: String) {
        guard let index = generations.firstIndex(where: { $0.id == id }) else { return }
        generations[index].localVideoPath = path
        persistHistory()
    }

    /// Get a generation by ID
    func generation(withId id: String) -> LocalGeneration? {
        generations.first { $0.id == id }
    }
    
    /// Get generations for a specific template
    func generations(forTemplateId templateId: String) -> [LocalGeneration] {
        generations.filter { $0.templateId == templateId }
    }
    
    /// Get recent generations (limited count)
    func recentGenerations(limit: Int = 10) -> [LocalGeneration] {
        Array(generations.prefix(limit))
    }
    
    /// Merge completed generations fetched from the server into local history.
    /// Only adds entries whose `outputVideoUrl` is not already present locally.
    /// This lets the app recover history after a reinstall or data loss.
    func mergeRemoteGenerations(_ remoteGenerations: [RemoteGeneration]) {
        let existingOutputUrls = Set(generations.compactMap { $0.outputVideoUrl })
        
        var newEntries: [LocalGeneration] = []
        for remote in remoteGenerations {
            guard let outputUrl = remote.outputVideoUrl,
                  !existingOutputUrls.contains(outputUrl) else { continue }
            
            let displayName = remote.effectName ?? templateDisplayName(from: remote.referenceVideoUrl)
            let local = LocalGeneration(
                id: UUID().uuidString,
                templateName: displayName,
                templateId: remote.effectId,
                inputImageUrl: remote.inputImageUrl ?? "",
                outputVideoUrl: outputUrl,
                createdAt: parseISO8601(remote.createdAt) ?? Date(),
                isCustomTemplate: remote.effectId == nil && remote.referenceVideoUrl == nil,
                localVideoPath: nil
            )
            newEntries.append(local)
        }
        
        guard !newEntries.isEmpty else {
            print("ℹ️ GenerationHistoryService: No new remote generations to merge")
            return
        }
        
        generations.append(contentsOf: newEntries)
        generations.sort { $0.createdAt > $1.createdAt }
        
        // Trim if exceeds max, cleaning up local files for evicted entries
        if generations.count > maxHistoryItems {
            let evicted = Array(generations.suffix(from: maxHistoryItems))
            for gen in evicted {
                VideoPersistenceManager.shared.delete(generationId: gen.id)
            }
            generations = Array(generations.prefix(maxHistoryItems))
        }

        persistHistory()
        print("✅ GenerationHistoryService: Merged \(newEntries.count) remote generations (total: \(generations.count))")
    }
    
    /// Clear all history
    func clearHistory() {
        // Delete all local video files
        for generation in generations {
            VideoPersistenceManager.shared.delete(generationId: generation.id)
        }
        generations.removeAll()
        persistHistory()

        print("✅ GenerationHistoryService: Cleared all history")
    }
    
    // MARK: - Private Methods
    
    /// Extract a human-readable name from a reference video URL.
    /// Falls back to "Video" if the URL is absent or unrecognizable.
    private func templateDisplayName(from referenceVideoUrl: String?) -> String {
        guard let urlString = referenceVideoUrl,
              let url = URL(string: urlString) else { return "Video" }
        
        let filename = url.deletingPathExtension().lastPathComponent
        // Strip leading timestamp prefix (e.g. "1770672586775_")
        let stripped = filename.replacingOccurrences(
            of: #"^\d+_"#, with: "", options: .regularExpression
        )
        // SnapTik filenames are just download IDs - not useful
        if stripped.hasPrefix("SnapTik") { return "Video" }
        
        let cleaned = stripped
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .removingPercentEncoding ?? stripped
        
        return cleaned.isEmpty ? "Video" : cleaned
    }
    
    /// Parse an ISO 8601 date string with fractional seconds + timezone.
    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        // Retry without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
    
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            print("ℹ️ GenerationHistoryService: No history found")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loadedGenerations = try decoder.decode([LocalGeneration].self, from: data)
            generations = loadedGenerations
            print("✅ GenerationHistoryService: Loaded \(generations.count) generations")
        } catch {
            print("❌ GenerationHistoryService: Failed to load history - \(error)")
        }
    }
    
    private func persistHistory() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(generations)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("❌ GenerationHistoryService: Failed to save history - \(error)")
        }
    }
}
