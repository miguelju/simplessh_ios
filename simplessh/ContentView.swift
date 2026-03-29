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
    
    /// Current color scheme for adaptive styling
    @Environment(\.colorScheme) private var colorScheme

    /// Controls whether the "Add Connection" sheet is presented
    @State private var showingAddConnection = false
    
    /// Controls whether the edit mode is active
    @State private var editMode: EditMode = .inactive

    /// Controls whether the settings sheet is presented
    @State private var showingSettings = false
    
    /// The connection currently being edited (nil when not editing)
    @State private var connectionToEdit: SSHConnection?
    
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
            // Sheet for adding a new connection
            .sheet(isPresented: $showingAddConnection) {
                AddConnectionView()
            }
            // Sheet for editing an existing connection (triggered by edit mode tap or context menu)
            .sheet(item: $connectionToEdit) { connection in
                AddConnectionView(connectionToEdit: connection)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
    
    // MARK: - View Components
    
    /// Background that adapts to light/dark mode.
    /// Light: clean light gray (Outlook-style). Dark: blue/purple gradient.
    private var backgroundGradient: some View {
        Group {
            if colorScheme == .dark {
                Color(.systemBackground)
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.3),
                                Color.purple.opacity(0.2),
                                Color.blue.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            } else {
                Color(.systemGroupedBackground)
            }
        }
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
            // Icon with glass effect — white on dark glass, accent blue on light glass
            Image(systemName: "server.rack")
                .font(.system(size: 80))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.accentColor)
                .frame(width: 160, height: 160)
                .glassEffect(.regular.tint(.blue.opacity(colorScheme == .dark ? 1.0 : 0.3)).interactive(), in: .circle)
            
            VStack(spacing: 12) {
                Text("No SSH Connections")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                
                Text("Add your first connection to get started")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Add connection button
            Button(action: { showingAddConnection = true }) {
                Label("Add Connection", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.accentColor)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .glassEffect(.regular.tint(.blue.opacity(colorScheme == .dark ? 1.0 : 0.3)).interactive(), in: .capsule)
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
                    // Pass edit mode state and edit callback to each row.
                    // In edit mode, tapping a row opens the edit sheet instead of the terminal.
                    ConnectionRowView(
                        connection: connection,
                        isEditMode: editMode == .active,
                        onEdit: {
                            connectionToEdit = connection
                        }
                    )
                    .contextMenu {
                        // Long-press context menu: edit or delete without entering edit mode
                        Button {
                            connectionToEdit = connection
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        
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
                }
            }
            
            // Settings button
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
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

/// Individual row view for displaying an SSH connection with Liquid Glass.
/// Supports two modes:
/// - **Normal mode**: Tapping navigates to the SSH terminal view
/// - **Edit mode**: Tapping triggers the `onEdit` callback to open the edit sheet
struct ConnectionRowView: View {
    /// The SSH connection to display
    let connection: SSHConnection
    
    /// Whether the list is in edit mode (toggled via the toolbar three-dots menu)
    var isEditMode: Bool = false
    
    /// Callback invoked when the user taps this row while in edit mode
    var onEdit: (() -> Void)? = nil
    
    /// Current color scheme for adaptive styling
    @Environment(\.colorScheme) private var colorScheme

    /// Access to model context for deletion
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        if isEditMode {
            // In edit mode, tapping opens the edit sheet
            Button {
                onEdit?()
            } label: {
                rowContent(showEditIcon: true)
            }
            .buttonStyle(.plain)
        } else {
            // In normal mode, tapping navigates to the terminal
            NavigationLink {
                SSHTerminalView(connection: connection)
            } label: {
                rowContent(showEditIcon: false)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
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
    
    /// Shared row content used in both normal and edit modes
    private func rowContent(showEditIcon: Bool) -> some View {
        HStack(spacing: 16) {
            // Server icon with glass effect — white on dark glass, accent blue on light glass
            Image(systemName: "terminal.fill")
                .font(.title2)
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.accentColor)
                .frame(width: 60, height: 60)
                .glassEffect(.regular.tint(.blue.opacity(colorScheme == .dark ? 1.0 : 0.4)).interactive(), in: .circle)
            
            // Connection details
            VStack(alignment: .leading, spacing: 6) {
                Text(connection.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                HStack(spacing: 12) {
                    Label(connection.username, systemImage: "person.fill")
                    Label(connection.serverIP, systemImage: "network")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                
                if let lastUsed = connection.lastUsedAt {
                    Text("Last used: \(lastUsed, format: .relative(presentation: .named))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Show pencil icon in edit mode, chevron in normal mode
            if showEditIcon {
                Image(systemName: "pencil.circle.fill")
                    .font(.title2)
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.accentColor)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .frame(minHeight: 100)
        // Light: subtle neutral glass card. Dark: purple-tinted glass.
        .glassEffect(
            .regular.tint(colorScheme == .dark ? .purple : .blue.opacity(0.15)).interactive(),
            in: .rect(cornerRadius: 20)
        )
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

