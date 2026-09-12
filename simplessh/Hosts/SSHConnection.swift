//
//  SSHConnection.swift
//  simplessh
//
//  Created by Miguel Jackson on 3/18/26.
//

import Foundation
import SwiftData

/// Model representing an SSH connection configuration.
/// Connection details are stored in SwiftData; the private key is stored by a
/// `KeyStore` (the Keychain in the app) under `id.uuidString`.
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
    /// - Note: The SSH key is stored separately through a `KeyStore`.
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
}
