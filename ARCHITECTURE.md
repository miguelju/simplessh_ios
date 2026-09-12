# Architecture

How Simple SSH is put together. Read this before changing data flow, the
terminal, or key handling. Feature status and planned work are in
[`ROADMAP.md`](ROADMAP.md).

## Layers

```
SwiftUI views  →  managers (SSHManager, TerminalSettingsStore)
               →  data (SSHConnection in SwiftData; private keys behind KeyStore → KeychainManager)
               →  Citadel (SwiftNIO SSH)  →  remote sshd
```

## Source map

```
simplessh/
├── App/
│   ├── simplesshApp.swift        @main; builds the SwiftData ModelContainer, registers fonts,
│   │                             applies the chosen colour scheme
│   └── FontRegistrar.swift       Registers bundled MesloLGS NF (Regular/Bold) via Core Text
├── Hosts/
│   ├── SSHConnection.swift       @Model: name, serverIP, username, port, createdAt, lastUsedAt,
│   │                             requiresBiometric. No key logic; the key lives in a KeyStore under id
│   ├── ContentView.swift         Host list (List + value-based NavigationLink), edit mode,
│   │                             context menu, swipe-to-delete
│   └── AddConnectionView.swift   Add/edit form, validation, isValidHost(), InputFieldView
├── Terminal/
│   ├── SSHManager.swift          @MainActor ObservableObject: connect, PTY shell task, stdin writer,
│   │                             key parsing, coalesced rendering
│   ├── TerminalEmulator.swift    Stateful VT100/xterm emulator → AttributedString
│   ├── SSHTerminalView.swift     Terminal screen: output, hidden keyboard capture, status pill
│   └── TerminalKeyboardView.swift TerminalTextField (UITextField subclass) + TerminalKeyboardCapture
│                                 (UIViewRepresentable); accessory toolbar; hardware-key mapping
├── Security/
│   ├── KeyStore.swift            KeyStore protocol (store/retrieve/delete by id) + the
│   │                             `\.keyStore` environment entry, defaulting to KeychainManager.shared
│   └── KeychainManager.swift     Keychain CRUD with SecAccessControl (conforms to KeyStore);
│                                 LocalAuthentication helpers
├── Settings/
│   ├── TerminalSettings.swift    AppAppearance, TerminalFont, TerminalTheme, TerminalSettingsStore
│   └── SettingsView.swift        Appearance + theme pickers with live preview
├── Assets.xcassets/              App icon, accent colour
├── Fonts/                        MesloLGS-NF-Regular.ttf, MesloLGS-NF-Bold.ttf
├── screenshots/                  Images used by README.md
└── simplessh.entitlements        App Sandbox + network.client
```

```
simplesshTests/                   Unit-test bundle (Swift Testing), hosted by the app
├── TerminalEmulatorTests.swift   Grid, cursor, scrollback, alt screen, query replies, split feeds
├── PrivateKeyParsingTests.swift  Accepted formats and every rejection path of parsePrivateKey
├── HostValidationTests.swift     isValidHost accept/reject tables
├── SSHManagerTests.swift         connect() against an in-memory KeyStore; render-theme changes
└── Support/
    ├── TestKeys.swift            Generates Ed25519 (CryptoKit) and RSA (Security) keys at test
    │                             time and serialises them as OpenSSH / PKCS#1 text
    └── InMemoryKeyStore.swift    Dictionary-backed KeyStore
```

Xcode uses synchronized root groups for `simplessh/` and `simplesshTests/`, so
new files under either are picked up without editing the project. The shared
scheme `simplessh` builds the app and runs the test bundle. There is no bridging
header; Citadel is pure Swift.

## Screens and flows

### Startup

`simplesshApp` creates a `ModelContainer` for `SSHConnection`, calls
`FontRegistrar.registerBundledFonts()` (runtime Core Text registration, because
the generated Info.plist makes `UIAppFonts` awkward), observes
`TerminalSettingsStore.shared`, and shows `ContentView` with
`.preferredColorScheme(settings.appearance.colorScheme)` (`nil` = follow system).

### Host list (`ContentView`)

- `@Query` sorted by `createdAt` descending. (Roadmap E2 changes this to last use.)
- Rows are `ConnectionRowView`. The `NavigationLink(value:)` sits in the row
  background so the List does not draw a second chevron; the single
  `.navigationDestination(for: SSHConnection.self)` on the stack resolves it.
  Value-based navigation is what makes tapping *any* row work reliably.
- The view is a `List` (not a `ScrollView`) because `.swipeActions` only work
  inside a List; list chrome is hidden so the glass cards show.
- Edit mode (toolbar ⋯ → Edit) turns rows into buttons that open the edit sheet.
  Long-press offers Edit and Delete without entering edit mode.
- Delete calls `connection.deleteSSHKey()` and then `modelContext.delete`.

### Add / edit host (`AddConnectionView`)

Same view for both modes; `connectionToEdit == nil` means create. Fields are
pre-filled in `.onAppear` when editing, and the key field stays empty (leave it
empty to keep the existing key).

Save order: validate name → trim and validate host (`isValidHost`: IPv4 with four
0–255 octets, IPv6 via `IPv6Address`, or DNS labels; rejects `..`, leading or
trailing dots, whitespace) → username → key (required only when creating) →
port 1–65535. On create, the key is stored in the Keychain **before** the record
is inserted, so a Keychain failure leaves no orphan host.

### Terminal (`SSHTerminalView`)

Layout is a `ZStack`: the rendered screen in a `ScrollView`, plus a 1×1,
invisible `TerminalKeyboardCapture` that holds first responder while connected.
`.task` runs `connectToServer()`; `.onDisappear` disconnects (roadmap D5 changes
this so sessions survive navigation).

Connect flow:

```
connectToServer()
 ├─ if requiresBiometric: KeychainManager.authenticateUserWithPasscode(reason)
 │     LAContext.evaluatePolicy(.deviceOwnerAuthentication)   ← Face ID / passcode
 ├─ sshManager.connect(to:keyStore:)          ← keyStore comes from the view's environment
 │   ├─ terminal.reset(); render
 │   ├─ keyStore.retrieveSSHKey(id)          ← Keychain SecItemCopyMatching; may prompt again (roadmap C3)
 │   ├─ parsePrivateKey() → SSHAuthenticationMethod (see Key parsing)
 │   ├─ SSHClient.connect(host, port, authenticationMethod, hostKeyValidator: .acceptAnything(), reconnect: .never)
 │   ├─ client.onDisconnect → isConnected = false, "[Connection closed]"
 │   └─ shellTask = Task { client.withPTY(term: "xterm-256color", 80×24) { output, writer in
 │          _stdinWriter = writer
 │          for try await event in output { processTerminalOutput(text) }   // stdout and stderr
 │      } }
 └─ connection.lastUsedAt = Date(); modelContext.save()
```

`hostKeyValidator: .acceptAnything()` is a known gap (roadmap C1). The PTY size
is fixed at 80×24 (roadmap D1).

Output path: `processTerminalOutput` feeds the bytes to `TerminalEmulator`,
writes back any query reply the emulator queued (`drainReply()`), then calls
`scheduleRender()`. **Rendering is coalesced**: the first call in a run-loop hop
schedules one `Task` that renders the screen into `renderedScreen` and bumps
`outputVersion` once. Driving SwiftUI from a high-frequency `onChange` made it
drop renders, which is why the prompt used to appear only after a keystroke.
The view shows `renderedScreen` directly and scrolls to the bottom on
`outputVersion`.

Input path:

```
key press → TerminalTextField / Coordinator.textField(_:shouldChangeCharactersIn:)
  printable → UTF-8 bytes          return → 0x0D          backspace → 0x7F
  ctrl toggle + letter → 0x01–0x1A  hardware arrows/F-keys/ctrl → pressesBegan → escape sequences
  accessory toolbar: esc tab ctrl ↑ ↓ ← → | ~ - /
→ onInput(Data) → SSHManager.sendRawData → TTYStdinWriter.write
```

The field always holds a single space and rejects every change (`return false`)
so iOS keeps firing delete events and no text accumulates. A `UITextField` is
used rather than bare `UIKeyInput` because it handles the predictive bar, smart
punctuation and double-character edge cases.

Disconnect: the toolbar button or `onDisappear` cancels `shellTask`, drops the
writer, flags disconnected and closes the client. When the remote shell exits,
`onDisconnect` fires; the view then waits 500 ms and dismisses (roadmap C6
replaces this with a "session ended" bar).

### Settings (`SettingsView`)

Appearance (System/Light/Dark) and theme pickers bound to
`TerminalSettingsStore`. Every preset uses MesloLGS NF at 14 pt (Oh My Zsh at
13 pt) so Powerline glyphs render; Custom exposes font family, size slider and
two `ColorPicker`s. `TerminalSettingsStore.renderTheme` snapshots the active
colours and fonts as an `Equatable` `TerminalRenderTheme`; `SSHTerminalView`
observes the store and assigns the snapshot to `sshManager.renderTheme`
whenever it changes (including Custom font/colour edits), which triggers one
coalesced render. `SSHManager` never reads the settings store.

## Terminal emulator

`TerminalEmulator` is a `final class` with an 80×24 grid of `Cell` (character +
`Style`), a cursor, a scroll region, a 2,000-line scrollback and an alternate
screen. `feed(_:)` iterates **Unicode scalars, not Characters** (Swift merges
`\r\n` into one grapheme, which would break CR/LF handling) through a persistent
state machine (`ground / esc / csi / osc / charset`), so escape sequences split
across network reads are handled.

Supported: CR, LF/VT/FF, BS, TAB, BEL; DECSC/DECRC, RI, IND, NEL, RIS; CSI
cursor moves (CUU/CUD/CUF/CUB/CNL/CPL/CHA/VPA/CUP), ED/EL/ECH, IL/DL/ICH/DCH,
DECSTBM, SCOSC/SCORC; SGR 0–4, 7, 9, 21–24, 27, 29, 30–37/39, 40–47/49, 90–97, 100–107,
38;5/48;5 (256-colour), 38;2/48;2 (true colour); private modes 7 (autowrap) and
47/1047/1049 (alternate screen); OSC 10/11/12 colour queries. Replies queued for
DSR 5/6, DA, XTWINOPS 14/16/18 and XTVERSION are returned by `drainReply()`.

`render(...)` produces an `AttributedString` from scrollback + screen (or just
the alternate screen), trimming trailing blank lines and trailing blank cells,
merging runs of identical style, resolving reverse video and dim against the
theme defaults. The cursor is not drawn yet (roadmap D2), and the whole
scrollback is re-rendered on every batch (roadmap D3).

Read-only inspection accessors (`cursorRow`/`cursorCol`, `isAlternateScreenActive`,
`scrollbackLineCount`, `scrollTop`/`scrollBottom`, `cell(row:col:)`, `lineText`,
`screenText`, `scrollbackLineText`) expose state for the tests and for the
cursor rendering planned in D2. Nothing else reads them.

## Key parsing (`SSHManager.parsePrivateKey`)

`parsePrivateKey(_:)` turns key text into a `ParsedPrivateKey` (`.ed25519` or
`.rsa`); the private `parsePrivateKey(from:username:)` wraps that in a Citadel
`SSHAuthenticationMethod`. For OpenSSH containers the algorithm is read from the
public-key blob (`detectOpenSSHKeyType`, a bounds-checked walk of magic, cipher,
kdf, key count, blob), so a truncated file throws and an unsupported algorithm
is reported by name.

| Input | Path | Result |
|---|---|---|
| `-----BEGIN OPENSSH PRIVATE KEY-----`, blob type `ssh-ed25519` | Custom parser: private section; check ints must match (else the key is encrypted); 64-byte private field → first 32 bytes are the seed → `Curve25519.Signing.PrivateKey` | `.ed25519` |
| Same header, blob type `ssh-rsa` | Citadel `Insecure.RSA.PrivateKey(sshRsa:)` | `.rsa` |
| `-----BEGIN RSA PRIVATE KEY-----` | PEM → DER, minimal ASN.1 walk for modulus, public and private exponent → BoringSSL BIGNUMs → `Insecure.RSA.PrivateKey` | `.rsa` |

Roadmap C2 replaces the custom Ed25519 and PKCS#1 code with Citadel's own
initialisers (which also take a passphrase) and adds ECDSA.

## Key storage

Views and `SSHManager` reach private keys only through the `KeyStore` protocol
(`storeSSHKey(_:for:requireBiometric:)`, `retrieveSSHKey(for:)`,
`deleteSSHKey(for:)`, keyed by the host's UUID string). Views take it from the
`\.keyStore` environment entry, whose default is `KeychainManager.shared`;
`SSHTerminalView` passes it into `connect(to:keyStore:)`. Tests inject
`InMemoryKeyStore`. Biometric helpers (`authenticateUserWithPasscode`,
`biometricType`, `isBiometricAuthenticationAvailable`) are LocalAuthentication
wrappers on `KeychainManager` and are still called directly (roadmap C3).

### Keychain

`KeychainManager` stores each key as a `kSecClassGenericPassword` item, service
`com.simplessh.sshkeys`, account = the host's UUID. With biometrics on, the
item carries `SecAccessControl(kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
[.biometryCurrentSet, .or, .devicePasscode])`; otherwise plain
`WhenUnlockedThisDeviceOnly`. Items are device-only (no iCloud sync). Storing
deletes any existing item first. `retrieveSSHKey` attaches an `LAContext`, so
the read itself can prompt.

## Tests

`simplesshTests` is a Swift Testing bundle hosted by the app (`@testable import
simplessh`), with the same `MainActor` default isolation as the app so
`TerminalEmulator` and the parser can be called directly. Everything runs on the
simulator; nothing touches the Keychain, Face ID or the network.

- **TerminalEmulator** — small grids (for example 10×4) fed byte strings, asserted
  through the inspection accessors and `render(...)`.
- **Key parsing** — `TestKeys` generates an Ed25519 key with CryptoKit and an RSA
  key with `SecKeyCreateRandomKey`, then serialises them itself (openssh-key-v1
  container, PKCS#1 PEM). The RSA tests sign and verify with the decoded key to
  prove the private exponent was read. Rejection fixtures are built the same
  way: an encrypted-looking container, an unsupported algorithm, truncated
  payloads, a three-byte payload. **No private-key material is committed**; the
  pre-push gate (roadmap B4) rejects PEM blocks.
- **Host validation** — parameterised accept/reject tables for `isValidHost`.
- **SSHManager** — `connect(to:keyStore:)` with an `InMemoryKeyStore`: missing
  key, invalid key, and a valid key that reaches a refused TCP connection on
  `127.0.0.1:1` (no server involved). Render-theme changes are asserted through
  `outputVersion` and the fonts in `renderedScreen`.

Run: `xcodebuild … -scheme simplessh -sdk iphonesimulator -destination … test`
(see `README.md`).

## Concurrency

The module defaults to `MainActor` isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION`).
`SSHManager` is `@MainActor`; the PTY loop runs in a detached `Task` and hops
back with `MainActor.run` for every output chunk. The stdin writer is held as
`nonisolated(unsafe)` so the PTY closure can set it. Citadel's own work runs on
SwiftNIO event loops. Keychain calls are synchronous on the main actor today
(roadmap C4).

## Configuration

- Info.plist is generated; `NSFaceIDUsageDescription`,
  `NSLocalNetworkUsageDescription` and `NSBonjourServices` are `INFOPLIST_KEY_`
  build settings.
- Entitlements: App Sandbox, `network.client`.
- `TARGETED_DEVICE_FAMILY = 1`, `SUPPORTED_PLATFORMS = iphoneos iphonesimulator`,
  deployment target iOS 26.2.
- Dependencies are pinned in `simplessh.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
