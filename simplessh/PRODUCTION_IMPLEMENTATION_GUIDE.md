# Production SSH Implementation Guide

## Overview

This guide covers the SimpleSSH iPhone app architecture and setup for production use with:

1. Real SSH connections via Citadel (SwiftNIO SSH)
2. Secure Keychain storage for SSH keys
3. Biometric authentication (Face ID/Touch ID)
4. Comprehensive error handling
5. Full terminal emulation with PTY

## Setup

### Step 1: Package Dependencies

Citadel is configured as a Swift Package Manager dependency in the Xcode project. Packages resolve automatically when opening the workspace. If needed:

1. Open `simplessh.xcodeproj`
2. Xcode resolves SPM packages automatically
3. If issues: **File > Packages > Resolve Package Versions**

### Step 2: Info.plist Configuration

Info.plist keys are configured via `INFOPLIST_KEY_` build settings (auto-generated plist). The following keys are already set:

- `NSFaceIDUsageDescription` — "Authenticate to access SSH keys"
- `NSLocalNetworkUsageDescription` — "Connect to SSH servers on your local network"

### Step 3: Entitlements

The file `simplessh/simplessh.entitlements` includes:
- `com.apple.security.app-sandbox` — App Sandbox
- `com.apple.security.network.client` — Outgoing network connections (required for SSH)

### Step 4: Test on Real Device

**Important**: Testing on a real iOS device is essential because:
- Keychain access differs between simulator and device
- Biometric authentication requires physical device
- Network connectivity patterns are different

## Architecture Details

### SSH Manager (`SSHManager.swift`)

Uses Citadel's `SSHClient` for all SSH operations:

```swift
// Connect to server
let client = try await SSHClient.connect(
    host: host, port: port,
    authenticationMethod: .rsa(username: username, privateKey: rsaKey),
    hostKeyValidator: .acceptAnything(),
    reconnect: .never
)

// Interactive PTY shell
try await client.withPTY(ptyRequest) { output, writer in
    self._stdinWriter = writer  // Store for sendCommand()
    for try await event in output {
        // Stream stdout/stderr to UI
    }
}

// Send commands via stored writer
var buffer = ByteBufferAllocator().buffer(capacity: command.utf8.count)
buffer.writeString(command + "\n")
try await writer.write(buffer)
```

### SSH Key Parsing (Auto-Detected)

SSHManager's `parsePrivateKey()` auto-detects the key type and returns the correct `SSHAuthenticationMethod`:

**OpenSSH Ed25519** (`-----BEGIN OPENSSH PRIVATE KEY-----` with ssh-ed25519):
1. Parses the OpenSSH binary format (magic, cipher, kdf, public key, private section)
2. Verifies check integers match (rejects encrypted keys)
3. Extracts the 32-byte Ed25519 seed from the 64-byte private key field
4. Creates `Curve25519.Signing.PrivateKey(rawRepresentation: seed)`
5. Returns `.ed25519(username:privateKey:)`

**OpenSSH RSA** (`-----BEGIN OPENSSH PRIVATE KEY-----` with ssh-rsa):
1. Handled natively by Citadel's `Insecure.RSA.PrivateKey(sshRsa:)`
2. Returns `.rsa(username:privateKey:)`

**PEM RSA (PKCS#1)** (`-----BEGIN RSA PRIVATE KEY-----`):
1. Strips PEM headers/footers, base64-decodes to DER
2. Parses ASN.1 DER to extract modulus, publicExponent, privateExponent
3. Creates BoringSSL BIGNUMs via `CCryptoBoringSSL_BN_bin2bn`
4. Constructs `Insecure.RSA.PrivateKey(privateExponent:publicExponent:modulus:)`
5. Returns `.rsa(username:privateKey:)`

Encrypted (passphrase-protected) keys are not supported.

### Thread Safety

All SSH operations use Swift async/await:

```swift
@MainActor class SSHManager: ObservableObject {
    @Published private(set) var isConnected: Bool = false
    @Published var terminalOutput: String = ""

    // PTY shell runs in a background Task
    private var shellTask: Task<Void, Never>?

    // Writer stored as nonisolated(unsafe) for cross-actor access
    nonisolated(unsafe) private var _stdinWriter: TTYStdinWriter?
}
```

### Error Handling

```swift
enum SSHError: LocalizedError {
    case connectionFailed(String)
    case authenticationFailed(String)
    case keyParsingFailed(String)
    case networkError(String)
    case sessionNotConnected
    case commandExecutionFailed(String)
}
```

### Keychain Security (`KeychainManager.swift`)

```swift
// Access control with biometric protection
SecAccessControlCreateWithFlags(
    kCFAllocatorDefault,
    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    [.biometryCurrentSet, .or, .devicePasscode],
    &error
)
```

- Hardware-encrypted storage
- Device-only (no iCloud sync)
- Biometric required (configurable per connection)
- Automatic cleanup on connection deletion

## Advanced Features

### Edit Existing Connections (Implemented)

`AddConnectionView` supports both creating and editing connections via an optional `connectionToEdit` parameter:

```swift
// New connection (default)
AddConnectionView()

// Edit existing connection
AddConnectionView(connectionToEdit: connection)
```

**Edit mode flow:**
- `ContentView` toggles `editMode` via the toolbar ⋯ menu → Edit
- In edit mode, `ConnectionRowView` renders as a `Button` (instead of `NavigationLink`) that sets `connectionToEdit`
- `connectionToEdit` triggers a `sheet(item:)` presenting `AddConnectionView` in edit mode
- Fields are pre-filled via `.onAppear`; SSH key is optional (leave empty to keep existing)
- On save, existing connection properties are updated in-place (SwiftData auto-persists)

**Alternative:** Long-press context menu → Edit also sets `connectionToEdit` without entering edit mode.

### Dark Mode (Implemented)

App-wide appearance is controlled by `AppAppearance` enum in `TerminalSettings.swift`:

```swift
enum AppAppearance: String, CaseIterable {
    case system = "System"  // follows device setting
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? { ... }  // nil for system
}
```

- Persisted via `@AppStorage("app_appearance")` in `TerminalSettingsStore`
- Applied at the app root: `.preferredColorScheme(settings.appearance.colorScheme)`
- **Adaptive backgrounds**: Light mode uses `Color(.systemGroupedBackground)` for a clean look; dark mode uses a blue/purple gradient overlay
- **Adaptive glass tints**: Light mode uses subtle, low-opacity tints (0.15–0.4); dark mode uses full-opacity tints for vibrant effects
- **Adaptive icon colors**: Icons use `Color.accentColor` in light mode, `Color.white` in dark mode for proper contrast against glass
- Terminal view is intentionally independent — it uses its own theme colors

### Terminal Appearance Settings (Implemented)

Terminal appearance is fully customizable via `SettingsView.swift` and `TerminalSettings.swift`:

- **Unified themes**: 7 built-in themes (Classic Green, Amber, Cyan, White, Solarized, Dracula, Oh My Zsh) + Custom, each bundling font family, font size, and colors
- **Oh My Zsh theme**: Optimized for Oh My Zsh shell configurations (Menlo 13pt)
- **Custom theme**: Independent font family picker, size slider, and `ColorPicker` for text and background
- **Live preview**: Settings view shows a terminal preview reflecting selections in real-time
- **Persistence**: All settings stored via `@AppStorage` (persists across app launches)
- **Access**: Settings gear icon in both the connection list and terminal view toolbars
- ANSI color codes from the server still override the default text color when present

### ANSI Color Support (Implemented)

Full ANSI escape code rendering is implemented in `ANSIParser.swift`. The parser converts raw terminal output into styled `AttributedString` supporting:

- **16 standard colors** (SGR 30-37, 40-47, 90-97, 100-107)
- **256-color palette** (SGR 38;5;N, 48;5;N) — 6x6x6 color cube + grayscale ramp
- **24-bit true color** (SGR 38;2;R;G;B, 48;2;R;G;B)
- **Text styles**: bold, dim, italic, underline, reverse video, strikethrough
- **Non-visual stripping**: cursor movement, OSC (terminal title), character set designation
- **Oh My Zsh compatible**: renders themed prompts, git status, Powerline symbols

### Multiple Sessions

```swift
class SSHSessionPool: ObservableObject {
    @Published var sessions: [UUID: SSHManager] = [:]

    func createSession(for connection: SSHConnection) -> SSHManager {
        let manager = SSHManager()
        sessions[connection.id] = manager
        return manager
    }
}
```

### SFTP Support

Citadel includes SFTP support:
```swift
let sftp = try await client.openSFTP()
// Use sftp for file operations
```

## Troubleshooting

### "No such module 'Citadel'"
- Wait for SPM to finish resolving
- File > Packages > Resolve Package Versions
- Clean build folder (Cmd+Shift+K)

### "Connection timeout"
- Check network connectivity
- Verify SSH server is running on target
- Check firewall settings
- Ensure device and server on same network

### "Authentication failed"
- Verify key format (Ed25519 or RSA, in OpenSSH or PEM format)
- Check public key is in authorized_keys on the server
- Ensure username is correct
- Encrypted (passphrase-protected) keys are not supported — regenerate without a passphrase if needed

## License Considerations

- **Citadel**: MIT License
- **SwiftNIO SSH**: Apache 2.0
- **swift-crypto**: Apache 2.0

Include license attributions in your app's About screen.
