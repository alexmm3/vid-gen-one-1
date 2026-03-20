//
//  LoopingVideoPlayer.swift
//  AIVideo
//
//  A SwiftUI view that plays a video in a continuous loop
//  For bundled videos (onboarding, etc.)
//  Adapted from GLAM reference
//

import SwiftUI
import AVFoundation
import AVKit

// MARK: - Looping Video Player View (Bundled Videos)

struct LoopingVideoPlayer: UIViewRepresentable {
    let videoName: String
    let videoExtension: String
    let isPlaying: Bool
    
    init(videoName: String, videoExtension: String = "mp4", isPlaying: Bool = true) {
        self.videoName = videoName
        self.videoExtension = videoExtension
        self.isPlaying = isPlaying
    }
    
    func makeUIView(context: Context) -> LoopingVideoUIView {
        let view = LoopingVideoUIView()
        view.configure(videoName: videoName, videoExtension: videoExtension)
        return view
    }
    
    func updateUIView(_ uiView: LoopingVideoUIView, context: Context) {
        if isPlaying {
            uiView.play()
        } else {
            uiView.pause()
        }
    }
}

// MARK: - UIKit Video View

class LoopingVideoUIView: UIView {
    private var playerLayer: AVPlayerLayer?
    private var playerLooper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?
    private var playerItem: AVPlayerItem?
    private var isConfigured = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(videoName: String, videoExtension: String) {
        guard !isConfigured else { return }
        isConfigured = true
        
        guard let videoURL = Bundle.main.url(forResource: videoName, withExtension: videoExtension) else {
            print("⚠️ Video not found: \(videoName).\(videoExtension)")
            return
        }
        
        let item = AVPlayerItem(url: videoURL)
        playerItem = item
        
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true
        
        playerLooper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer = player
        
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer.addSublayer(layer)
        playerLayer = layer
        
        player.pause()
    }
    
    func play() {
        guard let player = queuePlayer else { return }
        player.seek(to: .zero)
        player.play()
    }
    
    func pause() {
        queuePlayer?.pause()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
    
    deinit {
        queuePlayer?.pause()
        playerLooper?.disableLooping()
    }
}

// MARK: - Video Time Provider
/// Allows parent views to query the current playback time from a RemoteVideoPlayer.
/// Create one as @State, pass it to RemoteVideoPlayer, then call currentTime() when needed.

class VideoTimeProvider {
    fileprivate var getTime: (() -> CMTime)?
    fileprivate var getDurationFn: (() -> CMTime?)?
    
    /// Seek callback — accepts a fraction (0…1) and seeks the player
    var seek: ((Double) -> Void)?
    
    /// Duration of the current item, queried live from the player
    var duration: CMTime? {
        getDurationFn?()
    }
    
    func currentTime() -> CMTime {
        getTime?() ?? .zero
    }
}

// MARK: - Remote Video Player (Supabase URLs)

struct RemoteVideoPlayer: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool
    let isMuted: Bool
    let videoGravity: AVLayerVideoGravity
    /// Optional provider that lets the parent read the player's current playback time.
    var timeProvider: VideoTimeProvider?
    
    init(url: URL, isPlaying: Bool = true, isMuted: Bool = true, videoGravity: AVLayerVideoGravity = .resizeAspectFill, timeProvider: VideoTimeProvider? = nil) {
        self.url = url
        self.isPlaying = isPlaying
        self.isMuted = isMuted
        self.videoGravity = videoGravity
        self.timeProvider = timeProvider
    }
    
    func makeUIView(context: Context) -> RemoteVideoUIView {
        let view = RemoteVideoUIView()
        view.configure(url: url, isMuted: isMuted, videoGravity: videoGravity)
        bindTimeProvider(to: view)
        return view
    }
    
    func updateUIView(_ uiView: RemoteVideoUIView, context: Context) {
        if isPlaying {
            uiView.play()
        } else {
            uiView.pause()
        }
        uiView.setMuted(isMuted)
        bindTimeProvider(to: uiView)
    }
    
    private func bindTimeProvider(to view: RemoteVideoUIView) {
        timeProvider?.getTime = { [weak view] in
            view?.getCurrentTime() ?? .zero
        }
        timeProvider?.getDurationFn = { [weak view] in
            view?.getDuration()
        }
        timeProvider?.seek = { [weak view] fraction in
            view?.seekToFraction(fraction)
        }
    }
}

class RemoteVideoUIView: UIView {
    private var playerLayer: AVPlayerLayer?
    private var playerLooper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?
    private var isConfigured = false
    private var currentURL: URL?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(url: URL, isMuted: Bool, videoGravity: AVLayerVideoGravity = .resizeAspectFill) {
        // Skip reconfiguration if same URL
        guard !isConfigured || currentURL != url else {
            queuePlayer?.isMuted = isMuted
            return
        }
        
        // Clean up if reconfiguring with different URL
        if isConfigured {
            cleanup()
        }
        
        isConfigured = true
        currentURL = url
        
        // Use cached asset from VideoCacheManager
        let asset = VideoCacheManager.shared.asset(for: url)
        let item = AVPlayerItem(asset: asset)
        
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = isMuted
        
        playerLooper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer = player
        
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = videoGravity
        layer.frame = bounds
        self.layer.addSublayer(layer)
        playerLayer = layer
        
        player.pause()
    }
    
    private func cleanup() {
        queuePlayer?.pause()
        playerLooper?.disableLooping()
        playerLayer?.removeFromSuperlayer()
        queuePlayer = nil
        playerLooper = nil
        playerLayer = nil
        currentURL = nil
    }
    
    func play() {
        queuePlayer?.play()
    }
    
    func pause() {
        queuePlayer?.pause()
    }
    
    /// Returns the player's current playback time
    func getCurrentTime() -> CMTime {
        queuePlayer?.currentTime() ?? .zero
    }
    
    /// Returns the duration of the current item
    func getDuration() -> CMTime? {
        guard let item = queuePlayer?.currentItem,
              item.duration.isNumeric else { return nil }
        return item.duration
    }
    
    /// Seek to a fraction of the total duration (0…1)
    func seekToFraction(_ fraction: Double) {
        guard let item = queuePlayer?.currentItem,
              item.duration.isNumeric else { return }
        let target = CMTimeMultiplyByFloat64(item.duration, multiplier: Float64(fraction))
        queuePlayer?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    func setMuted(_ muted: Bool) {
        queuePlayer?.isMuted = muted
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
    
    deinit {
        cleanup()
    }
}

// MARK: - Video Background Modifier

extension View {
    /// Applies a looping video as the background with an optional dark overlay
    func videoBackground(
        videoName: String,
        videoExtension: String = "mp4",
        overlayOpacity: Double = 0.4,
        isPlaying: Bool = true
    ) -> some View {
        self.background(
            ZStack {
                LoopingVideoPlayer(
                    videoName: videoName,
                    videoExtension: videoExtension,
                    isPlaying: isPlaying
                )
                .ignoresSafeArea()
                
                Color.black.opacity(overlayOpacity)
                    .ignoresSafeArea()
            }
        )
    }
}
