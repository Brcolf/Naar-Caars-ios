//
//  DeviceIdentifier.swift
//  NaarsCars
//
//  Persistent device identifier stored in Keychain
//

import Foundation
import Security

/// Utility for managing a persistent device identifier
/// Stores UUID in Keychain to survive app reinstalls
/// Used for push token management and device tracking
enum DeviceIdentifier {
    private static let keychainKey = "com.naarscars.deviceId"
    private static let keychainService = "com.naarscars"
    
    /// Current device identifier
    /// Returns existing identifier from Keychain or generates new one
    static var current: String {
        // Try to read from Keychain first
        if let existingId = readFromKeychain() {
            return existingId
        }
        
        // Generate new UUID if not found
        let newId = UUID().uuidString
        saveToKeychain(newId)
        return newId
    }
    
    // MARK: - Private Methods
    
    /// Read device identifier from Keychain
    /// - Returns: Device identifier string if found, nil otherwise
    private static func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let identifier = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return identifier
    }
    
    /// Save device identifier to Keychain
    /// - Parameter identifier: Device identifier string to save
    private static func saveToKeychain(_ identifier: String) {
        guard let data = identifier.data(using: .utf8) else {
            return
        }
        
        // First, try to update existing item
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainKey
        ]
        
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
        
        // If update failed (item doesn't exist), create new item
        if updateStatus == errSecItemNotFound {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainKey,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]
            
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}

