//
//  KeychainManager.swift
//  simplessh
//
//  Created by Miguel Jackson on 3/18/26.
//

import Foundation
import Security
import LocalAuthentication

/// Manager for securely storing and retrieving SSH keys using iOS Keychain
/// Implements biometric authentication for accessing sensitive credentials
class KeychainManager {
    /// Shared singleton instance
    static let shared = KeychainManager()
    
    /// Private initializer to enforce singleton pattern
    private init() {}
    
    // MARK: - Keychain Constants
    
    /// Service identifier for keychain items
    private let service = "com.simplessh.sshkeys"
    
    /// Access group for keychain sharing (optional)
    private let accessGroup: String? = nil
    
    // MARK: - SSH Key Storage
    
    /// Stores an SSH private key securely in the Keychain with biometric protection
    /// - Parameters:
    ///   - key: The SSH private key string (PEM format)
    ///   - identifier: Unique identifier for this key (typically connection ID)
    ///   - requireBiometric: Whether to require biometric authentication to access the key
    /// - Returns: True if successful, false otherwise
    @discardableResult
    func storeSSHKey(_ key: String, for identifier: String, requireBiometric: Bool = true) -> Bool {
        guard let keyData = key.data(using: .utf8) else {
            return false
        }
        
        // Create access control for biometric authentication
        var accessControl: SecAccessControl?
        if requireBiometric {
            var error: Unmanaged<CFError>?
            accessControl = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.biometryCurrentSet, .or, .devicePasscode], // Biometry or passcode
                &error
            )
            
            if let error = error {
                print("Failed to create access control: \(error.takeRetainedValue())")
                return false
            }
        }
        
        // Delete any existing key first
        deleteSSHKey(for: identifier)
        
        // Build query dictionary
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier,
            kSecValueData as String: keyData,
            kSecAttrLabel as String: "SSH Private Key",
            kSecAttrDescription as String: "SSH authentication key"
        ]
        
        // Add access control if biometric is required
        if let accessControl = accessControl {
            query[kSecAttrAccessControl as String] = accessControl
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        
        // Add access group if specified
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        // Add to keychain
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("Successfully stored SSH key in Keychain")
            return true
        } else {
            print("Failed to store SSH key: \(status)")
            return false
        }
    }
    
    /// Retrieves an SSH private key from the Keychain
    /// This will trigger biometric authentication if required
    /// - Parameter identifier: Unique identifier for the key
    /// - Returns: The SSH private key string, or nil if not found or authentication failed
    func retrieveSSHKey(for identifier: String) -> String? {
        // Build query dictionary
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        // Add access group if specified
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        // Add biometric authentication prompt
        let context = LAContext()
        context.localizedReason = "Authenticate to access SSH key"
        query[kSecUseAuthenticationContext as String] = context
        
        // Retrieve from keychain
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        } else {
            print("Failed to retrieve SSH key: \(status)")
            return nil
        }
    }
    
    /// Retrieves an SSH private key without biometric authentication (for non-protected keys)
    /// - Parameter identifier: Unique identifier for the key
    /// - Returns: The SSH private key string, or nil if not found
    func retrieveSSHKeyWithoutAuth(for identifier: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: { let ctx = LAContext(); ctx.interactionNotAllowed = true; return ctx }() // Don't prompt for auth
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        
        return nil
    }
    
    /// Deletes an SSH private key from the Keychain
    /// - Parameter identifier: Unique identifier for the key
    /// - Returns: True if successful or key doesn't exist, false on error
    @discardableResult
    func deleteSSHKey(for identifier: String) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemDelete(query as CFDictionary)
        
        // errSecItemNotFound means it didn't exist, which is fine
        if status == errSecSuccess || status == errSecItemNotFound {
            return true
        } else {
            print("Failed to delete SSH key: \(status)")
            return false
        }
    }
    
    /// Updates an existing SSH key in the Keychain
    /// - Parameters:
    ///   - key: The new SSH private key string
    ///   - identifier: Unique identifier for the key
    /// - Returns: True if successful, false otherwise
    @discardableResult
    func updateSSHKey(_ key: String, for identifier: String) -> Bool {
        guard let keyData = key.data(using: .utf8) else {
            return false
        }
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let attributes: [String: Any] = [
            kSecValueData as String: keyData
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        if status == errSecSuccess {
            return true
        } else if status == errSecItemNotFound {
            // If key doesn't exist, create it
            return storeSSHKey(key, for: identifier)
        } else {
            print("Failed to update SSH key: \(status)")
            return false
        }
    }
    
    // MARK: - Biometric Authentication
    
    /// Checks if biometric authentication is available on this device
    /// - Returns: True if Face ID or Touch ID is available and enrolled
    func isBiometricAuthenticationAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    /// Gets the type of biometric authentication available
    /// - Returns: String describing the biometric type ("Face ID", "Touch ID", or "None")
    func biometricType() -> String {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "None"
        }
        
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "None"
        @unknown default:
            return "Unknown"
        }
    }
    
    /// Authenticates the user with biometrics
    /// - Parameter reason: The reason to display to the user
    /// - Returns: True if authentication succeeded, false otherwise
    func authenticateUser(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        
        // Check if biometric authentication is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            print("Biometric authentication not available: \(error?.localizedDescription ?? "Unknown")")
            return false
        }
        
        // Perform authentication
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success
        } catch {
            print("Biometric authentication failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Authenticates the user with biometrics or passcode as fallback
    /// - Parameter reason: The reason to display to the user
    /// - Returns: True if authentication succeeded, false otherwise
    func authenticateUserWithPasscode(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication, // Allows passcode fallback
                localizedReason: reason
            )
            return success
        } catch {
            print("Authentication failed: \(error.localizedDescription)")
            return false
        }
    }
}
