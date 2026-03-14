//
//  ToastView.swift
//  AIVideo
//
//  Toast notification system for showing non-intrusive alerts
//  Used primarily for generation completion notifications
//

import SwiftUI
import Combine

// MARK: - Toast Model

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let icon: String
    let type: ToastType
    let action: ToastAction?
    
    enum ToastType {
        case success
        case info
        case error
        
        var iconColor: Color {
            switch self {
            case .success: return .videoAccent
            case .info: return .videoTextSecondary
            case .error: return .videoError
            }
        }
    }
    
    enum ToastAction: Equatable {
        case navigateToMyVideos
        case dismiss
        
        static func == (lhs: ToastAction, rhs: ToastAction) -> Bool {
            switch (lhs, rhs) {
            case (.navigateToMyVideos, .navigateToMyVideos): return true
            case (.dismiss, .dismiss): return true
            default: return false
            }
        }
    }
    
    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Toast Manager

@MainActor
final class ToastManager: ObservableObject {
    // MARK: - Singleton
    static let shared = ToastManager()
    
    // MARK: - Published Properties
    @Published private(set) var currentToast: Toast?
    @Published private(set) var isVisible = false
    
    // MARK: - Private
    private var dismissTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let autoDismissDelay: TimeInterval = 5.0
    
    // MARK: - Initialization
    
    private init() {
        setupNotificationListeners()
    }
    
    // MARK: - Setup
    
    private func setupNotificationListeners() {
        // Listen for generation completed notifications
        NotificationCenter.default.publisher(for: .generationCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showGenerationCompleted()
            }
            .store(in: &cancellables)
        
        // Listen for generation failed notifications
        NotificationCenter.default.publisher(for: .generationFailed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let error = notification.userInfo?["error"] as? String {
                    self?.showGenerationFailed(error: error)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Show a toast for generation completed
    func showGenerationCompleted() {
        // Don't show if user is already on My Videos tab
        if AppState.shared.currentTab == .myVideos {
            print("ℹ️ ToastManager: Skipping toast - user on My Videos tab")
            return
        }
        
        show(Toast(
            message: "Your video is ready!",
            icon: "checkmark.circle.fill",
            type: .success,
            action: .navigateToMyVideos
        ))
    }
    
    /// Show a toast for generation failed
    func showGenerationFailed(error: String) {
        show(Toast(
            message: "Generation failed",
            icon: "exclamationmark.circle.fill",
            type: .error,
            action: .navigateToMyVideos
        ))
    }
    
    /// Show a custom toast
    func show(_ toast: Toast) {
        // Cancel any pending dismiss
        dismissTask?.cancel()
        
        // Update state
        currentToast = toast
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isVisible = true
        }
        
        print("✅ ToastManager: Showing toast - \(toast.message)")
        
        // Schedule auto-dismiss
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(autoDismissDelay * 1_000_000_000))
            
            if !Task.isCancelled {
                await dismiss()
            }
        }
    }
    
    /// Dismiss the current toast
    func dismiss() {
        dismissTask?.cancel()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isVisible = false
        }
        
        // Clear toast after animation
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            if !isVisible {
                currentToast = nil
            }
        }
    }
    
    /// Handle toast tap action
    func handleAction() {
        guard let toast = currentToast else { return }
        
        switch toast.action {
        case .navigateToMyVideos:
            AppState.shared.navigateToTab(.myVideos)
            HapticManager.shared.selection()
        case .dismiss, .none:
            break
        }
        
        dismiss()
    }
}

// MARK: - Toast View

struct ToastView: View {
    @ObservedObject private var toastManager = ToastManager.shared
    
    var body: some View {
        VStack {
            if toastManager.isVisible, let toast = toastManager.currentToast {
                toastContent(toast)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
            
            Spacer()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toastManager.isVisible)
    }
    
    private func toastContent(_ toast: Toast) -> some View {
        Button {
            toastManager.handleAction()
        } label: {
            HStack(spacing: VideoSpacing.sm) {
                Image(systemName: toast.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(toast.type.iconColor)
                
                Text(toast.message)
                    .font(.videoSubheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.videoTextPrimary)
                
                Spacer()
                
                if toast.action == .navigateToMyVideos {
                    HStack(spacing: VideoSpacing.xxs) {
                        Text("View")
                            .font(.videoCaption)
                            .foregroundColor(.videoAccent)
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.videoAccent)
                    }
                }
            }
            .padding(.horizontal, VideoSpacing.md)
            .padding(.vertical, VideoSpacing.sm)
            .background(Color.videoSurface)
            .cornerRadius(VideoSpacing.radiusMedium)
            .overlay(
                RoundedRectangle(cornerRadius: VideoSpacing.radiusMedium)
                    .stroke(toast.type.iconColor.opacity(0.3), lineWidth: 1)
            )
            .videoElevatedShadow()
        }
        .buttonStyle(ToastButtonStyle())
        .padding(.horizontal, VideoSpacing.screenHorizontal)
        .padding(.top, 60) // Below status bar and safe area
    }
}

// MARK: - Toast Button Style

struct ToastButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview("Success Toast") {
    ZStack {
        Color.videoBackground.ignoresSafeArea()
        
        ToastView()
    }
    .onAppear {
        ToastManager.shared.show(Toast(
            message: "Your video is ready!",
            icon: "checkmark.circle.fill",
            type: .success,
            action: .navigateToMyVideos
        ))
    }
}

#Preview("Error Toast") {
    ZStack {
        Color.videoBackground.ignoresSafeArea()
        
        ToastView()
    }
    .onAppear {
        ToastManager.shared.show(Toast(
            message: "Generation failed",
            icon: "exclamationmark.circle.fill",
            type: .error,
            action: .navigateToMyVideos
        ))
    }
}
