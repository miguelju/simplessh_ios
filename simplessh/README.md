# Simple SSH - iPhone SSH Terminal Client

A modern SSH client for iPhone, built with SwiftUI and Liquid Glass design principles. Connect to remote servers, manage SSH connections, and run commands in a full interactive terminal — all from your iPhone.

## Overview

Simple SSH is an iPhone app that provides a full-featured SSH terminal — connect to remote servers, execute commands in a live interactive shell, and manage multiple SSH connections. Designed exclusively for iPhone, it uses Apple's Liquid Glass design language and the Citadel SSH library for secure, key-based authentication.

## Features

### Liquid Glass Design
- Modern Material Effects with `.glassEffect()` modifier
- Interactive glass effects responsive to touch
- Color-tinted glass for visual hierarchy
- Smooth animations and fluid transitions

### SSH Connection Management
- Save multiple SSH server configurations
- Secure key storage in iOS Keychain (not in SwiftData)
- Biometric authentication (Face ID / Touch ID) for key access
- Connection details: hostname, username, SSH key (Ed25519 or RSA, OpenSSH or PEM format), port

### Real SSH Terminal
- Live terminal connected to remote SSH servers via Citadel (SwiftNIO SSH)
- Real-time output streaming via PTY (pseudo-terminal)
- Full ANSI color rendering (16, 256, and 24-bit true color)
- Styled text: bold, dim, italic, underline, reverse, strikethrough
- Oh My Zsh compatible — renders themed prompts, git status indicators, and Powerline symbols
- Direct keystroke input to PTY (real terminal experience)
- Special keys toolbar (ESC, TAB, CTRL, arrows) for software keyboard
- Typing `exit` closes the SSH session and returns to the connection list
- Connection status indicators

### Customizable Terminal Themes
- 7 built-in themes, each bundling font, size, and colors: Classic Green, Amber, Cyan, White, Solarized, Dracula, Oh My Zsh
- Oh My Zsh theme optimized for rendering Oh My Zsh shell configurations
- Custom theme with full control over font family, size, and colors
- Live preview in settings
- Preferences persist across app launches

## Screenshots

### Connection List (Empty State)
![Connection List - Empty](screenshots/connection_list_empty.png)

### Connection List (With Connections)
![Connection List - Populated](screenshots/connection_list_populated.png)

### Add Connection
![Add Connection](screenshots/add_connection.png)

### SSH Terminal
![SSH Terminal](screenshots/terminal_view.png)

### Settings
![Settings](screenshots/settings_view.png)

## Architecture

### Data Models
- **SSHConnection**: SwiftData model storing connection configuration (metadata only — keys in Keychain)

### Views
- **ContentView**: Main list showing all saved connections with swipe-to-delete
- **AddConnectionView**: Form for creating new connections with validation and biometric toggle
- **SSHTerminalView**: Production terminal with real SSH via Citadel
- **SettingsView**: Terminal appearance customization with live preview

### Managers
- **SSHManager**: SSH connection lifecycle, PTY shell sessions, command execution — all async/await
- **KeychainManager**: Secure key storage, biometric authentication, access control

### Utilities
- **ANSIParser**: Converts ANSI escape codes to styled `AttributedString` for terminal rendering (colors, bold, italic, underline, 256-color, true color)
- **TerminalSettingsStore**: Persists terminal appearance preferences (font, size, colors) via `@AppStorage`

### SSH Library
- **Citadel** (Swift Package Manager): Pure Swift SSH client built on SwiftNIO SSH
- Supports modern key exchange algorithms (curve25519-sha256, etc.)
- No Objective-C bridging required — fully native Swift

## How SSH Key Authentication Works

SSH (Secure Shell) supports two primary authentication methods: **password** and **public key**. This app exclusively uses **public key authentication**, which is the recommended and more secure approach.

### Why Keys Instead of Passwords?

Password authentication is vulnerable to brute-force attacks, credential stuffing, and phishing. Most security-conscious server administrators disable password authentication entirely. The [OpenSSH project](https://www.openssh.com/) and major hosting providers (AWS, GitHub, DigitalOcean) all recommend or require key-based authentication.

> **This app does not support password authentication by design.** You must use an SSH key pair to connect.

### How Public Key Authentication Works

1. **Key pair generation**: You generate a key pair on your local machine — a **private key** (secret, never shared) and a **public key** (placed on the server).
2. **Server configuration**: The public key is added to `~/.ssh/authorized_keys` on the remote server.
3. **Authentication handshake**: When connecting, the client proves it holds the private key by signing a challenge from the server. The server verifies the signature using the stored public key. The private key never leaves the client device.

This is based on asymmetric cryptography (also called public-key cryptography). For a detailed explanation, see:
- [OpenSSH Manual — ssh-keygen](https://man.openbsd.org/ssh-keygen.1) — official documentation for generating key pairs
- [SSH Protocol Architecture — RFC 4251](https://datatracker.ietf.org/doc/html/rfc4251) — the SSH protocol specification
- [Public Key Authentication — RFC 4252 Section 7](https://datatracker.ietf.org/doc/html/rfc4252#section-7) — the authentication protocol specification

### Generating an SSH Key Pair

```bash
# Ed25519 (recommended — fast, secure, compact)
ssh-keygen -t ed25519 -C "your_email@example.com"

# RSA (widely compatible — use 4096 bits minimum)
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

This creates two files (default locations):
- `~/.ssh/id_ed25519` (private key) — paste this into the app
- `~/.ssh/id_ed25519.pub` (public key) — add this to the server

### Installing the Public Key on the Server

```bash
# Copy public key to the remote server
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@server_ip

# Or manually append to authorized_keys
cat ~/.ssh/id_ed25519.pub | ssh user@server_ip "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

### Tested Key Formats

This app was tested with the following SSH key types and formats:

| Format | Header | Algorithm | Status |
|---|---|---|---|
| OpenSSH Ed25519 | `-----BEGIN OPENSSH PRIVATE KEY-----` | ssh-ed25519 | Tested |
| OpenSSH RSA | `-----BEGIN OPENSSH PRIVATE KEY-----` | ssh-rsa | Tested |
| PEM RSA (PKCS#1) | `-----BEGIN RSA PRIVATE KEY-----` | RSA | Tested |

The key format is auto-detected from the file content. **Encrypted (passphrase-protected) keys are not supported** — the private key must have no passphrase.

### References

- [OpenSSH](https://www.openssh.com/) — the most widely used SSH implementation
- [SSH Protocol Architecture — RFC 4251](https://datatracker.ietf.org/doc/html/rfc4251)
- [SSH Authentication Protocol — RFC 4252](https://datatracker.ietf.org/doc/html/rfc4252)
- [GitHub: Connecting with SSH](https://docs.github.com/en/authentication/connecting-to-github-with-ssh) — practical guide to SSH key setup
- [DigitalOcean: How to Set Up SSH Keys](https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys-on-ubuntu-20-04) — step-by-step tutorial

## Important Notes

### Security
- SSH keys stored in iOS Keychain (hardware-encrypted, device-only)
- Biometric authentication (Face ID/Touch ID) with passcode fallback
- Keys never stored in SwiftData or plaintext
- Automatic Keychain cleanup on connection deletion

### Network Permissions
- `NSLocalNetworkUsageDescription` — required for local network SSH connections
- `NSFaceIDUsageDescription` — required for biometric key access
- App Sandbox entitlement `com.apple.security.network.client` — required for outgoing TCP connections

## Getting Started

### Prerequisites

- **Xcode 26.0 beta or later** — required for Liquid Glass APIs (`.glassEffect()`) and iOS 26 SDK
- **Xcode 26.3 or later** — required if you want to use coding agents (Claude Agent, OpenAI Codex) in Xcode. See [Meet agentic coding in Xcode](https://developer.apple.com/videos/play/tech-talks/111428/) on Apple Developer.
- iOS 17.0 or later (deployment target)
- Swift 6.0
- Apple Developer account (free account works for device testing)
- Real device recommended (Keychain, Face ID, and SSH connectivity require a physical device)

### Clone and Build

```bash
# Clone the repository
git clone https://github.com/miguelju/simplessh_ios.git
cd simplessh_ios

# Open the project in Xcode
open simplessh.xcodeproj
```

Xcode will automatically resolve Swift Package Manager dependencies on first open. Then:

1. Select your target device (physical iPhone recommended) or simulator
2. Set your development team in **Signing & Capabilities** (Project > simplessh target > Signing & Capabilities)
3. Press **Cmd+R** to build and run

### Command-line Build (optional)

```bash
# Build for device
xcodebuild -project simplessh.xcodeproj -scheme simplessh -sdk iphoneos build

# Build for simulator
xcodebuild -project simplessh.xcodeproj -scheme simplessh -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Dependencies

All dependencies are managed via Swift Package Manager and resolve automatically when you open the project in Xcode.

### Direct Dependency

| Library | Version | License | Description |
|---|---|---|---|
| [Citadel](https://github.com/orlandos-nl/Citadel) | 0.9.2 | MIT | Pure Swift SSH client built on SwiftNIO SSH |

### Transitive Dependencies (pulled in by Citadel)

| Library | Version | License | Description |
|---|---|---|---|
| [swift-nio-ssh](https://github.com/Joannis/swift-nio-ssh) | 0.3.5 | Apache 2.0 | SSH protocol implementation (Citadel fork) |
| [swift-nio](https://github.com/apple/swift-nio) | 2.96.0 | Apache 2.0 | Event-driven network framework (Apple) |
| [swift-crypto](https://github.com/apple/swift-crypto) | 2.0.5 | Apache 2.0 | Cryptographic operations (Apple) |
| [BigInt](https://github.com/attaswift/BigInt) | 5.7.0 | MIT | Large number arithmetic for RSA |
| [swift-log](https://github.com/apple/swift-log) | 1.10.1 | Apache 2.0 | Logging framework (Apple) |
| [swift-atomics](https://github.com/apple/swift-atomics) | 1.3.0 | Apache 2.0 | Atomic operations (Apple) |
| [swift-collections](https://github.com/apple/swift-collections) | 1.4.1 | Apache 2.0 | Data structure extensions (Apple) |
| [swift-system](https://github.com/apple/swift-system) | 1.6.4 | Apache 2.0 | System interfaces (Apple) |
| [ColorizeSwift](https://github.com/mtynior/ColorizeSwift) | 1.7.0 | MIT | Terminal string colorization |

## Development

This application was developed using **Xcode Coding Assistant with Claude Agent** (Anthropic) as an educational example of AI-assisted iOS app development. It demonstrates what can be built using agentic coding tools directly within Xcode.

For more information on coding agents in Xcode, see:
- [Meet agentic coding in Xcode](https://developer.apple.com/videos/play/tech-talks/111428/) — Apple Tech Talk
- [Experiment with coding intelligence in Xcode 26](https://developer.apple.com/forums/thread/815576) — Apple Developer Forums

## License

This project is licensed under the [MIT License](LICENSE).
