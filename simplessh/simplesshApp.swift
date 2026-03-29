//
//  simplesshApp.swift
//  simplessh
//
//  Created by Miguel Jackson on 3/18/26.
//

import SwiftUI
import SwiftData

/// Main app entry point for the SSH terminal client
/// This app demonstrates a simple SSH interface for iOS using SwiftUI and Liquid Glass design
@main
struct simplesshApp: App {
    /// Shared model container for persisting SSH connection data
    var sharedModelContainer: ModelContainer = {
        // Define the schema with all data models
        let schema = Schema([
            SSHConnection.self,
        ])
        
        // Configure the model to persist data to disk
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    /// Terminal settings store (observes appearance changes)
    @ObservedObject private var settings = TerminalSettingsStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Apply the user's chosen appearance (nil = follow system)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .modelContainer(sharedModelContainer)
    }
}
