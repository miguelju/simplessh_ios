# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Roadmap
item ids (A1, B3, …) refer to [`ROADMAP.md`](ROADMAP.md).

## [Unreleased]

### Added
- B4 — Repository hardening: rulesets requiring verified signatures on
  `main` and `v*` tags (no bypass) plus PR / linear-history / no-force-push
  protection (Admin bypass); `hooks/pre-push` private-data gate with a
  `--self-test`; Actions restricted to GitHub-owned, SHA-pinned actions.
- B3 — GitHub Actions workflow: build and test on the hosted `macos-26` image
  (Xcode 26.6, iPhone 17 simulator) for every PR and push to `main`,
  path-filtered so docs-only changes skip it, actions SHA-pinned, log and
  result bundle uploaded on failure. CI badge in the README.
- B2 — `KeyStore` protocol with a `\.keyStore` SwiftUI environment entry
  (default: the Keychain) and `SSHManagerTests`, which drive `connect` with an
  in-memory store: missing key, invalid key, valid key reaching a refused
  localhost connection, and render-theme changes.
- B1 — `simplesshTests` Swift Testing bundle: terminal emulator (grid, cursor,
  scrollback, alternate screen, DECSTBM, SGR, erase/insert/delete, DSR/DA/OSC
  replies, sequences split across feeds), private-key parsing (OpenSSH Ed25519,
  OpenSSH RSA, PEM PKCS#1 RSA, and the encrypted / unsupported-type / truncated
  / tiny-payload / wrong-format rejections) and `isValidHost`. Test keys are
  generated at test time; none are committed. Shared `simplessh` scheme runs
  the tests; `README.md` documents the command.

### Fixed
- B1 — A short or truncated OpenSSH key body crashed the key-type detector
  (negative range in the marker scan); it now throws a parse error. An
  unsupported OpenSSH algorithm is reported by name (for example
  `ecdsa-sha2-nistp256`) instead of "unknown".

### Changed
- B2 — `SSHManager` takes its key store as a `connect(to:keyStore:)` parameter
  and its colours/fonts as a `renderTheme` value; it no longer reads
  `KeychainManager.shared` or `TerminalSettingsStore.shared`. The terminal
  now re-renders on Custom-theme font/colour edits, not only on theme name.
  Views store and delete keys through the environment's key store instead of
  wrappers on `SSHConnection`.
- B1 — `SSHManager.parsePrivateKey(_:)` returns a `ParsedPrivateKey` so tests
  can assert on the decoded key; `TerminalEmulator` gained read-only inspection
  accessors (cursor, scroll region, alternate-screen flag, line text).
- A1 — Sources reorganised into `App/`, `Hosts/`, `Terminal/`, `Security/`,
  `Settings/`; the stray root-level keyboard file moved inside the app folder.
- A3 — `Package.resolved` is committed; README dependency table synced to it.
- A4 — Six overlapping docs merged into `README.md`, `ARCHITECTURE.md` and this
  file; stale claims fixed (iOS 26.2 not 17, Swift 5 language mode, `ANSIParser`
  gone, no test sources yet, list sorted by creation date).
- A5 — Project builds for iPhone only (was iPhone, iPad and visionOS).

### Removed
- B2 — `SSHConnection.storeSSHKey/retrieveSSHKey/deleteSSHKey/hasSSHKey`,
  `KeychainManager.retrieveSSHKeyWithoutAuth` and `SSHManager.requestRender`.
- B1 — The `simplesshUITests` target (pointed at a folder that no longer
  existed; no UI tests are planned).
- A2 — Dead code: `MigrationHelper`, `SSHManager.sendCommand`,
  `KeychainManager.updateSSHKey`, the biometrics-only `authenticateUser`, an
  unused scroll proxy, the empty bridging header, `Info-plist-additions.xml`
  and `icons.code`.

## 2026-06-28

### Fixed
- Tapping any host row (not only the first) opens the terminal: value-based
  navigation with a single stack-level destination.

### Changed
- Terminal rendering rewritten as a stateful VT100/xterm emulator
  (`TerminalEmulator`) replacing the one-shot ANSI parser: live grid, cursor,
  scroll regions, scrollback, alternate screen, terminal-query replies,
  coalesced rendering. Fixes stray `%` marks and the prompt not appearing until
  the first keystroke.

## 2026-03-29

### Added
- Edit existing hosts (edit mode and long-press menu).
- System / Light / Dark appearance with an adaptive palette.

## 2026-03-22 — 2026-03-23

### Added
- Initial app: host list, add-host form, Keychain key storage with Face ID,
  Citadel SSH with PTY shell, ANSI colour rendering, seven terminal themes plus
  Custom, bundled MesloLGS NF, README and documentation set.
