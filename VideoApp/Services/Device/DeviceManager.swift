//
//  DeviceManager.swift
//  AIVideo
//
//  Device identification for backend API calls
//  Based on iOS-API-Integration.md specification
//

import Foundation

final class DeviceManager {
    // MARK: - Singleton
    static let shared = DeviceManager()

    private let deviceIdKey = "ai_video_device_id"

    #if DEBUG
    private let debugPremiumFlagKey = "debug_simulate_premium"
    private let debugPremiumDevicePrefix = "debug-premium:"
    #endif

    // MARK: - Device ID

    /// Unique device identifier for backend API
    /// Format: device_{random}_{timestamp}
    var deviceId: String {
        // Try to retrieve from Keychain first
        if let existing = KeychainManager.shared.retrieve(key: deviceIdKey) {
            return existing
        }

        // Generate new ID
        let newId = generateDeviceId()

        // Store in Keychain
        _ = KeychainManager.shared.store(key: deviceIdKey, value: newId)

        return newId
    }

    /// Device ID used for generation/subscription backend flows.
    var backendDeviceId: String {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: debugPremiumFlagKey) else {
            return deviceId
        }
        return "\(debugPremiumDevicePrefix)\(deviceId)"
        #else
        return deviceId
        #endif
    }

    // MARK: - Private

    private init() {}

    private func generateDeviceId() -> String {
        let random = randomAlphanumericString(length: 8)
        let timestamp = Int(Date().timeIntervalSince1970)
        return "device_\(random)_\(timestamp)"
    }

    private func randomAlphanumericString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<length).map { _ in letters.randomElement()! })
    }

    // MARK: - Reset (for testing)

    /// Reset device ID (generates new one)
    func resetDeviceId() {
        _ = KeychainManager.shared.delete(key: deviceIdKey)
    }
}
