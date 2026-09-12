# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Roadmap
item ids (A1, B3, …) refer to [`ROADMAP.md`](ROADMAP.md).

## [Unreleased]

### Changed
- A1 — Sources reorganised into `App/`, `Hosts/`, `Terminal/`, `Security/`,
  `Settings/`; the stray root-level keyboard file moved inside the app folder.
- A3 — `Package.resolved` is committed; README dependency table synced to it.
- A4 — Six overlapping docs merged into `README.md`, `ARCHITECTURE.md` and this
  file; stale claims fixed (iOS 26.2 not 17, Swift 5 language mode, `ANSIParser`
  gone, no test sources yet, list sorted by creation date).
- A5 — Project builds for iPhone only (was iPhone, iPad and visionOS).

### Removed
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
