//
//  SSHConnection.swift
//  simplessh
//
//  Created by Miguel Jackson on 3/18/26.
//

import Foundation
import SwiftData

/// Model representing an SSH connection configuration
/// Connection details are stored in SwiftData, SSH keys are stored securely in Keychain
@Model
final class SSHConnection {
    /// Unique identifier for the connection
    /// Also used as the Keychain identifier for the SSH key
    var id: UUID
    
    /// Display name for this SSH connection
    var name: String
    
    /// IP address or hostname of the SSH server
    var serverIP: String
    
    /// Username for SSH authentication
    var username: String
    
    /// Port number for SSH connection (default: 22)
    var port: Int
    
    /// Timestamp when this connection was created
    var createdAt: Date
    
    /// Timestamp when this connection was last used
    var lastUsedAt: Date?
    
    /// Whether biometric authentication is required to use this connection
    var requiresBiometric: Bool
    
    /// Initialize a new SSH connection
    /// - Parameters:
    ///   - name: Display name for the connection
    ///   - serverIP: IP address or hostname of the server
    ///   - username: SSH username
    ///   - port: SSH port (default: 22)
    ///   - requiresBiometric: Whether to require biometric auth (default: true)
    /// - Note: SSH key should be stored separately using KeychainManager
    init(name: String, serverIP: String, username: String, port: Int = 22, requiresBiometric: Bool = true) {
        self.id = UUID()
        self.name = name
        self.serverIP = serverIP
        self.username = username
        self.port = port
        self.createdAt = Date()
        self.lastUsedAt = nil
        self.requiresBiometric = requiresBiometric
    }
    
    // MARK: - Keychain Integration
    
    /// Stores the SSH key securely in the Keychain
    /// - Parameter key: The SSH private key in PEM format
    /// - Returns: True if storage was successful
    @discardableResult
    func storeSSHKey(_ key: String) -> Bool {
        return KeychainManager.shared.storeSSHKey(
            key,
            for: id.uuidString,
            requireBiometric: requiresBiometric
        )
    }
    
    /// Retrieves the SSH key from the Keychain
    /// Will trigger biometric authentication if required
    /// - Returns: The SSH private key, or nil if not found or auth failed
    func retrieveSSHKey() -> String? {
        return KeychainManager.shared.retrieveSSHKey(for: id.uuidString)
    }
    
    /// Deletes the SSH key from the Keychain
    /// Should be called when deleting a connection
    @discardableResult
    func deleteSSHKey() -> Bool {
        return KeychainManager.shared.deleteSSHKey(for: id.uuidString)
    }
    
    /// Checks if an SSH key exists in the Keychain for this connection
    /// - Returns: True if a key exists
    func hasSSHKey() -> Bool {
        return KeychainManager.shared.retrieveSSHKeyWithoutAuth(for: id.uuidString) != nil
    }
}
