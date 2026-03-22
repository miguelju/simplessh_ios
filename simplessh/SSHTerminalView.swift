//
//  SSHTerminalView.swift
//  simplessh
//
//  Created by Miguel Jackson on 3/18/26.
//

import SwiftUI
import SwiftData

/// Terminal view with real SSH connection via Citadel (SwiftNIO SSH)
/// Includes biometric authentication, error handling, and full terminal emulation
struct SSHTerminalView: View {
    /// The SSH connection to use
    let connection: SSHConnection
    
    /// SSH manager handling the connection
    @StateObject private var sshManager = SSHManager()
    
    /// Whether authentication is in progress
    @State private var isAuthenticating: Bool = false
    
    /// Whether to show error alert
    @State private var showError: Bool = false
    
    /// Error message to display
    @State private var errorMessage: String = ""
    
    /// Access to model context for updating last used date
    @Environment(\.modelContext) private var modelContext
    
    /// Environment variable to dismiss this view
    @Environment(\.dismiss) private var dismiss
    
    /// Whether the terminal was previously connected (for exit detection)
    @State private var wasConnected: Bool = false

    /// Scroll view proxy for auto-scrolling
    @State private var scrollProxy: ScrollViewProxy?

    /// Parsed terminal output with ANSI colors/styles
    @State private var parsedOutput: AttributedString = AttributedString()

    /// Terminal appearance settings
    @ObservedObject private var terminalSettings = TerminalSettingsStore.shared

    /// Whether settings sheet is presented
    @State private var showSettings: Bool = false
    
    var body: some View {
        ZStack {
            // Terminal output area (full screen)
            terminalOutputSection

            // Invisible keyboard capture — sits in the ZStack to maintain first responder
            TerminalKeyboardCapture(
                onInput: { data in
                    Task {
                        try? await sshManager.sendRawData(data)
                    }
                },
                isConnected: sshManager.isConnected
            )
            .frame(width: 1, height: 1)
            .opacity(0)
        }
        .background(terminalSettings.backgroundColor)
        .navigationTitle(connection.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .toolbar {
            toolbarContent
        }
        .task {
            await connectToServer()
        }
        .onDisappear {
            sshManager.disconnect()
        }
        .onChange(of: sshManager.isConnected) { oldValue, newValue in
            // Track connection state for exit detection
            if newValue {
                wasConnected = true
            }
            // Auto-dismiss when connection drops after being connected (e.g. user typed "exit")
            if wasConnected && !newValue {
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    dismiss()
                }
            }
        }
        .alert("SSH Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
            if !sshManager.isConnected {
                Button("Retry") {
                    Task {
                        await connectToServer()
                    }
                }
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - View Components
    
    /// Terminal output display area with ANSI support
    private var terminalOutputSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(parsedOutput)
                        .font(terminalSettings.font)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("terminal-bottom")
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(terminalSettings.backgroundColor)
            .onChange(of: sshManager.terminalOutput) { oldValue, newValue in
                // Parse ANSI escape codes into styled AttributedString
                parsedOutput = ANSIParser.parse(
                    newValue,
                    defaultForeground: terminalSettings.foregroundColor,
                    defaultFont: terminalSettings.font,
                    boldFont: terminalSettings.boldFont
                )
                // Auto-scroll to bottom when new output arrives
                withAnimation {
                    proxy.scrollTo("terminal-bottom", anchor: .bottom)
                }
            }
            .onAppear {
                scrollProxy = proxy
            }
        }
    }
    
    /// Toolbar content
    private var toolbarContent: some ToolbarContent {
        Group {
            // Connection status indicator
            ToolbarItem(placement: .primaryAction) {
                connectionStatusView
            }

            // Settings and disconnect
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }

            ToolbarItem(placement: .secondaryAction) {
                if sshManager.isConnected {
                    Button("Disconnect", role: .destructive) {
                        sshManager.disconnect()
                    }
                }
            }
        }
    }
    
    /// Connection status indicator
    private var connectionStatusView: some View {
        HStack(spacing: 6) {
            if isAuthenticating {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting...")
                    .font(.caption)
            } else {
                Circle()
                    .fill(sshManager.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Text(sshManager.statusMessage.isEmpty ? (sshManager.isConnected ? "Connected" : "Disconnected") : sshManager.statusMessage)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(sshManager.isConnected ? .green : .red).interactive(), in: .capsule)
    }
    
    // MARK: - SSH Actions
    
    /// Connects to the SSH server with biometric authentication
    private func connectToServer() async {
        isAuthenticating = true
        
        do {
            // Authenticate with biometrics if required
            if connection.requiresBiometric {
                let authenticated = await KeychainManager.shared.authenticateUserWithPasscode(
                    reason: "Authenticate to access SSH key for \(connection.name)"
                )
                
                guard authenticated else {
                    errorMessage = "Authentication required to access SSH key"
                    showError = true
                    isAuthenticating = false
                    return
                }
            }
            
            // Connect to SSH server
            try await sshManager.connect(to: connection)
            
            // Update last used date
            connection.lastUsedAt = Date()
            try? modelContext.save()
            
        } catch let error as SSHManager.SSHError {
            errorMessage = error.localizedDescription
            showError = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isAuthenticating = false
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SSHTerminalView(
            connection: SSHConnection(
                name: "Production Server",
                serverIP: "192.168.1.100",
                username: "admin"
            )
        )
    }
}
