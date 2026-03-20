//
//  LoopingRemoteVideoPlayer.swift
//  AIVideo
//
//  Looping video player for remote URLs (template videos)
//  Uses VideoCacheManager for efficient caching
//

import SwiftUI
import AVFoundation
import AVKit

// MARK: - Video Player Coordinator

/// Coordinates video player initialization to prevent UI freezes.
///
/// When the feed first loads, many `LoopingRemoteVideoPlayer` views appear
/// simultaneously. Without coordination, each one creates an AVPlayer on the
/// main thread in the same layout pass, saturating the AVFoundation media
/// pipeline and freezing the UI until all players have buffered.
///
/// The coordinator solves this by:
/// 1. **Deferring** all player creation off the current SwiftUI layout pass
///    (via `DispatchQueue.main.async`), so the UI renders and is scrollable immediately.
/// 2. **Staggering** creation in small batches with short delays between them,
///    so AVFoundation's shared resources aren't overwhelmed.
/// 3. Supporting **cancellation** for views that scroll off-screen before their
///    setup fires.
final class VideoPlayerCoordinator {
    static let shared = VideoPlayerCoordinator()

    /// Pending setup requests
    private var pendingSetups: [(id: UUID, setup: () -> Void)] = []
    /// Cancelled setup IDs (view torn down before setup fired)
    private var cancelledIDs = Set<UUID>()
    /// Whether a drain pass is already scheduled
    private var drainScheduled = false
    /// Number of players to initialize per batch
    private let batchSize = 2
    /// Delay between batches (seconds)
    private let batchInterval: TimeInterval = 0.08

    private init() {}

    /// Queue a player setup. The closure runs on the main thread after the
    /// current layout pass completes, staggered with other pending setups.
    /// - Parameters:
    ///   - id: Unique token for this request (used for cancellation)
    ///   - setup: Closure that creates the AVPlayer (runs on main thread)
    func scheduleSetup(id: UUID, setup: @escaping () -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.scheduleSetup(id: id, setup: setup)
            }
            return
        }
        cancelledIDs.remove(id)
        pendingSetups.append((id: id, setup: setup))
        scheduleDrainIfNeeded()
    }

    /// Cancel a pending setup (e.g., when the player view is torn down
    /// before its scheduled setup has fired).
    func cancelSetup(id: UUID) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.cancelSetup(id: id)
            }
            return
        }
        pendingSetups.removeAll { $0.id == id }
        cancelledIDs.insert(id)
        // Prevent unbounded growth
        if cancelledIDs.count > 200 { cancelledIDs.removeAll() }
    }

    private func scheduleDrainIfNeeded() {
        guard !drainScheduled else { return }
        drainScheduled = true
        // Defer to next run loop iteration — this unblocks the current
        // SwiftUI layout pass so the UI renders and is scrollable immediately.
        DispatchQueue.main.async { [weak self] in
            self?.drainBatch()
        }
    }

    private func drainBatch() {
        var count = 0
        while count < batchSize, !pendingSetups.isEmpty {
            let (id, setup) = pendingSetups.removeFirst()
            guard !cancelledIDs.contains(id) else { continue }
            setup()
            count += 1
        }

        if pendingSetups.isEmpty {
            drainScheduled = false
        } else {
            // Stagger next batch to avoid AVFoundation pipeline contention
            DispatchQueue.main.asyncAfter(deadline: .now() + batchInterval) { [weak self] in
                self?.drainBatch()
            }
        }
    }
}

// MARK: - SwiftUI View

struct LoopingRemoteVideoPlayer: View {
    let url: URL?
    var isMuted: Bool = true
    var isPlaying: Bool = true
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    /// Optional time to seek to after player setup (for seamless fullscreen transitions)
    var startTime: CMTime?
    var onReadyForDisplayChanged: ((Bool) -> Void)?

    var body: some View {
        LoopingRemoteVideoPlayerContent(
            url: url,
            isMuted: isMuted,
            isPlaying: isPlaying,
            videoGravity: videoGravity,
            startTime: startTime,
            onReadyForDisplayChanged: onReadyForDisplayChanged
        )
            .id(url?.absoluteString ?? "nil_url")
    }
}

private struct LoopingRemoteVideoPlayerContent: View {
    let url: URL?
    var isMuted: Bool = true
    var isPlaying: Bool = true
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    var startTime: CMTime?
    var onReadyForDisplayChanged: ((Bool) -> Void)?

    /// Tracks whether this view is currently on-screen.
    /// When false the AVPlayer is torn down to free resources and the view falls
    /// back to a lightweight solid placeholder instead of a separate thumbnail layer.
    @State private var isVisible = false

    var body: some View {
        Group {
            if let url = url {
                if isVisible {
                    RemoteVideoLooperView(
                        url: url,
                        isMuted: isMuted,
                        isPlaying: isPlaying,
                        videoGravity: videoGravity,
                        startTime: startTime,
                        onReadyForDisplayChanged: onReadyForDisplayChanged
                    )
                } else {
                    Color.videoSurface
                }
            } else {
                Rectangle()
                    .fill(Color.videoSurface)
            }
        }
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
    }
}

// MARK: - UIKit Representable

private struct RemoteVideoLooperView: UIViewRepresentable {
    let url: URL
    var isMuted: Bool
    var isPlaying: Bool = true
    var videoGravity: AVLayerVideoGravity
    var startTime: CMTime?
    var onReadyForDisplayChanged: ((Bool) -> Void)?

    func makeUIView(context: Context) -> RemoteLoopingVideoUIView {
        let view = RemoteLoopingVideoUIView()
        view.onReadyForDisplayChanged = onReadyForDisplayChanged
        view.configure(with: url, isMuted: isMuted, videoGravity: videoGravity, startTime: startTime)
        return view
    }

    func updateUIView(_ uiView: RemoteLoopingVideoUIView, context: Context) {
        uiView.onReadyForDisplayChanged = onReadyForDisplayChanged
        uiView.configure(with: url, isMuted: isMuted, videoGravity: videoGravity, startTime: startTime)
        if isPlaying {
            uiView.resumePlayback()
        } else {
            uiView.pausePlayback()
        }
    }
}

// MARK: - UIView for Remote Looping Video

private class RemoteLoopingVideoUIView: UIView {
    private var player: AVQueuePlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerLooper: AVPlayerLooper?
    private var playerItem: AVPlayerItem?
    private var currentURL: URL?
    private var readyObservation: NSKeyValueObservation?
    private var hasReportedReadyForDisplay = false

    /// Tracks whether this view should be actively playing.
    /// True once configure() is called; false after cleanup().
    private var shouldBePlaying = false

    /// Unique token for the current coordinator setup request.
    /// Used to cancel stale requests and ignore callbacks from outdated schedules.
    private var setupID = UUID()

    var onReadyForDisplayChanged: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Use a stable solid background while AVPlayer is buffering so the UI
        // no longer depends on a separate thumbnail underlay.
        backgroundColor = .black
        clipsToBounds = true
        addLifecycleObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle Observers
    // AVPlayer gets paused by the system during background transitions,
    // fullScreenCover presentations, and audio session interruptions.
    // These observers ensure playback resumes automatically.

    private func addLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func appWillEnterForeground() {
        // Resume playback if this view is visible and should be playing
        guard shouldBePlaying, window != nil else { return }
        player?.play()
    }

    @objc private func appDidEnterBackground() {
        // Pause to free resources while backgrounded
        player?.pause()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, shouldBePlaying {
            // View (re-)appeared in a window — resume playback.
            // This handles recovery after tab switches and fullScreenCover dismissals.
            // We intentionally do NOT pause when window becomes nil, because that
            // happens during tab switches and would force the player to re-buffer,
            // causing a visible reload flash when the user returns.
            player?.play()
        }
    }

    // MARK: - Configuration

    func configure(with url: URL, isMuted: Bool, videoGravity: AVLayerVideoGravity = .resizeAspectFill, startTime: CMTime? = nil) {
        // Skip reconfiguration if same URL
        guard currentURL != url else {
            player?.isMuted = isMuted
            if let startTime, startTime.seconds > 0 {
                let currentSeconds = player?.currentTime().seconds ?? 0
                if abs(currentSeconds - startTime.seconds) > 0.25 {
                    player?.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
            // Ensure player is still running (may have been paused by system)
            if shouldBePlaying, window != nil {
                player?.play()
            }
            return
        }

        // Clean up existing player and cancel any pending setup
        cleanup()
        currentURL = url
        shouldBePlaying = true
        reportReadyForDisplay(false)

        // Schedule player creation through the coordinator.
        // This defers AVPlayer setup off the current SwiftUI layout pass
        // and staggers creation across multiple run loop iterations,
        // preventing the UI freeze caused by many simultaneous AVPlayer inits.
        let id = UUID()
        setupID = id
        let capturedMuted = isMuted
        let capturedGravity = videoGravity
        let capturedStartTime = startTime

        VideoPlayerCoordinator.shared.scheduleSetup(id: id) { [weak self] in
            guard let self = self,
                  self.setupID == id,
                  self.shouldBePlaying else { return }
            self.createPlayer(url: url, isMuted: capturedMuted, videoGravity: capturedGravity, startTime: capturedStartTime)
        }
    }

    // MARK: - Player Creation (called by coordinator)

    private func createPlayer(url: URL, isMuted: Bool, videoGravity: AVLayerVideoGravity, startTime: CMTime?) {
        // Get cached asset from VideoCacheManager
        let asset = VideoCacheManager.shared.asset(for: url)
        playerItem = AVPlayerItem(asset: asset)

        // Create queue player for looping
        player = AVQueuePlayer(playerItem: playerItem)
        player?.isMuted = isMuted
        player?.automaticallyWaitsToMinimizeStalling = true

        // Create looper
        if let player = player, let playerItem = playerItem {
            playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
        }

        // Create player layer
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.videoGravity = videoGravity
        playerLayer?.frame = bounds

        if let playerLayer = playerLayer {
            layer.addSublayer(playerLayer)
        }
        observeReadyForDisplay()

        // Seek to start time if provided (for seamless fullscreen transitions)
        if let startTime = startTime, startTime.seconds > 0 {
            player?.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        // Start playing
        player?.play()
    }

    func setMuted(_ muted: Bool) {
        player?.isMuted = muted
    }

    func pausePlayback() {
        player?.pause()
    }

    func resumePlayback() {
        guard shouldBePlaying, window != nil else { return }
        player?.play()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    private func observeReadyForDisplay() {
        readyObservation = playerLayer?.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            self?.reportReadyForDisplay(layer.isReadyForDisplay)
        }
    }

    private func reportReadyForDisplay(_ isReady: Bool) {
        guard hasReportedReadyForDisplay != isReady else { return }
        hasReportedReadyForDisplay = isReady
        let callback = onReadyForDisplayChanged
        DispatchQueue.main.async {
            callback?(isReady)
        }
    }

    private func cleanup() {
        if !Thread.isMainThread {
            let pendingSetupID = setupID
            let readyCallback = onReadyForDisplayChanged
            let player = player
            let playerLooper = playerLooper
            let playerLayer = playerLayer

            shouldBePlaying = false
            readyObservation = nil
            hasReportedReadyForDisplay = false
            self.player = nil
            self.playerLooper = nil
            self.playerLayer = nil
            playerItem = nil
            currentURL = nil

            DispatchQueue.main.async {
                VideoPlayerCoordinator.shared.cancelSetup(id: pendingSetupID)
                readyCallback?(false)
                player?.pause()
                playerLooper?.disableLooping()
                playerLayer?.removeFromSuperlayer()
            }
            return
        }

        // Cancel any pending coordinator setup for this view
        VideoPlayerCoordinator.shared.cancelSetup(id: setupID)
        shouldBePlaying = false
        readyObservation = nil
        reportReadyForDisplay(false)
        player?.pause()
        playerLooper?.disableLooping()
        playerLayer?.removeFromSuperlayer()
        player = nil
        playerLooper = nil
        playerLayer = nil
        playerItem = nil
        currentURL = nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        cleanup()
    }
}

// MARK: - Preview

#Preview {
    LoopingRemoteVideoPlayer(
        url: URL(string: "https://your-project.supabase.co/storage/v1/object/public/reference-videos/templates/sample.mp4")
    )
    .frame(width: 200, height: 300)
    .cornerRadius(12)
}
