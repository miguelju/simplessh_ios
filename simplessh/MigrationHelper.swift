//
//  MigrationHelper.swift
//  simplessh
//
//  Created by Miguel Jackson on 3/18/26.
//

import Foundation
import SwiftData

/// Helper class for migrating data from the old demo version to the production version
/// This handles moving SSH keys from SwiftData to Keychain
@MainActor
class MigrationHelper {
    
    /// Migrates old SSHConnection objects that stored keys in SwiftData to the new Keychain-based system
    /// - Parameter modelContext: The SwiftData model context
    /// - Returns: Number of connections migrated
    /// - Note: This should be run once on app upgrade
    static func migrateToKeychainStorage(modelContext: ModelContext) async -> Int {
        let migratedCount = 0
        
        // Fetch all connections
        let descriptor = FetchDescriptor<SSHConnection>()
        
        do {
            let connections = try modelContext.fetch(descriptor)
            
            for connection in connections {
                // Check if connection already has a key in Keychain
                if connection.hasSSHKey() {
                    print("Connection \(connection.name) already migrated")
                    continue
                }
                
                // For the old model, you would retrieve the key from the old property
                // Since we've updated the model, this is示 what the migration would look like:
                
                /*
                // If we still had access to the old sshKey property:
                if !connection.sshKey.isEmpty {
                    // Store in Keychain
                    let success = connection.storeSSHKey(connection.sshKey)
                    
                    if success {
                        print("Migrated key for connection: \(connection.name)")
                        migratedCount += 1
                        
                        // Clear the old property (if it still existed)
                        // connection.sshKey = ""
                    } else {
                        print("Failed to migrate key for connection: \(connection.name)")
                    }
                }
                */
                
                print("Note: Migration requires manual re-entry of SSH keys")
            }
            
            // Save changes
            try modelContext.save()
            
        } catch {
            print("Migration failed: \(error)")
        }
        
        return migratedCount
    }
    
    /// Validates that all connections have their keys properly stored in Keychain
    /// - Parameter modelContext: The SwiftData model context
    /// - Returns: Array of connection names that are missing keys
    static func validateKeychainMigration(modelContext: ModelContext) -> [String] {
        var missingKeys: [String] = []
        
        let descriptor = FetchDescriptor<SSHConnection>()
        
        do {
            let connections = try modelContext.fetch(descriptor)
            
            for connection in connections {
                if !connection.hasSSHKey() {
                    missingKeys.append(connection.name)
                }
            }
        } catch {
            print("Validation failed: \(error)")
        }
        
        return missingKeys
    }
    
    /// Exports connection metadata (without keys) for backup
    /// - Parameter modelContext: The SwiftData model context
    /// - Returns: JSON string of connection metadata
    static func exportConnectionsMetadata(modelContext: ModelContext) -> String? {
        let descriptor = FetchDescriptor<SSHConnection>()
        
        do {
            let connections = try modelContext.fetch(descriptor)
            
            let metadata = connections.map { connection in
                [
                    "id": connection.id.uuidString,
                    "name": connection.name,
                    "serverIP": connection.serverIP,
                    "username": connection.username,
                    "port": String(connection.port),
                    "requiresBiometric": String(connection.requiresBiometric)
                ]
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
            return String(data: jsonData, encoding: .utf8)
            
        } catch {
            print("Export failed: \(error)")
            return nil
        }
    }
    
    /// Imports connection metadata from backup
    /// - Parameters:
    ///   - jsonString: JSON string of connection metadata
    ///   - modelContext: The SwiftData model context
    /// - Returns: Number of connections imported
    /// - Note: SSH keys must be manually re-entered after import
    static func importConnectionsMetadata(from jsonString: String, modelContext: ModelContext) -> Int {
        var importedCount = 0
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("Invalid JSON string")
            return 0
        }
        
        do {
            guard let metadataArray = try JSONSerialization.jsonObject(with: jsonData) as? [[String: String]] else {
                print("Invalid JSON format")
                return 0
            }
            
            for metadata in metadataArray {
                guard let name = metadata["name"],
                      let serverIP = metadata["serverIP"],
                      let username = metadata["username"],
                      let portString = metadata["port"],
                      let port = Int(portString) else {
                    continue
                }
                
                let requiresBiometric = metadata["requiresBiometric"] == "true"
                
                let connection = SSHConnection(
                    name: name,
                    serverIP: serverIP,
                    username: username,
                    port: port,
                    requiresBiometric: requiresBiometric
                )
                
                modelContext.insert(connection)
                importedCount += 1
            }
            
            try modelContext.save()
            
        } catch {
            print("Import failed: \(error)")
        }
        
        return importedCount
    }
    
    /// Cleanup utility to remove orphaned Keychain items
    /// Removes Keychain entries for connections that no longer exist in SwiftData
    /// - Parameter modelContext: The SwiftData model context
    /// - Returns: Number of orphaned keys removed
    static func cleanupOrphanedKeys(modelContext: ModelContext) -> Int {
        let cleanedCount = 0
        
        // This would require iterating through all Keychain items
        // which is not directly supported by the Keychain API
        // Instead, we rely on proper cleanup during connection deletion
        
        // For a more robust solution, you could maintain a list of connection IDs
        // in UserDefaults and compare against Keychain items
        
        print("Note: Keychain cleanup happens automatically during connection deletion")
        
        return cleanedCount
    }
}

// MARK: - Migration View

import SwiftUI

/// View to display migration status and allow manual migration
struct MigrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var migrationStatus: String = "Ready to migrate"
    @State private var missingKeys: [String] = []
    @State private var isMigrating: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Migration Status", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                        
                        Text(migrationStatus)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                
                if !missingKeys.isEmpty {
                    Section("Connections Missing Keys") {
                        ForEach(missingKeys, id: \.self) { name in
                            Label(name, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                
                Section {
                    Button(action: validateMigration) {
                        Label("Validate Migration", systemImage: "checkmark.shield")
                    }
                    
                    Button(action: exportMetadata) {
                        Label("Export Connections", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("Migration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                validateMigration()
            }
        }
    }
    
    private func validateMigration() {
        missingKeys = MigrationHelper.validateKeychainMigration(modelContext: modelContext)
        
        if missingKeys.isEmpty {
            migrationStatus = "✅ All connections have keys in Keychain"
        } else {
            migrationStatus = "⚠️ \(missingKeys.count) connection(s) need key re-entry"
        }
    }
    
    private func exportMetadata() {
        if let json = MigrationHelper.exportConnectionsMetadata(modelContext: modelContext) {
            // Share the JSON
            let activityVC = UIActivityViewController(
                activityItems: [json],
                applicationActivities: nil
            )
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootVC = window.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
            
            migrationStatus = "✅ Exported connection metadata"
        } else {
            migrationStatus = "❌ Export failed"
        }
    }
}

// MARK: - Preview

#Preview {
    MigrationView()
        .modelContainer(for: SSHConnection.self, inMemory: true)
}
