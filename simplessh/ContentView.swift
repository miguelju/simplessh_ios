//
//  ContentView.swift
//  simplessh
//
//  Created by Miguel Jackson on 3/18/26.
//

import SwiftUI
import SwiftData

/// Main view displaying saved SSH connections with Liquid Glass design
/// Users can view, add, and connect to their saved SSH servers
struct ContentView: View {
    /// Access to SwiftData model context for managing connections
    @Environment(\.modelContext) private var modelContext
    
    /// Query to fetch all saved SSH connections, sorted by last used date
    @Query(sort: \SSHConnection.createdAt, order: .reverse) private var connections: [SSHConnection]
    
    /// Controls whether the "Add Connection" sheet is presented
    @State private var showingAddConnection = false
    
    /// Controls whether the edit mode is active
    @State private var editMode: EditMode = .inactive

    /// Controls whether the settings sheet is presented
    @State private var showingSettings = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                backgroundGradient
                
                // Main content
                mainContent
            }
            .navigationTitle("SSH Connections")
            .toolbar {
                toolbarContent
            }
            .sheet(isPresented: $showingAddConnection) {
                AddConnectionView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
    
    // MARK: - View Components
    
    /// Background gradient with Liquid Glass aesthetic
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.3),
                Color.purple.opacity(0.2),
                Color.blue.opacity(0.3)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    /// Main content area - shows either connection list or empty state
    @ViewBuilder
    private var mainContent: some View {
        if connections.isEmpty {
            emptyStateView
        } else {
            connectionsList
        }
    }
    
    /// Empty state view shown when no connections exist
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            // Icon with glass effect
            Image(systemName: "server.rack")
                .font(.system(size: 80))
                .foregroundStyle(.white)
                .frame(width: 160, height: 160)
                .glassEffect(.regular.tint(.blue).interactive(), in: .circle)
            
            VStack(spacing: 12) {
                Text("No SSH Connections")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                
                Text("Add your first connection to get started")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Add connection button
            Button(action: { showingAddConnection = true }) {
                Label("Add Connection", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .glassEffect(.regular.tint(.blue).interactive(), in: .capsule)
            }
            .padding(.top)
        }
        .padding()
    }
    
    /// List of saved SSH connections
    private var connectionsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(connections) { connection in
                    ConnectionRowView(connection: connection)
                        .environment(\.editMode, $editMode)
                        .contextMenu {
                            // Context menu for quick actions
                            Button(role: .destructive) {
                                deleteConnection(connection)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding()
        }
    }
    
    /// Toolbar content with add and edit buttons
    private var toolbarContent: some ToolbarContent {
        Group {
            // Add button
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddConnection = true }) {
                    Label("Add Connection", systemImage: "plus")
                        .foregroundStyle(.white)
                }
            }
            
            // Settings button
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .foregroundStyle(.white)
                }
            }

            // Edit button (only show when connections exist)
            ToolbarItem(placement: .secondaryAction) {
                if !connections.isEmpty {
                    Button(editMode == .active ? "Done" : "Edit") {
                        withAnimation {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    /// Deletes a connection from the database and removes its SSH key from Keychain
    /// - Parameter connection: The connection to delete
    private func deleteConnection(_ connection: SSHConnection) {
        withAnimation {
            // Delete SSH key from Keychain first
            connection.deleteSSHKey()
            
            // Delete connection from SwiftData
            modelContext.delete(connection)
        }
    }
}

// MARK: - Connection Row View

/// Individual row view for displaying an SSH connection with Liquid Glass
struct ConnectionRowView: View {
    /// The SSH connection to display
    let connection: SSHConnection
    
    /// Edit mode from the environment
    @Environment(\.editMode) private var editMode
    
    /// Access to model context for deletion
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationLink {
            // Navigate to the terminal view
            SSHTerminalView(connection: connection)
        } label: {
            HStack(spacing: 16) {
                // Server icon with glass effect
                ZStack {
                    Image(systemName: "terminal.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .glassEffect(.regular.tint(.blue).interactive(), in: .circle)
                }
                
                // Connection details
                VStack(alignment: .leading, spacing: 6) {
                    Text(connection.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    HStack(spacing: 12) {
                        Label(connection.username, systemImage: "person.fill")
                        Label(connection.serverIP, systemImage: "network")
                    }
                    .font(.caption)
                    .foregroundStyle(.white)
                    
                    if let lastUsed = connection.lastUsedAt {
                        Text("Last used: \(lastUsed, format: .relative(presentation: .named))")
                            .font(.caption2)
                            .foregroundStyle(.white)
                    }
                }
                
                Spacer()
                
                // Chevron indicator
                if editMode?.wrappedValue == .inactive {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .frame(minHeight: 100)
            .glassEffect(.regular.tint(.purple).interactive(), in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            // Swipe to delete action
            Button(role: .destructive) {
                withAnimation {
                    connection.deleteSSHKey()
                    modelContext.delete(connection)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .modelContainer(for: SSHConnection.self, inMemory: true)
}
#Preview("With Connections") {
    let container = try! ModelContainer(
        for: SSHConnection.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    
    // Add sample connections
    let connection1 = SSHConnection(
        name: "Production Server",
        serverIP: "192.168.1.100",
        username: "admin"
    )
    connection1.lastUsedAt = Date().addingTimeInterval(-3600)
    
    let connection2 = SSHConnection(
        name: "Development Server",
        serverIP: "dev.example.com",
        username: "developer"
    )
    
    container.mainContext.insert(connection1)
    container.mainContext.insert(connection2)
    
    return ContentView()
        .modelContainer(container)
}

