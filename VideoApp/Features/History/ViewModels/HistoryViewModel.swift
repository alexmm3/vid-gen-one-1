//
//  HistoryViewModel.swift
//  AIVideo
//
//  ViewModel for My Videos tab - shows completed and pending generations
//

import Foundation
import Combine

@MainActor
final class HistoryViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var generations: [LocalGeneration] = []
    @Published var pendingGeneration: PendingGeneration?
    @Published var isDeleting = false
    @Published var isCheckingPending = false
    @Published var isSyncingHistory = false
    
    // MARK: - Private
    private let historyService = GenerationHistoryService.shared
    private let activeGenerationManager = ActiveGenerationManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        // Observe history service updates
        historyService.$generations
            .assign(to: &$generations)
        
        // Observe pending generation - use sink to ensure UI updates
        activeGenerationManager.$pendingGeneration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pending in
                self?.pendingGeneration = pending
                print("📱 HistoryViewModel: pendingGeneration updated - \(pending?.generationId ?? "nil")")
            }
            .store(in: &cancellables)
        
        activeGenerationManager.$isCheckingPending
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isChecking in
                self?.isCheckingPending = isChecking
            }
            .store(in: &cancellables)
        
        // Listen for generation started notification to refresh
        NotificationCenter.default.publisher(for: .generationStarted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                print("📱 HistoryViewModel: Received generationStarted notification")
                self?.pendingGeneration = self?.activeGenerationManager.pendingGeneration
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // Listen for generation completed notifications to refresh
        NotificationCenter.default.publisher(for: .generationCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                print("📱 HistoryViewModel: Received generationCompleted notification")
                self?.pendingGeneration = nil
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // Listen for generation failed notifications to refresh
        NotificationCenter.default.publisher(for: .generationFailed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                print("📱 HistoryViewModel: Received generationFailed notification")
                self?.pendingGeneration = nil
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Force sync pending generation from ActiveGenerationManager
    func syncPendingGeneration() {
        let managerPending = activeGenerationManager.pendingGeneration
        if pendingGeneration != managerPending {
            pendingGeneration = managerPending
            print("📱 HistoryViewModel: Synced pendingGeneration - \(managerPending?.generationId ?? "nil")")
        }
    }
    
    /// Check and update pending generation status
    func refreshPendingStatus() async {
        // First sync the local state
        syncPendingGeneration()
        guard pendingGeneration != nil else { return }
        _ = await activeGenerationManager.checkAndResumePendingGeneration()
    }
    
    /// Sync local history with the server (source of truth).
    /// Fetches completed generations for this device and merges any
    /// that are missing from local UserDefaults storage.
    func syncHistory() async {
        guard !isSyncingHistory else { return }
        isSyncingHistory = true
        defer { isSyncingHistory = false }
        
        do {
            let remoteGenerations = try await GenerationService.shared.fetchDeviceHistory()
            historyService.mergeRemoteGenerations(remoteGenerations)
            print("📱 HistoryViewModel: Server sync completed (\(remoteGenerations.count) remote entries)")
        } catch {
            // Non-fatal: the local data still shows; we just couldn't sync.
            print("⚠️ HistoryViewModel: History sync failed - \(error.localizedDescription)")
        }
    }
    
    /// Delete a generation
    func deleteGeneration(_ generation: LocalGeneration) {
        isDeleting = true
        historyService.deleteGeneration(generation.id)
        isDeleting = false
        
        Analytics.track(.historyItemDeleted(generationId: generation.id))
    }
    
    /// Track viewing history
    func trackHistoryViewed() {
        Analytics.track(.historyViewed)
    }
    
    /// Track viewing a specific item
    func trackItemViewed(_ generation: LocalGeneration) {
        Analytics.track(.historyItemViewed(generationId: generation.id))
    }
    
    /// Whether there's an active pending generation
    var hasPendingGeneration: Bool {
        pendingGeneration != nil
    }
}
