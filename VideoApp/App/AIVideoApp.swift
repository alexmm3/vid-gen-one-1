//
//  AIVideoApp.swift
//  AIVideo
//
//  Main app entry point
//

import SwiftUI
import AVFoundation
import FirebaseCore

@main
struct AIVideoApp: App {
    @StateObject private var appState = AppState.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Configure appearance
        configureAppearance()
        
        // Configure URLCache for better video caching
        configureURLCache()
    }
    
    /// Configure URLCache with larger capacity for video content
    private func configureURLCache() {
        // 50 MB memory, 500 MB disk (videos need more space)
        let memoryCapacity = 50 * 1024 * 1024  // 50 MB
        let diskCapacity = 500 * 1024 * 1024   // 500 MB
        
        let cache = URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            diskPath: "video_url_cache"
        )
        URLCache.shared = cache
        
        print("📦 URLCache configured: \(memoryCapacity / 1024 / 1024)MB memory, \(diskCapacity / 1024 / 1024)MB disk")
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
    }
    
    private func configureAppearance() {
        // Navigation bar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(Color.videoBackground)
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        
        // Tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(Color.videoSurface)
        
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Configure audio session to play sound even when device is in silent mode.
        // The .playback category tells iOS that audio is a core feature of this app,
        // so the hardware mute switch should not silence video playback.
        // The .moviePlayback mode optimizes for video content (AV sync).
        configureAudioSession()
        
        // Configure Firebase if GoogleService-Info.plist exists and has a valid GOOGLE_APP_ID
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let appId = dict["GOOGLE_APP_ID"] as? String,
           !appId.contains("REPLACE_WITH") {
            FirebaseApp.configure()
        } else {
            print("⚠️ GoogleService-Info.plist has placeholder values. Firebase will not be configured.")
        }
        
        // Set up analytics
        configureAnalytics()
        
        // Start subscription transaction listener (refresh happens in RootView.initialize)
        Task {
            await SubscriptionManager.shared.startTransactionUpdatesListener()
        }
        
        // Check for pending generations on app launch
        Task {
            await checkPendingGenerations()
        }
        
        return true
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Reactivate audio session after returning from background or interruption
        // (e.g. phone call ended, another app released audio focus)
        configureAudioSession()
        
        // Refresh subscription status when app becomes active
        Task {
            await SubscriptionManager.shared.refreshSubscriptionStatus()
        }
        
        // Check for any pending generations that need to be resumed
        Task {
            await checkPendingGenerations()
        }
    }
    
    @MainActor
    private func checkPendingGenerations() async {
        let manager = ActiveGenerationManager.shared
        
        guard manager.hasActiveGeneration else { return }
        
        // If polling is already active, just re-subscribe to Realtime
        // (the WebSocket disconnects when the app is backgrounded by iOS)
        if manager.isPollingActive {
            if let generationId = manager.pendingGeneration?.generationId {
                print("ℹ️ AppDelegate: Polling active, re-subscribing Realtime for \(generationId)")
                manager.subscribeToGenerationUpdates(generationId: generationId)
            }
            return
        }
        
        print("🔄 AppDelegate: Found pending generation, checking status...")
        
        // First, do a quick status check (with fetch_id to get fresh status from API)
        if let result = await manager.checkAndResumePendingGeneration() {
            switch result {
            case .completed(let outputUrl):
                print("✅ AppDelegate: Pending generation completed: \(outputUrl)")
                // The ActiveGenerationManager already saved to history and posted notification
                // Toast will show automatically via ToastManager
                
            case .failed(let error):
                print("❌ AppDelegate: Pending generation failed: \(error)")
                
            case .stillProcessing(let pollCount):
                print("🔄 AppDelegate: Generation still processing (poll #\(pollCount)), starting background polling...")
                // Start background polling + Realtime subscription
                manager.startBackgroundPolling()
                
            case .expired:
                print("⚠️ AppDelegate: Pending generation expired")
            }
        }
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        Analytics.track(.appOpened)
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        Analytics.track(.appBackgrounded)
    }
    
    /// Configures AVAudioSession so video playback is audible even when the device
    /// silent/mute switch is on. Safe to call multiple times (e.g. on foreground return).
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            print("⚠️ Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
    private func configureAnalytics() {
        let deviceId = DeviceManager.shared.deviceId
        Analytics.setUserId(deviceId)
        Analytics.setUserProperty("ios", for: .platform)
        Analytics.setUserProperty(Bundle.main.appVersion, for: .appVersion)
        Analytics.setUserProperty(deviceId, for: .deviceId)
        
        // Set subscription status
        let isPremium = SubscriptionManager.shared.hasActiveSubscription
        Analytics.updateSubscriptionStatus(
            isPremium: isPremium,
            plan: SubscriptionManager.shared.currentProductId
        )
    }
}

// MARK: - Root View

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var isInitialized = false
    
    var body: some View {
        ZStack {
            Color.videoBackground.ignoresSafeArea()
            
            if isInitialized {
                if appState.hasCompletedOnboarding {
                    MainTabView()
                        .fullScreenCover(isPresented: $appState.showOnboardingPaywall) {
                            PaywallView(source: .onboarding) {
                                // Purchase complete
                                appState.setPremiumStatus(true)
                            }
                        }
                } else {
                    OnboardingView()
                }
            } else {
                // Splash / Loading screen
                splashView
            }
        }
        .task {
            await initialize()
        }
    }
    
    private var splashView: some View {
        VStack(spacing: VideoSpacing.lg) {
            Image(systemName: "wand.and.sparkles")
                .font(.system(size: 60))
                .foregroundColor(.videoAccent)
            
            Text(BrandConfig.appName)
                .font(.videoDisplayLarge)
                .foregroundColor(.videoTextPrimary)
        }
    }
    
    private func initialize() async {
        // Brief delay for splash
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Refresh subscription status — this updates AppState directly
        // via validateWithBackend() (sets premium + generation limits)
        await SubscriptionManager.shared.refreshSubscriptionStatus()
        
        // Show UI immediately - don't block on template loading
        withAnimation {
            isInitialized = true
        }
        
        // Pre-fetch templates in background (non-blocking)
        // CategoryService has caching, so this will speed up CreateView's first load.
        // Also prefetch lightweight thumbnails (small JPEGs) so they are cached
        // before the user reaches the Create screen. We intentionally do NOT
        // prefetch full video files here — that would compete with AVPlayer
        // streaming and cause memory pressure / buffer purges.
        Task.detached(priority: .background) {
            await CategoryService.shared.fetchAll()
            
            // Prefetch only thumbnails (small JPEGs, ~5-20 KB each)
            let allTemplates = await CategoryService.shared.templatesByCategory.values.flatMap { $0 }
            let thumbnailURLs = allTemplates.compactMap { $0.fullThumbnailUrl }
            
            if !thumbnailURLs.isEmpty {
                ImageCacheManager.shared.prefetch(urls: thumbnailURLs)
                print("🖼️ Prefetching \(thumbnailURLs.count) template thumbnails")
            }
        }
    }
}
