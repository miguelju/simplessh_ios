# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

iOS SSH client app built with SwiftUI, SwiftData, and Citadel (pure Swift SSH library via Swift Package Manager). Targets iOS 17.0+. Uses Swift 6.0.

## Build & Run

```bash
# Open project
open simplessh.xcodeproj

# Build from command line (SPM packages resolve automatically)
xcodebuild -project simplessh.xcodeproj -scheme simplessh -sdk iphoneos build

# Run tests
xcodebuild -project simplessh.xcodeproj -scheme simplessh -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Face ID, Keychain, and SSH connectivity require a real device — simulator has limited functionality.

## Architecture

**Layered design: Views → Managers → Data Model → Citadel (SwiftNIO SSH)**

- **SSHManager** (`@MainActor`): Wraps Citadel's `SSHClient` for SSH sessions and interactive PTY shells. Uses Swift async/await for all SSH operations. Terminal I/O is streamed via `TTYStdinWriter` (input) and `AsyncSequence` (output).
- **ANSIParser**: Converts raw terminal output with ANSI escape codes into styled `AttributedString`. Supports 16/256/true color, bold, dim, italic, underline, reverse, strikethrough. Strips non-visual sequences (cursor movement, OSC). Accepts configurable default foreground color and font from terminal settings. Enables proper rendering of Oh My Zsh themes and colored output.
- **TerminalSettingsStore** (`@MainActor`, singleton): Persists terminal appearance preferences via `@AppStorage`. Stores selected theme (7 built-in presets + Custom) that bundles font family, font size, foreground color, and background color. Custom theme allows independent control of all settings. Used by `ANSIParser`, `SSHTerminalView`, and `SettingsView`.
- **KeychainManager** (singleton): Stores SSH private keys in iOS Keychain with optional biometric (`SecAccessControl`) protection. Keys are never stored in SwiftData.
- **SSHConnection** (SwiftData `@Model`): Persists connection metadata (name, host, username, port). Delegates key storage/retrieval to `KeychainManager`.
- **MigrationHelper**: One-time migration from older demo storage to Keychain-based storage.

**Views:**
- `ContentView` — connection list with swipe-to-delete, settings access
- `AddConnectionView` — connection creation form with validation
- `SSHTerminalView` — live SSH terminal with biometric auth prompt, direct keystroke input, settings access
- `TerminalKeyboardView` — UIKeyInput-based keyboard capture (UIViewRepresentable) with special keys toolbar
- `SettingsView` — terminal theme selection (7 presets + custom) with live preview

**SSH Library:** Citadel (SPM) — pure Swift SSH client built on Apple's SwiftNIO SSH. Supports modern key exchange algorithms (curve25519-sha256, diffie-hellman-group14-sha256, etc.). No Objective-C bridging required.

## Required Info.plist Entries

These are configured via `INFOPLIST_KEY_` build settings in the Xcode project (auto-generated Info.plist):

- `NSFaceIDUsageDescription` — "Authenticate to access SSH keys"
- `NSLocalNetworkUsageDescription` — "Connect to SSH servers on your local network"

## Entitlements

`simplessh/simplessh.entitlements` includes:
- `com.apple.security.app-sandbox` — App Sandbox enabled
- `com.apple.security.network.client` — Outgoing network connections (required for SSH)

## Key Constraints

- SSH keys are supported in three formats:
  - **OpenSSH Ed25519**: `-----BEGIN OPENSSH PRIVATE KEY-----` (ssh-ed25519) — parsed via custom OpenSSH binary format parser, extracts 32-byte seed for `Curve25519.Signing.PrivateKey`
  - **OpenSSH RSA**: `-----BEGIN OPENSSH PRIVATE KEY-----` (ssh-rsa) — handled natively by Citadel's `init(sshRsa:)`
  - **PEM RSA (PKCS#1)**: `-----BEGIN RSA PRIVATE KEY-----` — parsed via custom ASN.1 DER parser, extracts modulus/exponents for `Insecure.RSA.PrivateKey`
- Key type is auto-detected from the file content; the correct Citadel authentication method (`.ed25519()` or `.rsa()`) is selected automatically
- Encrypted private keys are not supported (key must have no passphrase)
- The bridging header (`simplessh-Bridging-Header.h`) is empty — Citadel is pure Swift

## Dependencies (Swift Package Manager)

- **Citadel** (0.9.x) — SSH client library (brings in SwiftNIO SSH, swift-crypto, BigInt, swift-log)

## Documentation Policy

After any major code change (adding/removing files, changing architecture, adding features, modifying data flow, or changing dependencies), update the relevant documentation files:

- `simplessh/APP_FLOW.md` — Application flow diagrams and screen descriptions
- `simplessh/FILE_STRUCTURE.md` — File listing and architecture layers
- `simplessh/IMPLEMENTATION_SUMMARY.md` — Feature summary and architecture overview
- `simplessh/README.md` — Project overview, features, and requirements
- `simplessh/QUICK_START.md` — Setup guide and troubleshooting
- `simplessh/PRODUCTION_IMPLEMENTATION_GUIDE.md` — Detailed technical guide

Only update docs that are affected by the change. Keep documentation concise and accurate.
