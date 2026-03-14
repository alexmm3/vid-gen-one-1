//
//  KeychainManager.swift
//  AIVideo
//
//  Secure storage manager using iOS Keychain
//  Copied from templates-reference
//

import Foundation
import Security

final class KeychainManager {
    
    // MARK: - Singleton
    static let shared = KeychainManager()
    
    private init() {}
    
    // MARK: - Constants
    private enum Constants {
        static let service = Bundle.main.bundleIdentifier ?? "com.aivideo"
        static let accessGroup: String? = nil
    }
    
    // MARK: - Public Methods
    
    /// Store a string value in the keychain
    func store(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            print("KeychainManager: Failed to convert string to data")
            return false
        }
        
        // Delete existing item if it exists
        _ = delete(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            return true
        } else {
            return false
        }
    }
    
    /// Retrieve a string value from the keychain
    func retrieve(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess,
           let data = dataTypeRef as? Data,
           let string = String(data: data, encoding: .utf8) {
            return string
        } else if status == errSecItemNotFound {
            return nil
        } else {
            print("KeychainManager: Failed to retrieve key '\(key)' with status: \(status)")
            return nil
        }
    }
    
    /// Delete a key from the keychain
    func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess || status == errSecItemNotFound {
            return true
        } else {
            print("KeychainManager: Failed to delete key '\(key)' with status: \(status)")
            return false
        }
    }
    
    /// Check if a key exists in the keychain
    func exists(key: String) -> Bool {
        return retrieve(key: key) != nil
    }
    
    /// Clear all keys for this app
    func clearAll() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess || status == errSecItemNotFound {
            print("KeychainManager: Successfully cleared all keys")
            return true
        } else {
            print("KeychainManager: Failed to clear all keys with status: \(status)")
            return false
        }
    }
}
