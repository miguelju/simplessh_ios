# SimpleSSH Application Flow

## App Startup

```
iOS launches app
    └── @main simplesshApp (simplesshApp.swift)
            ├── Creates ModelContainer with SSHConnection schema (SwiftData)
            └── body: WindowGroup
                    └── ContentView()
                            └── .modelContainer(sharedModelContainer)
                                  (injects SwiftData context into environment)
```

---

## Screen 1: Connection List (ContentView.swift)

```
ContentView
    ├── @Query fetches all SSHConnection objects from SwiftData (sorted by createdAt desc)
    ├── IF no connections → shows emptyStateView (icon + "Add Connection" button)
    └── IF connections exist → shows connectionsList
            └── ForEach connection:
                    └── ConnectionRowView (NavigationLink)
                            ├── Displays: name, username, serverIP, lastUsedAt
                            ├── Tap → navigates to SSHTerminalView(connection:)
                            ├── Swipe left → delete (removes Keychain key + SwiftData record)
                            └── Long press → context menu with Delete option
```

**User actions:**
- **Tap "+"** → presents `AddConnectionView` as a sheet
- **Tap a connection row** → navigates to `SSHTerminalView`
- **Swipe to delete** → calls `connection.deleteSSHKey()` then `modelContext.delete(connection)`

---

## Screen 2: Add Connection (AddConnectionView.swift)

```
AddConnectionView (presented as sheet)
    ├── Input fields:
    │     ├── Connection Name (TextField)
    │     ├── Server IP / Hostname (TextField)
    │     ├── Username (TextField)
    │     ├── Port (TextField, default "22")
    │     └── SSH Private Key (TextEditor, Ed25519 or RSA, OpenSSH or PEM format)
    ├── Biometric toggle (Face ID / Touch ID)
    └── Save button → saveConnection()
```

**Save flow:**
```
saveConnection()
    ├── Validates all fields (non-empty, valid port 1-65535)
    ├── Creates SSHConnection(name, serverIP, username, port, requiresBiometric)
    ├── connection.storeSSHKey(sshKey)
    │       └── KeychainManager.shared.storeSSHKey(key, id, requireBiometric)
    │               ├── Creates SecAccessControl with biometry+passcode
    │               ├── Deletes any existing key for this ID
    │               └── SecItemAdd() to iOS Keychain
    ├── modelContext.insert(connection)  — saves to SwiftData
    └── dismiss()
```

---

## Screen 3: SSH Terminal (SSHTerminalView.swift)

```
SSHTerminalView
    ├── @StateObject SSHManager (created fresh for each connection)
    ├── @ObservedObject TerminalSettingsStore.shared (font, colors)
    ├── @State parsedOutput: AttributedString (ANSI-parsed terminal content)
    ├── .task { connectToServer() }   ← runs when view appears
    └── Layout:
          ├── Terminal output (ScrollView + Text, styled per settings + ANSI)
          │     └── Bound to parsedOutput (ANSIParser with settings colors/font)
          ├── Keyboard capture (invisible UIKeyInput view, auto-focused when connected)
          │     └── Special keys toolbar above keyboard: ESC, TAB, CTRL, arrows, |, ~, -, /
          └── Toolbar: connection status + settings gear + disconnect button
```

### Connection Flow

```
connectToServer() (SSHTerminalView.swift)
    ├── IF requiresBiometric:
    │     └── KeychainManager.authenticateUserWithPasscode()
    │           └── LAContext.evaluatePolicy(.deviceOwnerAuthentication)
    │                 → Face ID / Touch ID / Passcode prompt
    │           IF denied → shows error, returns
    │
    ├── sshManager.connect(to: connection)  (SSHManager.swift)
    │     ├── KeychainManager.retrieveSSHKey(id)
    │     │     └── SecItemCopyMatching() — may trigger biometric prompt
    │     │
    │     ├── Parse SSH key (auto-detects type):
    │     │     ├── IF OpenSSH Ed25519 (ssh-ed25519):
    │     │     │     └── parseOpenSSHEd25519() → Curve25519.Signing.PrivateKey → .ed25519()
    │     │     ├── IF OpenSSH RSA (ssh-rsa):
    │     │     │     └── Insecure.RSA.PrivateKey(sshRsa:) → .rsa()
    │     │     └── IF PEM RSA (-----BEGIN RSA PRIVATE KEY-----):
    │     │           └── pemToDER() → parseRSAPKCS1DER() → .rsa()
    │     │
    │     ├── SSHClient.connect(host, port, authMethod, hostKeyValidator)
    │     │     └── Citadel establishes TCP + SSH handshake (async/await)
    │     │
    │     ├── client.onDisconnect { ... }  ← monitor for disconnection
    │     │
    │     └── [Background Task]: client.withPTY(ptyRequest) { output, writer in
    │           ├── Stores writer as _stdinWriter (for sendCommand)
    │           └── for try await event in output:
    │                 ├── .stdout(buffer) → terminalOutput += text
    │                 └── .stderr(buffer) → terminalOutput += text
    │
    └── connection.lastUsedAt = Date()   ← updates SwiftData
```

### When a User Types (Direct Keystroke Input)

```
User presses key on software/hardware keyboard
    └── TerminalKeyInputView (UIKeyInput) captures keystroke:
          ├── Printable chars → insertText() → UTF-8 bytes
          ├── Return → 0x0D (carriage return, PTY convention)
          ├── Backspace → deleteBackward() → 0x7F (DEL)
          ├── Arrow keys (hardware) → pressesBegan() → ANSI escape sequences
          ├── Ctrl+letter (hardware or toolbar) → control byte (0x01–0x1A)
          └── Special keys toolbar: ESC, TAB, CTRL, arrows, |, ~, -, /

    └── onInput callback → sshManager.sendRawData(data) (SSHManager.swift)
          ├── Guard: _stdinWriter exists + isConnected
          ├── Creates ByteBuffer with raw bytes
          └── writer.write(buffer) — sends to SSH server via Citadel

Server echoes input and sends output back
    └── withPTY output AsyncSequence receives it
          └── for try await event in output:
                └── Dispatches to MainActor → appends to terminalOutput
                      └── .onChange triggers ANSIParser.parse(terminalOutput)
                            └── parsedOutput updated (AttributedString with colors/styles)
                                  └── SwiftUI re-renders styled Text view
                                        └── ScrollView auto-scrolls
```

### Disconnect Flow

```
User taps "Disconnect" in toolbar OR view disappears (.onDisappear)
    └── sshManager.disconnect()
          ├── shellTask.cancel()        ← cancels PTY background task
          ├── _stdinWriter = nil
          ├── isConnected = false
          ├── terminalOutput += "[Connection closed]"
          └── Task { client.close() }   ← closes Citadel SSH session

User types "exit" + Return (keystrokes sent directly to PTY)
    └── Remote shell receives "exit\r" and closes
          └── PTY output stream ends → withPTY closure exits
                └── onDisconnect fires → isConnected = false
                      └── .onChange detects disconnection after prior connection
                            ├── Task.sleep(500ms)   ← brief delay
                            └── dismiss()           ← navigates back to connection list
```

---

## Data Layer

```
SSHConnection (@Model, SwiftData)
    ├── id: UUID (also used as Keychain identifier)
    ├── name, serverIP, username, port, createdAt, lastUsedAt, requiresBiometric
    ├── storeSSHKey()    → KeychainManager
    ├── retrieveSSHKey() → KeychainManager (triggers biometric)
    ├── deleteSSHKey()   → KeychainManager
    └── hasSSHKey()      → KeychainManager (no biometric prompt)

KeychainManager (singleton)
    ├── storeSSHKey()              → SecItemAdd with biometric access control
    ├── retrieveSSHKey()           → SecItemCopyMatching (triggers biometric)
    ├── retrieveSSHKeyWithoutAuth() → SecItemCopyMatching (kSecUseAuthenticationUIFail)
    ├── deleteSSHKey()             → SecItemDelete
    ├── updateSSHKey()             → SecItemUpdate
    ├── isBiometricAuthenticationAvailable() → LAContext.canEvaluatePolicy
    ├── biometricType()            → "Face ID" / "Touch ID" / "Optic ID" / "None"
    ├── authenticateUser()         → LAContext biometrics only
    └── authenticateUserWithPasscode() → LAContext biometrics + passcode fallback
```



