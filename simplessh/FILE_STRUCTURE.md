# SimpleSSH for iPhone - File Structure

```
simplessh/
│
├── Core Application Files
│   ├── simplesshApp.swift                    # App entry point, SwiftData setup
│   └── ContentView.swift                     # Main connection list
│
├── Security & Authentication
│   ├── KeychainManager.swift                 # Keychain storage & biometrics
│   └── SSHConnection.swift                   # SwiftData model (keys in Keychain)
│
├── SSH Functionality
│   ├── SSHManager.swift                      # Citadel SSH client, PTY shell, Ed25519/RSA key parser
│   ├── SSHTerminalView.swift             # Terminal view with real SSH via Citadel
│   └── ANSIParser.swift                      # ANSI escape code → AttributedString (colors, styles)
│
├── UI Components
│   ├── AddConnectionView.swift               # Connection form with Keychain integration
│   ├── SettingsView.swift                    # Terminal appearance settings with live preview
│   ├── TerminalSettings.swift                # Settings model (@AppStorage persistence)
│   ├── TerminalKeyboardView.swift            # UIKeyInput keyboard capture for direct PTY input
│   └── MigrationHelper.swift                 # Migration utilities & UI
│
├── Configuration
│   ├── simplessh.entitlements                # App Sandbox + network.client entitlement
│   ├── Info-plist-additions.xml              # Reference for Info.plist keys
│   └── simplessh-Bridging-Header.h           # Empty (Citadel is pure Swift)
│
├── Dependencies (Swift Package Manager)
│   └── Citadel (0.9.x)                      # Resolved by Xcode automatically
│       ├── SwiftNIO SSH                      # SSH protocol
│       ├── swift-crypto                      # Cryptography
│       ├── BigInt                            # RSA math
│       └── swift-log                         # Logging
│
├── Documentation
│   ├── README.md                             # Project overview
│   ├── IMPLEMENTATION_SUMMARY.md             # Feature & architecture summary
│   ├── PRODUCTION_IMPLEMENTATION_GUIDE.md    # Detailed setup & advanced features
│   ├── QUICK_START.md                        # 5-minute setup guide
│   ├── FILE_STRUCTURE.md                     # This file
│   └── APP_FLOW.md                           # Application flow diagrams
│
└── Tests
    ├── simplesshTests/                       # Unit tests
    ├── simplesshUITests/                     # UI tests
    └── simplesshUITestsLaunchTests/          # Launch tests
```

---

## Architecture Layers

### Layer 1: UI (SwiftUI)
```
ContentView.swift           → Connection list, navigation, settings access
AddConnectionView.swift     → Form with biometric toggle, saves to Keychain
SSHTerminalView.swift   → Live terminal, PTY output, direct keystroke input, settings access
SettingsView.swift          → Unified theme picker (font, size, colors) with live preview
```

### Layer 2: Business Logic
```
SSHManager.swift            → Citadel SSH client, PTY sessions, key parsing
KeychainManager.swift       → Secure storage, biometric auth, access control
ANSIParser.swift            → ANSI escape codes → styled AttributedString
TerminalSettingsStore       → Font, size, color preferences (@AppStorage)
```

### Layer 3: Data Models
```
SSHConnection.swift         → SwiftData model with Keychain integration
```

### Layer 4: SSH Library (Citadel via SPM)
```
Citadel                     → Pure Swift SSH client
  └── SwiftNIO SSH          → SSH protocol implementation
      └── swift-crypto      → Cryptographic primitives
```

---

## Key Files to Review

### Must Review:
1. **SSHManager.swift** — Core SSH logic, Ed25519/RSA key parsers, PTY shell
2. **ANSIParser.swift** — ANSI color/style rendering for Oh My Zsh compatibility
3. **KeychainManager.swift** — Security implementation
4. **SSHTerminalView.swift** — Terminal UI

### Reference:
4. **simplessh.entitlements** — App Sandbox + network permissions
5. **SSHConnection.swift** — Data model with Keychain helpers
