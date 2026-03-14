//
//  HapticManager.swift
//  AIVideo
//
//  Haptic feedback manager for consistent user feedback
//  Copied from GLAM reference
//

import Foundation
import UIKit

class HapticManager {
    static let shared = HapticManager()
    
    private init() {}
    
    // Track last haptic time to prevent rapid firing
    private var lastHapticTime: Date = Date.distantPast
    private let minimumHapticInterval: TimeInterval = 0.1
    
    private func safeHapticFeedback(_ action: @escaping () -> Void) {
        guard UIApplication.shared.applicationState == .active else { return }
        
        let now = Date()
        guard now.timeIntervalSince(lastHapticTime) >= minimumHapticInterval else { return }
        
        lastHapticTime = now
        
        DispatchQueue.main.async {
            action()
        }
    }
    
    // Light haptic for general taps
    func lightImpact() {
        safeHapticFeedback {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.prepare()
            impactFeedback.impactOccurred()
        }
    }
    
    // Medium haptic for more significant actions
    func mediumImpact() {
        safeHapticFeedback {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.prepare()
            impactFeedback.impactOccurred()
        }
    }
    
    // Heavy haptic for important actions
    func heavyImpact() {
        safeHapticFeedback {
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.prepare()
            impactFeedback.impactOccurred()
        }
    }
    
    // Success haptic for completed actions
    func success() {
        safeHapticFeedback {
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.prepare()
            notificationFeedback.notificationOccurred(.success)
        }
    }
    
    // Warning haptic for alerts
    func warning() {
        safeHapticFeedback {
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.prepare()
            notificationFeedback.notificationOccurred(.warning)
        }
    }
    
    // Error haptic for failures
    func error() {
        safeHapticFeedback {
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.prepare()
            notificationFeedback.notificationOccurred(.error)
        }
    }
    
    // Selection haptic for picker changes
    func selection() {
        safeHapticFeedback {
            let selectionFeedback = UISelectionFeedbackGenerator()
            selectionFeedback.prepare()
            selectionFeedback.selectionChanged()
        }
    }
    
    /// Notification haptic with type parameter
    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        safeHapticFeedback {
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.prepare()
            notificationFeedback.notificationOccurred(type)
        }
    }
    
    /// Impact haptic with style parameter
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        safeHapticFeedback {
            let impactFeedback = UIImpactFeedbackGenerator(style: style)
            impactFeedback.prepare()
            impactFeedback.impactOccurred()
        }
    }
}
