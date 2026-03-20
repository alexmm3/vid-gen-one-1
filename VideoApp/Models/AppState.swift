//
//  AppState.swift
//  AIVideo
//
//  Global app state management
//  Adapted from GLAM reference
//

import SwiftUI
import Combine

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    // MARK: - Singleton
    static let shared = AppState()
    
    // MARK: - Published Properties
    
    /// Whether user has completed onboarding
    @AppStorage(AppConstants.StorageKeys.hasCompletedOnboarding)
    var hasCompletedOnboarding: Bool = false
    
    /// Whether user has seen the paywall (for resume functionality)
    @AppStorage(AppConstants.StorageKeys.hasReachedPaywall)
    var hasReachedPaywall: Bool = false
    
    /// Whether user has accepted AI data processing consent
    @AppStorage(AppConstants.StorageKeys.hasAcceptedAIDataConsent)
    var hasAcceptedAIDataConsent: Bool = false
    
    /// Whether the onboarding paywall should be presented (non-persisted, session only)
    @Published var showOnboardingPaywall: Bool = false
    
    /// Currently selected tab
    @Published var currentTab: VideoTab = .create
    
    /// Subscription status (from backend validation)
    @Published private var _isPremiumUser: Bool = false
    
    // DEBUG: Remove before release
    #if DEBUG
    @AppStorage("debug_simulate_premium") var debugSimulatePremium: Bool = false
    
    var isPremiumUser: Bool {
        debugSimulatePremium || _isPremiumUser
    }
    #else
    var isPremiumUser: Bool {
        _isPremiumUser
    }
    #endif
    
    /// Remaining generations in current period (from backend)
    @Published var generationsRemaining: Int? = nil

    /// Generations used in current period (from backend)
    @Published var generationsUsed: Int? = nil

    /// Total generation limit for current billing period (from backend)
    @Published var generationLimit: Int? = nil

    /// Subscription expiration date (from backend)
    @Published var subscriptionExpiresAt: Date? = nil
    
    /// App-wide loading state
    @Published var isLoading: Bool = false
    
    /// App-wide error state
    @Published var currentError: AppError? = nil
    
    /// Active generation (for tracking in-progress generations)
    @Published var activeGenerationId: String? = nil
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        // Immediately restore premium status from persisted subscription state
        // so the UI is correct before the async StoreKit refresh completes
        self._isPremiumUser = SubscriptionManager.shared.hasActiveSubscription
        setupSubscriptionListener()
    }
    
    // MARK: - Setup
    
    private func setupSubscriptionListener() {
        NotificationCenter.default.publisher(for: .subscriptionStatusChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let isPremium = notification.userInfo?["isPremium"] as? Bool {
                    self?._isPremiumUser = isPremium
                }
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Premium Management
    
    /// Update premium status
    func setPremiumStatus(_ isPremium: Bool, generationsRemaining: Int? = nil, generationsUsed: Int? = nil, generationLimit: Int? = nil, expiresAt: String? = nil) {
        self._isPremiumUser = isPremium
        self.generationsRemaining = generationsRemaining
        self.generationsUsed = generationsUsed
        self.generationLimit = generationLimit

        if isPremium, let expiresAt = expiresAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.subscriptionExpiresAt = formatter.date(from: expiresAt) ?? ISO8601DateFormatter().date(from: expiresAt)
        } else if !isPremium {
            self.subscriptionExpiresAt = nil
        }
    }
    
    /// Check if user can generate (has subscription)
    var canGenerate: Bool {
        isPremiumUser
    }
    
    // MARK: - Navigation
    
    /// Navigate to a specific tab
    func navigateToTab(_ tab: VideoTab) {
        withAnimation(.easeInOut(duration: AppConstants.Animation.standard)) {
            currentTab = tab
        }
    }
    
    // MARK: - Error Handling
    
    /// Show an error to the user
    func showError(_ error: AppError) {
        currentError = error
    }
    
    /// Clear current error
    func clearError() {
        currentError = nil
    }
    
    // MARK: - Onboarding
    
    /// Complete onboarding flow
    func completeOnboarding() {
        withAnimation {
            hasCompletedOnboarding = true
        }
    }
    
    /// Reset onboarding (for testing)
    func resetOnboarding() {
        hasCompletedOnboarding = false
        hasReachedPaywall = false
    }
}

// MARK: - Video Tab

enum VideoTab: Int, CaseIterable, Identifiable {
    case create = 0
    case myVideos = 1
    case profile = 2
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .create: return "Create"
        case .myVideos: return "My Videos"
        case .profile: return "Profile"
        }
    }
    
    var icon: String {
        switch self {
        case .create: return "wand.and.sparkles"
        case .myVideos: return "film.stack"
        case .profile: return "person"
        }
    }
    
    var selectedIcon: String {
        switch self {
        case .create: return "wand.and.sparkles"
        case .myVideos: return "film.stack.fill"
        case .profile: return "person.fill"
        }
    }
}

// MARK: - App Error

enum AppError: Error, Identifiable {
    case network(String)
    case api(String)
    case noSubscription
    case limitReached(limit: Int, remaining: Int)
    case imageProcessing(String)
    case storage(String)
    case unknown(String)
    
    var id: String {
        switch self {
        case .network(let msg): return "network_\(msg)"
        case .api(let msg): return "api_\(msg)"
        case .noSubscription: return "no_subscription"
        case .limitReached(let limit, _): return "limit_\(limit)"
        case .imageProcessing(let msg): return "image_\(msg)"
        case .storage(let msg): return "storage_\(msg)"
        case .unknown(let msg): return "unknown_\(msg)"
        }
    }
    
    var title: String {
        switch self {
        case .network: return "Connection Error"
        case .api: return "Service Error"
        case .noSubscription: return "Subscription Required"
        case .limitReached: return "Limit Reached"
        case .imageProcessing: return "Image Error"
        case .storage: return "Storage Error"
        case .unknown: return "Something Went Wrong"
        }
    }
    
    var message: String {
        switch self {
        case .network(let msg): return msg
        case .api(let msg): return msg
        case .noSubscription: return "Subscribe to generate videos"
        case .limitReached(let limit, let remaining):
            return "You've used \(limit - remaining) of \(limit) generations. Upgrade for more."
        case .imageProcessing(let msg): return msg
        case .storage(let msg): return msg
        case .unknown(let msg): return msg
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .network, .api: return true
        default: return false
        }
    }
}
