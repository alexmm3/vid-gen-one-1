//
//  ErrorView.swift
//  AIVideo
//
//  Reusable error display component
//

import SwiftUI

struct ErrorView: View {
    let error: AppError
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?
    
    var body: some View {
        VStack(spacing: VideoSpacing.lg) {
            // Icon
            Image(systemName: iconName)
                .font(.system(size: 50))
                .foregroundColor(iconColor)
            
            // Title
            Text(error.title)
                .font(.videoHeadline)
                .foregroundColor(.videoTextPrimary)
            
            // Message
            Text(error.message)
                .font(.videoBody)
                .foregroundColor(.videoTextSecondary)
                .multilineTextAlignment(.center)
            
            // Actions
            VStack(spacing: VideoSpacing.sm) {
                if error.isRetryable, let onRetry = onRetry {
                    VideoButton(title: "Try Again", action: onRetry)
                }
                
                if let onDismiss = onDismiss {
                    VideoButton(title: "Dismiss", action: onDismiss, style: .secondary)
                }
            }
            .padding(.top, VideoSpacing.sm)
        }
        .padding(VideoSpacing.xl)
        .background(Color.videoSurface)
        .cornerRadius(VideoSpacing.radiusLarge)
    }
    
    private var iconName: String {
        switch error {
        case .network: return "wifi.exclamationmark"
        case .api: return "exclamationmark.triangle"
        case .noSubscription: return "lock"
        case .limitReached: return "exclamationmark.circle"
        case .imageProcessing: return "photo.badge.exclamationmark"
        case .storage: return "externaldrive.badge.exclamationmark"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private var iconColor: Color {
        switch error {
        case .noSubscription, .limitReached:
            return .videoAccent
        default:
            return .videoError
        }
    }
}

// MARK: - Error Alert Modifier

extension View {
    func errorAlert(error: Binding<AppError?>, onRetry: (() -> Void)? = nil) -> some View {
        self.alert(
            error.wrappedValue?.title ?? "Error",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { if !$0 { error.wrappedValue = nil } }
            )
        ) {
            Button("OK") { error.wrappedValue = nil }
            
            if error.wrappedValue?.isRetryable == true, let onRetry = onRetry {
                Button("Retry") {
                    error.wrappedValue = nil
                    onRetry()
                }
            }
        } message: {
            Text(error.wrappedValue?.message ?? "Unknown error")
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.videoBackground.ignoresSafeArea()
        
        ErrorView(
            error: .network("Unable to connect to server"),
            onRetry: {},
            onDismiss: {}
        )
        .padding()
    }
}
