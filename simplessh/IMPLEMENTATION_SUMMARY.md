# SimpleSSH - Implementation Summary

## What Was Implemented

A **production-ready SSH client for iPhone** with the following features:

### 1. Real SSH Library Integration - Citadel

- Pure Swift SSH client built on Apple's SwiftNIO SSH
- Supports modern key exchange algorithms (curve25519-sha256, diffie-hellman-group14-sha256)
- Swift Package Manager integration (no bridging headers needed)
- Async/await API with real-time terminal streaming
- Actively maintained

**File:** `SSHManager.swift`

**Key Features:**
```swift
// Async/await SSH connection via Citadel
try await sshManager.connect(to: connection)

// Interactive PTY shell with real-time streaming
try await client.withPTY(ptyRequest) { output, writer in
    for try await event in output { /* stream to UI */ }
}

// Command execution
try await sshManager.sendCommand("ls -la")
```

### 2. Edit Existing Connections

**Files:** `ContentView.swift`, `AddConnectionView.swift`

- Edit connection details (name, host, username, port, biometric setting) after creation
- Two ways to access edit functionality:
  - **Edit mode**: Toolbar ⋯ menu → Edit, then tap a connection to open its details
  - **Context menu**: Long-press any connection → Edit (no need to enter edit mode)
- `AddConnectionView` serves dual purpose: creating new connections and editing existing ones
- SSH key is optional when editing — leave empty to keep the existing key, or paste a new one to replace it
- Visual feedback: pencil icon on rows in edit mode, chevron in normal mode

### 3. iOS Keychain Storage

**File:** `KeychainManager.swift`

- SSH keys stored in iOS Keychain (not SwiftData)
- Keys never stored in plaintext
- Device-only storage (no iCloud sync)
- Biometric access control (Face ID / Touch ID)
- Automatic cleanup on connection deletion

### 4. Biometric Authentication

**Files:** `KeychainManager.swift`, `AddConnectionView.swift`, `SSHTerminalView.swift`

- Face ID and Touch ID support
- Passcode fallback
- Per-connection toggle
- Automatic prompt before SSH connection

### 5. SSH Key Format Support (Auto-Detected)

**File:** `SSHManager.swift`

- **OpenSSH Ed25519**: `-----BEGIN OPENSSH PRIVATE KEY-----` (ssh-ed25519) — custom OpenSSH binary parser extracts the 32-byte Ed25519 seed and creates `Curve25519.Signing.PrivateKey`. Auth via `.ed25519()`
- **OpenSSH RSA**: `-----BEGIN OPENSSH PRIVATE KEY-----` (ssh-rsa) — handled natively by Citadel's `init(sshRsa:)`. Auth via `.rsa()`
- **PEM RSA (PKCS#1)**: `-----BEGIN RSA PRIVATE KEY-----` — custom ASN.1 DER parser extracts modulus, public exponent, and private exponent, then creates BoringSSL BIGNUMs for Citadel's `Insecure.RSA.PrivateKey`. Auth via `.rsa()`
- Key type is auto-detected from the binary content; the correct authentication method is selected automatically
- Encrypted (passphrase-protected) keys are not supported

### 6. Full Terminal Emulation with ANSI Color Support

**Files:** `SSHTerminalView.swift`, `SSHManager.swift`, `ANSIParser.swift`

- Real-time output streaming via `AsyncSequence`
- Direct keystroke input via `UIKeyInput` → `sendRawData` → `TTYStdinWriter` (each key sent immediately)
- Special keys toolbar above software keyboard (ESC, TAB, CTRL, arrows, pipe, tilde)
- PTY allocation with xterm-256color terminal type
- **Full ANSI escape code rendering** via `ANSIParser`:
  - 16 standard colors, 256-color palette, 24-bit true color (RGB)
  - Bold, dim, italic, underline, reverse video, strikethrough
  - Strips non-visual sequences (cursor movement, OSC/terminal title)
  - Accepts configurable default foreground color and font from terminal settings
- Oh My Zsh compatible — renders themed prompts, git branch indicators, Powerline symbols
- Auto-scrolling terminal output
- Connection status indicators

### 7. Dark Mode Support

**Files:** `TerminalSettings.swift`, `SettingsView.swift`, `simplesshApp.swift`, `ContentView.swift`, `AddConnectionView.swift`

- Three appearance modes: **System** (follows device setting), **Light**, and **Dark**
- `AppAppearance` enum with `.colorScheme` computed property maps to SwiftUI's `ColorScheme?`
- Setting persisted via `@AppStorage("app_appearance")` in `TerminalSettingsStore`
- Applied at the app root via `.preferredColorScheme()` in `simplesshApp`
- All UI views use adaptive colors (`.primary`, `.secondary`) instead of hardcoded `.white`
- **Adaptive backgrounds**: Light mode uses clean `Color(.systemGroupedBackground)`; dark mode uses blue/purple gradient overlay on `Color(.systemBackground)`
- **Adaptive glass tints**: Light mode uses subtle, low-opacity tints (0.15–0.4); dark mode uses full-opacity tints for vibrant glass effects
- **Adaptive icon colors**: Icons use `Color.accentColor` in light mode and `Color.white` in dark mode for proper contrast against glass backgrounds
- Terminal view is unaffected — it uses its own theme colors from `TerminalSettingsStore`

### 8. Customizable Terminal Themes

**Files:** `SettingsView.swift`, `TerminalSettings.swift`

- **Unified themes** (7 presets + custom): Each theme bundles font family, font size, foreground color, and background color
  - Classic Green (System Mono 14pt), Amber (Courier 14pt), Cyan (SF Mono 14pt), White (Menlo 14pt), Solarized (Menlo 14pt), Dracula (SF Mono 14pt), Oh My Zsh (Menlo 13pt)
  - Custom mode with independent font family picker, size slider, and `ColorPicker` for foreground and background
- **Oh My Zsh theme**: Optimized for rendering Oh My Zsh shell configurations with appropriate font and colors
- **Live preview**: Settings view shows a terminal preview reflecting current selections
- **Persistence**: All preferences saved via `@AppStorage` (survives app launches)
- **Integration**: Settings accessible from both connection list and terminal view toolbars
- ANSI color codes from the server still override the default color when present

---

## Architecture Overview

```
UI Layer (SwiftUI)
  ContentView → SSHTerminalView / AddConnectionView (add or edit)
       │                                    │
       ▼                                    ▼
  SSHManager                         KeychainManager
  - Citadel SSHClient               - Key storage
  - PTY shell sessions              - Biometric auth
  - Async command execution          - Access control
       │
       ▼
  Citadel (SwiftNIO SSH)
  - Modern SSH protocol
  - Key exchange & auth
  - Channel management
       │
       ▼
  SSH Server (Remote)

Data Storage:
  SwiftData                          iOS Keychain
  - Connection metadata              - SSH private keys
  - Server details                   - Biometric protection
  - Timestamps                       - Device-only
```

### Threading Model

```
Main Actor (UI)
    ├── @MainActor SSHManager @Published properties
    ├── SwiftUI view updates
    └── User interactions

NIO Event Loop (Background)
    ├── Citadel SSH operations
    ├── Network I/O
    ├── PTY output streaming
    └── Command sending

Keychain (Sync)
    ├── Biometric prompts (main thread)
    └── Secure storage operations
```

---

## Dependencies

Managed via Swift Package Manager:

| Package | Version | Purpose |
|---------|---------|---------|
| Citadel | 0.9.x | SSH client library |
| SwiftNIO SSH | 0.3.x | SSH protocol (via Citadel) |
| swift-crypto | 2.x | Cryptographic operations |
| BigInt | 5.x | Large number arithmetic |
| swift-log | 1.x | Logging |
| swift-nio | 2.x | Network I/O |

---

## Device Requirements

- **iOS 17.0+**
- **Real device required** for: Keychain, biometric auth, SSH connectivity
