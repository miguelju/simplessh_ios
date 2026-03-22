//
//  AddConnectionView.swift
//  simplessh
//
//  Created by Miguel Jackson on 3/18/26.
//

import SwiftUI
import SwiftData

/// View for adding or editing SSH connection details
/// Features a modern Liquid Glass design with intuitive input fields
struct AddConnectionView: View {
    /// Access to the SwiftData model context for saving connections
    @Environment(\.modelContext) private var modelContext
    
    /// Environment variable to dismiss this view
    @Environment(\.dismiss) private var dismiss
    
    /// Connection name entered by the user
    @State private var connectionName: String = ""
    
    /// Server IP address or hostname
    @State private var serverIP: String = ""
    
    /// SSH username
    @State private var username: String = ""
    
    /// SSH private key content
    @State private var sshKey: String = ""
    
    /// SSH port number (default: 22)
    @State private var port: String = "22"
    
    /// Whether to require biometric authentication
    @State private var requireBiometric: Bool = true
    
    /// Flag to show validation errors
    @State private var showError: Bool = false
    
    /// Error message to display
    @State private var errorMessage: String = ""
    
    /// Biometric type available on device
    private var biometricType: String {
        KeychainManager.shared.biometricType()
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header section with icon
                    headerSection
                    
                    // Input fields section
                    inputFieldsSection
                    
                    // SSH Key section
                    sshKeySection
                    
                    // Save button
                    saveButton
                }
                .padding()
            }
            .background(gradientBackground)
            .navigationTitle("New Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Invalid Input", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - View Components
    
    /// Header section with SSH icon
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.white)
                .frame(width: 120, height: 120)
                .glassEffect(.regular.tint(.blue).interactive(), in: .circle)
            
            Text("SSH Connection Setup")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.top)
    }
    
    /// Input fields for connection details
    private var inputFieldsSection: some View {
        VStack(spacing: 16) {
            // Connection name field
            InputFieldView(
                icon: "tag.fill",
                placeholder: "Connection Name",
                text: $connectionName
            )
            
            // Server IP field
            InputFieldView(
                icon: "server.rack",
                placeholder: "Server IP or Hostname",
                text: $serverIP,
                keyboardType: .URL
            )
            
            // Username field
            InputFieldView(
                icon: "person.fill",
                placeholder: "Username",
                text: $username,
                autocapitalization: .never
            )
            
            // Port field
            InputFieldView(
                icon: "network",
                placeholder: "Port",
                text: $port,
                keyboardType: .numberPad
            )
        }
    }
    
    /// SSH Key input section
    private var sshKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("SSH Private Key", systemImage: "key.fill")
                .font(.headline)
                .foregroundStyle(.white)
            
            TextEditor(text: $sshKey)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 150)
                .padding()
                .background(Color.black.opacity(0.2))
                .glassEffect(.regular.tint(.gray).interactive(), in: .rect(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            
            Text("Paste your SSH private key (PEM format)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Biometric authentication toggle
            if KeychainManager.shared.isBiometricAuthenticationAvailable() {
                Toggle(isOn: $requireBiometric) {
                    HStack(spacing: 8) {
                        Image(systemName: biometricType == "Face ID" ? "faceid" : "touchid")
                        Text("Require \(biometricType)")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                }
                .tint(.blue)
                .padding()
                .glassEffect(.regular.tint(.blue).interactive(), in: .rect(cornerRadius: 12))
            }
        }
    }
    
    /// Save button with glass effect
    private var saveButton: some View {
        Button(action: saveConnection) {
            Label("Save Connection", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .glassEffect(.regular.tint(.green).interactive(), in: .capsule)
        }
        .padding(.top)
    }
    
    /// Gradient background
    private var gradientBackground: some View {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.3),
                Color.purple.opacity(0.3),
                Color.blue.opacity(0.3)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Actions
    
    /// Validates input and saves the SSH connection
    private func saveConnection() {
        // Validate inputs
        guard !connectionName.isEmpty else {
            showError(message: "Please enter a connection name")
            return
        }
        
        guard !serverIP.isEmpty else {
            showError(message: "Please enter a server IP or hostname")
            return
        }
        
        guard !username.isEmpty else {
            showError(message: "Please enter a username")
            return
        }
        
        guard !sshKey.isEmpty else {
            showError(message: "Please paste your SSH private key")
            return
        }
        
        guard let portNumber = Int(port), portNumber > 0, portNumber <= 65535 else {
            showError(message: "Please enter a valid port number (1-65535)")
            return
        }
        
        // Create and save the connection
        let connection = SSHConnection(
            name: connectionName,
            serverIP: serverIP,
            username: username,
            port: portNumber,
            requiresBiometric: requireBiometric
        )
        
        // Store SSH key in Keychain
        guard connection.storeSSHKey(sshKey) else {
            showError(message: "Failed to store SSH key securely. Please try again.")
            return
        }
        
        // Save connection to SwiftData
        modelContext.insert(connection)
        
        // Dismiss the view
        dismiss()
    }
    
    /// Shows an error alert
    /// - Parameter message: Error message to display
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Input Field Component

/// Reusable input field with icon and glass effect
struct InputFieldView: View {
    /// Icon name for the field
    let icon: String
    
    /// Placeholder text
    let placeholder: String
    
    /// Binding to the text value
    @Binding var text: String
    
    /// Keyboard type (default: .default)
    var keyboardType: UIKeyboardType = .default
    
    /// Text autocapitalization style
    var autocapitalization: TextInputAutocapitalization = .sentences
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 24)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
        }
        .padding()
        .frame(height: 56)
        .glassEffect(.regular.tint(.blue).interactive(), in: .rect(cornerRadius: 16))
    }
}

// MARK: - Preview

#Preview {
    AddConnectionView()
        .modelContainer(for: SSHConnection.self, inMemory: true)
}
