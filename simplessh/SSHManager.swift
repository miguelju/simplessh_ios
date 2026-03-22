//
//  SSHManager.swift
//  simplessh
//
//  Created by Miguel Jackson on 3/18/26.
//

import Foundation
import Combine
import Citadel
import NIOSSH
import NIOCore
import Crypto
import CCryptoBoringSSL

/// Manager class for handling SSH connections with Citadel (SwiftNIO SSH)
/// Provides thread-safe SSH session management with real-time output streaming
@MainActor
class SSHManager: ObservableObject {
    // MARK: - Published Properties (MainActor-isolated, for UI)

    /// Connection status
    @Published private(set) var isConnected: Bool = false

    /// Connection status message
    @Published private(set) var statusMessage: String = ""

    /// Terminal output stream (processed for display — handles backspace)
    @Published var terminalOutput: String = ""

    /// Last error encountered
    @Published private(set) var lastError: SSHError?

    // MARK: - Private Properties

    /// Citadel SSH client
    private var client: SSHClient?

    /// Writer for sending input to the PTY shell
    nonisolated(unsafe) private var _stdinWriter: TTYStdinWriter?

    /// Background task running the interactive shell session
    private var shellTask: Task<Void, Never>?

    /// Current connection configuration
    private var currentConnection: SSHConnection?

    // MARK: - SSH Error Types

    /// Enumeration of possible SSH errors
    enum SSHError: LocalizedError, Sendable {
        case connectionFailed(String)
        case authenticationFailed(String)
        case channelCreationFailed
        case shellStartFailed(String)
        case keyParsingFailed(String)
        case networkError(String)
        case sessionNotConnected
        case commandExecutionFailed(String)

        var errorDescription: String? {
            switch self {
            case .connectionFailed(let reason):
                return "Connection failed: \(reason)"
            case .authenticationFailed(let reason):
                return "Authentication failed: \(reason)"
            case .channelCreationFailed:
                return "Failed to create SSH channel"
            case .shellStartFailed(let reason):
                return "Failed to start shell: \(reason)"
            case .keyParsingFailed(let reason):
                return "Failed to parse SSH private key: \(reason)"
            case .networkError(let reason):
                return "Network error: \(reason)"
            case .sessionNotConnected:
                return "SSH session is not connected"
            case .commandExecutionFailed(let reason):
                return "Command execution failed: \(reason)"
            }
        }
    }

    // MARK: - Connection Management

    /// Connects to an SSH server using the provided connection details
    /// - Parameter connection: SSH connection configuration
    /// - Throws: SSHError if connection fails
    func connect(to connection: SSHConnection) async throws {
        currentConnection = connection
        statusMessage = "Connecting to \(connection.serverIP)..."
        lastError = nil
        terminalOutput = ""

        // Retrieve SSH key from Keychain
        guard let privateKeyString = KeychainManager.shared.retrieveSSHKey(for: connection.id.uuidString) else {
            let error = SSHError.keyParsingFailed("No key found in Keychain")
            self.lastError = error
            self.statusMessage = "Failed to retrieve SSH key from Keychain"
            throw error
        }

        // Parse the private key and build the authentication method
        let authMethod: SSHAuthenticationMethod
        do {
            authMethod = try Self.parsePrivateKey(from: privateKeyString, username: connection.username)
        } catch {
            let sshError = (error as? SSHError) ?? SSHError.keyParsingFailed(error.localizedDescription)
            self.lastError = sshError
            self.statusMessage = "Invalid SSH key format"
            throw sshError
        }

        // Connect to the SSH server
        statusMessage = "Establishing SSH session..."
        let sshClient: SSHClient
        do {
            sshClient = try await SSHClient.connect(
                host: connection.serverIP,
                port: connection.port,
                authenticationMethod: authMethod,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never
            )
        } catch {
            let sshError = SSHError.connectionFailed(error.localizedDescription)
            self.lastError = sshError
            self.statusMessage = "Connection failed"
            throw sshError
        }

        self.client = sshClient
        self.isConnected = true
        self.statusMessage = "Connected to \(connection.serverIP)"

        // Monitor disconnection
        sshClient.onDisconnect { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnected = false
                self.statusMessage = "Disconnected"
                self.processTerminalOutput("\n\n[Connection closed]\n")
                self._stdinWriter = nil
            }
        }

        // Start interactive shell with PTY in background
        shellTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await sshClient.withPTY(
                    .init(
                        wantReply: true,
                        term: "xterm-256color",
                        terminalCharacterWidth: 80,
                        terminalRowHeight: 24,
                        terminalPixelWidth: 0,
                        terminalPixelHeight: 0,
                        terminalModes: .init([:])
                    )
                ) { output, writer in
                    // Store the writer so sendCommand can use it
                    await MainActor.run {
                        self._stdinWriter = writer
                    }

                    // Read output and forward to UI
                    for try await event in output {
                        let text: String
                        switch event {
                        case .stdout(let buffer):
                            text = String(buffer: buffer)
                        case .stderr(let buffer):
                            text = String(buffer: buffer)
                        }
                        await MainActor.run {
                            self.processTerminalOutput(text)
                        }
                    }
                }
            } catch is CancellationError {
                // Normal disconnection
            } catch {
                await MainActor.run {
                    self.processTerminalOutput("\n[Shell error: \(error.localizedDescription)]\n")
                    self.isConnected = false
                    self.statusMessage = "Shell closed"
                }
            }
        }
    }

    /// Disconnects from the current SSH session
    func disconnect() {
        shellTask?.cancel()
        shellTask = nil
        _stdinWriter = nil

        let client = self.client
        self.client = nil
        isConnected = false
        statusMessage = "Disconnected"
        processTerminalOutput("\n\n[Connection closed]\n")

        Task {
            try? await client?.close()
        }
    }

    // MARK: - Command Execution

    /// Sends a command to the SSH session
    /// - Parameter command: Command string to execute
    /// - Throws: SSHError if command fails
    func sendCommand(_ command: String) async throws {
        guard let writer = _stdinWriter, isConnected else {
            throw SSHError.sessionNotConnected
        }

        let commandWithNewline = command + "\n"
        var buffer = ByteBufferAllocator().buffer(capacity: commandWithNewline.utf8.count)
        buffer.writeString(commandWithNewline)

        do {
            try await writer.write(buffer)
        } catch {
            throw SSHError.commandExecutionFailed(error.localizedDescription)
        }
    }

    /// Sends raw data to the SSH channel (for special keys like arrows, etc.)
    /// - Parameter data: Raw data to send
    func sendRawData(_ data: Data) async throws {
        guard let writer = _stdinWriter, isConnected else {
            throw SSHError.sessionNotConnected
        }

        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)

        do {
            try await writer.write(buffer)
        } catch {
            throw SSHError.commandExecutionFailed(error.localizedDescription)
        }
    }

    // MARK: - Terminal Output Processing

    /// Pre-processes raw PTY output to handle backspace (BS, 0x08) which erases the
    /// previous character. The backspace echo from the PTY sends `\b \b` (backspace,
    /// space, backspace) to visually erase a character, but since our output is a string
    /// buffer (not a cursor-based display), we need to actually remove the character.
    ///
    /// All other characters — including ANSI escape sequences, \r, \n — are passed
    /// through unchanged for the ANSIParser to handle.
    private func processTerminalOutput(_ text: String) {
        // Work on a local copy, then assign once to avoid flooding @Published
        // with per-character objectWillChange notifications (which can cause
        // SwiftUI to throttle updates, leaving the prompt un-rendered until
        // the next keystroke triggers a layout pass).
        var buffer = terminalOutput
        for char in text {
            if char == "\u{08}" {
                // Backspace: remove the last non-newline character
                if let last = buffer.last, last != "\n" {
                    buffer.removeLast()
                }
            } else {
                buffer.append(char)
            }
        }
        terminalOutput = buffer
    }

    // MARK: - Key Parsing

    /// Parses a private key string and returns the appropriate SSHAuthenticationMethod.
    /// Supports:
    /// - OpenSSH Ed25519: -----BEGIN OPENSSH PRIVATE KEY----- (ssh-ed25519)
    /// - OpenSSH RSA: -----BEGIN OPENSSH PRIVATE KEY----- (ssh-rsa)
    /// - PEM RSA (PKCS#1): -----BEGIN RSA PRIVATE KEY-----
    private static func parsePrivateKey(from keyString: String, username: String) throws -> SSHAuthenticationMethod {
        let trimmed = keyString.trimmingCharacters(in: .whitespacesAndNewlines)

        // OpenSSH format — detect key type from the binary content
        if trimmed.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----") {
            let keyData = try pemToDER(trimmed)
            let keyType = detectOpenSSHKeyType(keyData)

            switch keyType {
            case .ed25519:
                let ed25519Key = try parseOpenSSHEd25519(keyData)
                return .ed25519(username: username, privateKey: ed25519Key)
            case .rsa:
                let rsaKey = try Insecure.RSA.PrivateKey(sshRsa: trimmed)
                return .rsa(username: username, privateKey: rsaKey)
            case .unknown(let name):
                throw SSHError.keyParsingFailed("Unsupported key type: \(name)")
            }
        }

        // PEM PKCS#1 RSA format
        if trimmed.hasPrefix("-----BEGIN RSA PRIVATE KEY-----") {
            let derData = try pemToDER(trimmed)
            let rsaKey = try parseRSAPKCS1DER(derData)
            return .rsa(username: username, privateKey: rsaKey)
        }

        throw SSHError.keyParsingFailed("Unsupported key format. Use OpenSSH or PEM RSA format.")
    }

    /// Key types found in OpenSSH private key files
    private enum OpenSSHKeyType {
        case ed25519
        case rsa
        case unknown(String)
    }

    /// Detects the key type from OpenSSH binary data by scanning for key type strings
    private static func detectOpenSSHKeyType(_ data: Data) -> OpenSSHKeyType {
        let bytes = Array(data)
        // Search for "ssh-ed25519" or "ssh-rsa" in the binary data
        if let str = String(data: data, encoding: .ascii) {
            if str.contains("ssh-ed25519") { return .ed25519 }
            if str.contains("ssh-rsa") { return .rsa }
        }
        // Fallback: check raw bytes for known patterns
        let ed25519Marker: [UInt8] = Array("ssh-ed25519".utf8)
        for i in 0..<(bytes.count - ed25519Marker.count) {
            if Array(bytes[i..<(i + ed25519Marker.count)]) == ed25519Marker {
                return .ed25519
            }
        }
        return .unknown("unknown")
    }

    /// Parses an OpenSSH Ed25519 private key and returns a Curve25519.Signing.PrivateKey.
    /// OpenSSH format: "openssh-key-v1\0" + cipher + kdf + keys...
    private static func parseOpenSSHEd25519(_ data: Data) throws -> Curve25519.Signing.PrivateKey {
        let bytes = Array(data)
        var offset = 0

        // Verify magic: "openssh-key-v1\0"
        let magic = "openssh-key-v1\0"
        let magicBytes = Array(magic.utf8)
        guard bytes.count > magicBytes.count,
              Array(bytes[0..<magicBytes.count]) == magicBytes else {
            throw SSHError.keyParsingFailed("Invalid OpenSSH key magic")
        }
        offset = magicBytes.count

        // Skip ciphername (string)
        _ = try readOpenSSHString(bytes: bytes, offset: &offset)
        // Skip kdfname (string)
        _ = try readOpenSSHString(bytes: bytes, offset: &offset)
        // Skip kdfoptions (string)
        _ = try readOpenSSHString(bytes: bytes, offset: &offset)

        // Number of keys (uint32)
        guard offset + 4 <= bytes.count else {
            throw SSHError.keyParsingFailed("Truncated key data")
        }
        offset += 4 // skip number of keys

        // Skip public key blob (string)
        _ = try readOpenSSHString(bytes: bytes, offset: &offset)

        // Private key section (string containing the actual key data)
        let privateSection = try readOpenSSHString(bytes: bytes, offset: &offset)
        var privOffset = 0

        // Two uint32 check integers (must match)
        guard privateSection.count >= 8 else {
            throw SSHError.keyParsingFailed("Private section too short")
        }
        let check1 = readUInt32(privateSection, offset: &privOffset)
        let check2 = readUInt32(privateSection, offset: &privOffset)
        guard check1 == check2 else {
            throw SSHError.keyParsingFailed("Check integers mismatch — key may be encrypted. Encrypted keys are not supported.")
        }

        // Key type string (e.g. "ssh-ed25519")
        _ = try readOpenSSHString(bytes: privateSection, offset: &privOffset)

        // Ed25519 public key (32 bytes, as a string)
        _ = try readOpenSSHString(bytes: privateSection, offset: &privOffset)

        // Ed25519 private key (64 bytes: 32-byte seed + 32-byte public key)
        let privKeyData = try readOpenSSHString(bytes: privateSection, offset: &privOffset)
        guard privKeyData.count == 64 else {
            throw SSHError.keyParsingFailed("Ed25519 private key should be 64 bytes, got \(privKeyData.count)")
        }

        // The first 32 bytes are the seed (actual private key)
        let seed = Array(privKeyData[0..<32])
        return try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    }

    /// Reads an OpenSSH "string" (uint32 length + data)
    private static func readOpenSSHString(bytes: [UInt8], offset: inout Int) throws -> [UInt8] {
        guard offset + 4 <= bytes.count else {
            throw SSHError.keyParsingFailed("Truncated string length")
        }
        var lenOffset = offset
        let length = Int(readUInt32(bytes, offset: &lenOffset))
        offset = lenOffset
        guard offset + length <= bytes.count else {
            throw SSHError.keyParsingFailed("String data exceeds buffer (length=\(length))")
        }
        let data = Array(bytes[offset..<(offset + length)])
        offset += length
        return data
    }

    /// Reads a big-endian uint32
    private static func readUInt32(_ bytes: [UInt8], offset: inout Int) -> UInt32 {
        let value = UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
        offset += 4
        return value
    }

    /// Strips PEM headers/footers and base64-decodes to raw DER bytes
    private static func pemToDER(_ pem: String) throws -> Data {
        let lines = pem.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        let base64 = lines.joined()
        guard let data = Data(base64Encoded: base64) else {
            throw SSHError.keyParsingFailed("Invalid base64 encoding in PEM key")
        }
        return data
    }

    /// Parses a PKCS#1 DER-encoded RSA private key and extracts modulus, publicExponent, privateExponent.
    /// PKCS#1 RSAPrivateKey ::= SEQUENCE { version, modulus, publicExponent, privateExponent, ... }
    private static func parseRSAPKCS1DER(_ data: Data) throws -> Insecure.RSA.PrivateKey {
        let bytes = Array(data)
        var offset = 0

        // Parse outer SEQUENCE
        guard offset < bytes.count, bytes[offset] == 0x30 else {
            throw SSHError.keyParsingFailed("Expected SEQUENCE tag")
        }
        offset += 1
        _ = try readDERLength(bytes: bytes, offset: &offset)

        // Skip version INTEGER (should be 0)
        let _ = try readDERInteger(bytes: bytes, offset: &offset)

        // Read modulus (n)
        let modulusBytes = try readDERInteger(bytes: bytes, offset: &offset)

        // Read publicExponent (e)
        let pubExpBytes = try readDERInteger(bytes: bytes, offset: &offset)

        // Read privateExponent (d)
        let privExpBytes = try readDERInteger(bytes: bytes, offset: &offset)

        // Create BIGNUMs from raw bytes
        let modulus = CCryptoBoringSSL_BN_bin2bn(modulusBytes, modulusBytes.count, nil)!
        let publicExponent = CCryptoBoringSSL_BN_bin2bn(pubExpBytes, pubExpBytes.count, nil)!
        let privateExponent = CCryptoBoringSSL_BN_bin2bn(privExpBytes, privExpBytes.count, nil)!

        return Insecure.RSA.PrivateKey(
            privateExponent: privateExponent,
            publicExponent: publicExponent,
            modulus: modulus
        )
    }

    /// Reads a DER length field
    private static func readDERLength(bytes: [UInt8], offset: inout Int) throws -> Int {
        guard offset < bytes.count else {
            throw SSHError.keyParsingFailed("Unexpected end of DER data")
        }
        let first = bytes[offset]
        offset += 1

        if first < 0x80 {
            return Int(first)
        }

        let numLengthBytes = Int(first & 0x7F)
        guard numLengthBytes > 0, offset + numLengthBytes <= bytes.count else {
            throw SSHError.keyParsingFailed("Invalid DER length encoding")
        }

        var length = 0
        for i in 0..<numLengthBytes {
            length = (length << 8) | Int(bytes[offset + i])
        }
        offset += numLengthBytes
        return length
    }

    /// Reads a DER INTEGER and returns the raw unsigned bytes (leading zero stripped)
    private static func readDERInteger(bytes: [UInt8], offset: inout Int) throws -> [UInt8] {
        guard offset < bytes.count, bytes[offset] == 0x02 else {
            throw SSHError.keyParsingFailed("Expected INTEGER tag")
        }
        offset += 1

        let length = try readDERLength(bytes: bytes, offset: &offset)
        guard offset + length <= bytes.count else {
            throw SSHError.keyParsingFailed("INTEGER exceeds available data")
        }

        var intBytes = Array(bytes[offset..<(offset + length)])
        offset += length

        // Strip leading zero byte used for positive sign in ASN.1
        if intBytes.first == 0x00 && intBytes.count > 1 {
            intBytes.removeFirst()
        }

        return intBytes
    }

    // MARK: - Cleanup

    deinit {
        shellTask?.cancel()
    }
}
