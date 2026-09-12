# SimpleSSH for iPhone - File Structure

```
simplessh/
│
├── App/
│   ├── simplesshApp.swift                    # App entry point, SwiftData setup
│   └── FontRegistrar.swift                   # Registers bundled Nerd Fonts (MesloLGS NF) at launch via Core Text
│
├── Hosts/
│   ├── SSHConnection.swift                   # SwiftData model (keys in Keychain)
│   ├── ContentView.swift                     # Main connection list (List + value-based navigation), edit mode
│   └── AddConnectionView.swift               # Add/edit connection form with Keychain integration
│
├── Terminal/
│   ├── SSHManager.swift                      # Citadel SSH client, PTY shell, Ed25519/RSA key parser; owns TerminalEmulator
│   ├── TerminalEmulator.swift                # Stateful VT100/xterm emulator: screen grid, cursor, scrollback, alt-screen → AttributedString
│   ├── SSHTerminalView.swift                 # Terminal view with real SSH via Citadel
│   └── TerminalKeyboardView.swift            # UIKeyInput keyboard capture for direct PTY input
│
├── Security/
│   ├── KeychainManager.swift                 # Keychain storage & biometrics
│   └── MigrationHelper.swift                 # Migration utilities & UI (unused; removed in roadmap item A2)
│
├── Settings/
│   ├── TerminalSettings.swift                # AppAppearance + TerminalFont (incl. bundled MesloLGS NF) + theme model (@AppStorage)
│   └── SettingsView.swift                    # App appearance + terminal theme settings with live preview
│
├── Resources
│   ├── Assets.xcassets/                      # App icon, accent colour
│   └── Fonts/                                # MesloLGS NF (Regular/Bold) — Nerd Font for prompt/Powerline icons
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
└── Documentation
    ├── README.md                             # Project overview
    ├── IMPLEMENTATION_SUMMARY.md             # Feature & architecture summary
    ├── PRODUCTION_IMPLEMENTATION_GUIDE.md    # Detailed setup & advanced features
    ├── QUICK_START.md                        # 5-minute setup guide
    ├── FILE_STRUCTURE.md                     # This file
    └── APP_FLOW.md                           # Application flow diagrams
```

---

## Architecture Layers

### Layer 1: UI (SwiftUI)
```
ContentView.swift           → Connection list, navigation, edit mode, settings access
AddConnectionView.swift     → Add/edit connection form with biometric toggle, saves to Keychain
SSHTerminalView.swift   → Live terminal, PTY output, direct keystroke input, settings access
SettingsView.swift          → Unified theme picker (font, size, colors) with live preview
```

### Layer 2: Business Logic
```
SSHManager.swift            → Citadel SSH client, PTY sessions, key parsing
KeychainManager.swift       → Secure storage, biometric auth, access control
TerminalEmulator.swift      → VT100/xterm emulator: grid, cursor, scrollback, alt-screen → styled AttributedString
TerminalSettingsStore       → App appearance mode, font, size, color preferences (@AppStorage)
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
2. **TerminalEmulator.swift** — VT100/xterm screen emulation (scrollback, alt-screen, Oh My Zsh / Powerlevel prompts)
3. **KeychainManager.swift** — Security implementation
4. **SSHTerminalView.swift** — Terminal UI

### Reference:
4. **simplessh.entitlements** — App Sandbox + network permissions
5. **SSHConnection.swift** — Data model with Keychain helpers
