# Simple SSH — iPhone SSH Terminal Client

A key-based SSH client for iPhone, built with SwiftUI, SwiftData and
[Citadel](https://github.com/orlandos-nl/Citadel) (pure-Swift SSH on SwiftNIO).
Save hosts, keep the private keys in the Keychain behind Face ID, and work in a
live VT100/xterm terminal.

Developed with Xcode's Claude agent as an example of AI-assisted iOS work. The
current plan of record is [`ROADMAP.md`](ROADMAP.md); how the app is built is in
[`ARCHITECTURE.md`](ARCHITECTURE.md); changes are in [`CHANGELOG.md`](CHANGELOG.md).

## Features

**Hosts**
- Save any number of hosts (name, hostname or IP, username, port).
- Edit via the toolbar ⋯ menu → Edit, or long-press → Edit. Swipe to delete.
- Private keys live only in the iOS Keychain (device-only, hardware-encrypted),
  never in SwiftData. Optional Face ID / Touch ID gate per host, with passcode
  fallback.
- Keys are auto-detected: OpenSSH Ed25519, OpenSSH RSA, PEM PKCS#1 RSA. Keys
  must not have a passphrase (see roadmap item C2).

**Terminal**
- Interactive PTY shell (`xterm-256color`) with a stateful VT100/xterm emulator:
  cursor control, erase/insert/delete, scroll regions, bounded scrollback, and
  an alternate screen so `vim`, `htop`, `less` and `clear` behave.
- 16 / 256 / 24-bit colour; bold, dim, italic, underline, reverse, strikethrough.
- Oh My Zsh / Powerlevel10k prompts render, including Nerd Font glyphs (the
  MesloLGS NF font is bundled). Terminal queries (DSR, DA, XTWINOPS) are answered
  so prompts that probe the terminal draw immediately.
- Every keystroke goes straight to the PTY. A toolbar above the keyboard adds
  esc, tab, ctrl, arrows and common shell characters; hardware keyboards get
  arrows, function keys and ctrl-combinations.
- Typing `exit` closes the session and returns to the host list.

**Appearance**
- System / Light / Dark mode for the app chrome.
- Seven terminal themes (Classic Green, Amber, Cyan, White, Solarized, Dracula,
  Oh My Zsh) plus a Custom theme with your own font, size and colours. Live
  preview in Settings. All preferences persist.

## Screenshots

| Host list (empty) | Host list | Add host |
|:-:|:-:|:-:|
| ![Empty](simplessh/screenshots/connection_list_empty.png) | ![Populated](simplessh/screenshots/connection_list_populated.png) | ![Add](simplessh/screenshots/add_connection.png) |

| Settings | Terminal | Host list (dark) | Settings (dark) |
|:-:|:-:|:-:|:-:|
| ![Settings](simplessh/screenshots/settings_view.png) | ![Terminal](simplessh/screenshots/terminal_view.png) | ![Dark](simplessh/screenshots/connection_list_dark.png) | ![Settings dark](simplessh/screenshots/settings_view_dark.png) |

## Requirements

| | |
|---|---|
| Xcode | 26.x (the UI uses the iOS 26 `glassEffect` APIs) |
| Deployment target | iOS 26.2, iPhone only |
| Language | Swift 5 language mode with approachable concurrency; the module defaults to `MainActor` isolation |
| Device | A physical iPhone for anything real: Keychain, Face ID and SSH connectivity are limited or absent in the simulator |
| Account | A free Apple Developer account is enough for device builds |

## Quick start

```bash
git clone https://github.com/miguelju/simplessh_ios.git
cd simplessh_ios
open simplessh.xcodeproj
```

1. Xcode resolves the Swift packages on first open (pinned by the committed
   `Package.resolved`). If it does not: **File ▸ Packages ▸ Resolve Package Versions**.
2. Set your team under **Signing & Capabilities** for the `simplessh` target.
3. Select your iPhone and press **⌘R**.
4. Tap **+**, fill in the host, paste a private key, choose whether to require
   Face ID, and save.
5. Tap the host. Authenticate if asked, and the shell appears.

Command line:

```bash
# Device build
xcodebuild -project simplessh.xcodeproj -scheme simplessh -sdk iphoneos build

# Simulator build
xcodebuild -project simplessh.xcodeproj -scheme simplessh -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

### Common issues

| Symptom | Cause / fix |
|---|---|
| `No such module 'Citadel'` | Packages still resolving. **File ▸ Packages ▸ Resolve Package Versions**, or Reset Package Caches, then clean build. |
| Face ID never prompts | Simulator, or Face ID not enrolled. Use a device. |
| Connection timeout | Server not reachable from the phone's network, sshd not running, or firewall. Try `ssh user@host` from a laptop on the same network first. |
| Authentication failed | Public key not in the server's `authorized_keys`, wrong username, or a passphrase-protected key (not supported yet, roadmap C2). |
| Host key never checked | Known gap: the client currently accepts any host key. Roadmap item C1 adds trust-on-first-use verification. |

## SSH key authentication

The app supports **public-key authentication only**; password login is
deliberately unsupported. Password auth is exposed to brute force and
credential stuffing, and most hardened servers disable it. See
[RFC 4252 §7](https://datatracker.ietf.org/doc/html/rfc4252#section-7) and the
[OpenSSH manual](https://man.openbsd.org/ssh-keygen.1).

Generate a pair on your computer (Ed25519 is recommended; RSA ≥ 4096 bits if you
must):

```bash
ssh-keygen -t ed25519 -C "you@example.com"        # ~/.ssh/id_ed25519 + .pub
ssh-keygen -t rsa -b 4096 -C "you@example.com"    # RSA alternative
```

Install the **public** key on the server, then paste the **private** key file,
header and footer included, into the app:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@server
# or
cat ~/.ssh/id_ed25519.pub | ssh user@server 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'
```

| Format | Header | Algorithm |
|---|---|---|
| OpenSSH Ed25519 | `-----BEGIN OPENSSH PRIVATE KEY-----` | ssh-ed25519 |
| OpenSSH RSA | `-----BEGIN OPENSSH PRIVATE KEY-----` | ssh-rsa |
| PEM PKCS#1 RSA | `-----BEGIN RSA PRIVATE KEY-----` | RSA |

The format is detected from the content. Passphrase-protected keys are rejected
for now.

Further reading: [RFC 4251](https://datatracker.ietf.org/doc/html/rfc4251)
(protocol architecture), [GitHub's SSH guide](https://docs.github.com/en/authentication/connecting-to-github-with-ssh),
[DigitalOcean's key setup tutorial](https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys-on-ubuntu-20-04).

## Permissions and entitlements

- `NSFaceIDUsageDescription` and `NSLocalNetworkUsageDescription` are set through
  `INFOPLIST_KEY_` build settings (the Info.plist is generated).
- `NSBonjourServices` lists `_ssh._tcp.` for local-network discovery permission.
- `simplessh/simplessh.entitlements`: App Sandbox and `network.client` (outgoing TCP).

## Dependencies

Managed by Swift Package Manager and pinned by `Package.resolved`.

| Library | Version | License | Role |
|---|---|---|---|
| [Citadel](https://github.com/orlandos-nl/Citadel) | 0.9.2 | MIT | SSH client (direct dependency) |
| [swift-nio-ssh](https://github.com/Joannis/swift-nio-ssh) | 0.3.5 | Apache 2.0 | SSH protocol (Citadel's fork) |
| [swift-nio](https://github.com/apple/swift-nio) | 2.101.2 | Apache 2.0 | Event-driven networking |
| [swift-crypto](https://github.com/apple/swift-crypto) | 2.0.5 | Apache 2.0 | Cryptography |
| [BigInt](https://github.com/attaswift/BigInt) | 5.7.0 | MIT | RSA arithmetic |
| [swift-log](https://github.com/apple/swift-log) | 1.14.0 | Apache 2.0 | Logging |
| [swift-atomics](https://github.com/apple/swift-atomics) | 1.3.1 | Apache 2.0 | Atomics |
| [swift-collections](https://github.com/apple/swift-collections) | 1.6.0 | Apache 2.0 | Data structures |
| [swift-system](https://github.com/apple/swift-system) | 1.7.2 | Apache 2.0 | System interfaces |
| [ColorizeSwift](https://github.com/mtynior/ColorizeSwift) | 1.7.0 | MIT | Terminal string colouring |

## License

[MIT](LICENSE).
