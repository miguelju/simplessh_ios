# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project overview

iPhone-only SSH client: SwiftUI + SwiftData + Citadel (pure-Swift SSH over
SwiftNIO). Deployment target **iOS 26.2** (the UI uses `glassEffect`). Swift 5
language mode with approachable concurrency; the module defaults to `MainActor`
isolation. Xcode 26.x.

Plan of record: `ROADMAP.md` (phases A–E, one item per PR). How things work:
`ARCHITECTURE.md`. Changes: `CHANGELOG.md`.

## Build and test

```bash
open simplessh.xcodeproj

# Simulator build (what CI runs)
xcodebuild -project simplessh.xcodeproj -scheme simplessh -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Tests (target exists; sources arrive with roadmap item B1)
xcodebuild -project simplessh.xcodeproj -scheme simplessh -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Packages are pinned by the committed `Package.resolved`. Keychain, Face ID and
SSH connectivity need a physical device; the simulator only proves it compiles.

## Architecture in one screen

Views → managers → data → Citadel. Details and flow diagrams are in
`ARCHITECTURE.md`; the traps worth knowing before editing:

- **`SSHManager`** (`@MainActor`) owns the Citadel client, the PTY shell task
  and a `TerminalEmulator`. Rendering is **coalesced** through `scheduleRender()`
  into one `renderedScreen` update and one `outputVersion` bump per run-loop
  hop. Rendering from a high-frequency `onChange` made SwiftUI drop frames and
  hid the prompt until the next keystroke. Keep it coalesced.
- **`TerminalEmulator`** iterates **Unicode scalars, not Characters** (Swift
  merges `\r\n` into one grapheme). It queues replies to DSR/DA/XTWINOPS/OSC
  queries that `SSHManager` must write back via `drainReply()`; prompts such as
  Powerlevel10k block until they get them.
- **`ContentView`** uses a `List` (swipe actions need one) and value-based
  `NavigationLink` with a single stack-level `navigationDestination`; a
  per-row closure link inside a lazy stack only worked for the first row.
- **`TerminalTextField`** keeps one space of text and rejects every edit so iOS
  keeps sending backspace events; do not "fix" that.
- **Private keys live only in the Keychain**, keyed by the host's UUID. Never
  put key material in SwiftData, logs or test fixtures.

Source folders: `simplessh/{App,Hosts,Terminal,Security,Settings}`. The app
group is a synchronized folder, so new files need no project edits.

## Key constraints

- Supported private keys: OpenSSH Ed25519, OpenSSH RSA, PEM PKCS#1 RSA, no
  passphrase. Type is detected from content. (C2 adds passphrases and ECDSA.)
- Host keys are currently accepted blindly (`.acceptAnything()`); C1 fixes it.
- No password authentication, by design.
- Info.plist is generated: usage strings are `INFOPLIST_KEY_` build settings.

## Working conventions

- **One roadmap item = one PR**, branched from the previous item's branch when
  they touch the same files so merges stay fast-forwards.
- **Commits are YubiKey-signed by Miguel.** Write the message to
  `/tmp/simplessh-<item>-commit.txt`, stage, and ask for `git commit -F`. Claude
  pushes and verifies `git log -1 --format=%G?` is `G`. Never `--no-gpg-sign`.
- **Merges are fast-forwards** (`git merge --ff-only`) so the signed commit is
  the one on `main`. Claude does not merge; Miguel does.
- **Tick a roadmap box only when the code proves it** (file and symbol named,
  behaviour confirmed, reachable, tested from phase B on, verified in-session).
  Partial work is written down as partial.
- Every PR updates the docs it affects: `README.md` for user-facing behaviour,
  `ARCHITECTURE.md` for structure or data flow, `CHANGELOG.md` always.
