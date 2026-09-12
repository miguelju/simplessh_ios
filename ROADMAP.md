# SimpleSSH Roadmap

Approved 2026-09-11. This is the working plan for making the project easier to
change (phases A–B), closing real security and correctness gaps (C), improving
the terminal (D), and reworking the hosts/keys workflow and UI (E).

UI mockups for phases D–E: https://claude.ai/code/artifact/3620dac9-dff5-4f19-afab-f93d2167e0d2
(five screens: Hosts, Terminal, New host, Keys, Host-key trust).

## How we work

- **One item = one PR.** Small, reviewable, revertible. Items within a phase
  are independent unless noted; phases run in order.
- **A checkbox is ticked only when the code proves it.** Before marking an
  item done: name the file and symbol, confirm it does what the item says,
  confirm it is reachable from production code, confirm a test asserts the
  behaviour (from phase B onward), and run that verification in the same
  session. Partial completion is written down as partial, never rounded up.
- **Every PR updates the docs it affects** (after A4: `README.md` for
  user-facing behaviour, `ARCHITECTURE.md` for structure/data flow,
  `CHANGELOG.md` always).
- **Commits are YubiKey-signed by Miguel.** Claude writes the message to a
  file; Miguel runs `git commit -F`; Claude pushes and verifies `%G? == G`.
- Effort: **S** < 1 h · **M** ≈ half a day · **L** ≥ 1 day.

Status legend: `[ ]` not started · `[~]` in progress (PR open) · `[x]` merged and verified.

---

## Phase A — Hygiene

Mechanical cleanups that make every later diff smaller and reviews faster.

- [x] **A1 · Reorganise sources by feature** (S)
  Move `TerminalKeyboardView.swift` from the repo root into `simplessh/`.
  Group files: `App/` (app entry, fonts), `Hosts/` (model, list, form),
  `Terminal/` (SSHManager, TerminalEmulator, terminal view, keyboard),
  `Security/` (Keychain), `Settings/` (theme store, settings view).
  *Done when:* no Swift file outside `simplessh/`; project builds; groups
  match folders on disk.

- [x] **A2 · Delete dead code** (S)
  Remove `MigrationHelper.swift` (292 lines, zero callers, no-op migration),
  `SSHManager.sendCommand`, `KeychainManager.updateSSHKey`,
  `KeychainManager.authenticateUser`, the unused `scrollProxy` state in
  `SSHTerminalView`, the empty bridging header (and its build setting),
  `Info-plist-additions.xml`, and `icons.code`.
  *Done when:* `grep` finds no references; build is warning-free.

- [x] **A3 · Commit `Package.resolved`** (S)
  Remove the `swiftpm/` ignore rule from `.gitignore` and commit the lockfile
  so every machine and CI resolve identical dependency versions.
  *Done when:* `git ls-files | grep Package.resolved` is non-empty.

- [x] **A4 · Consolidate documentation** (M)
  Collapse `simplessh/{README,APP_FLOW,FILE_STRUCTURE,IMPLEMENTATION_SUMMARY,
  PRODUCTION_IMPLEMENTATION_GUIDE,QUICK_START}.md` into three root files:
  `README.md` (overview, screenshots, SSH-key guide, quick start),
  `ARCHITECTURE.md` (layers, data flow, threading, key parsing, Keychain,
  troubleshooting), `CHANGELOG.md`. Fix the stale claims while merging:
  deployment target is **iOS 26.2** (not 17), language mode is **Swift 5 with
  approachable concurrency** (not Swift 6), `ANSIParser` no longer exists,
  the list sorts by `createdAt` (or change it to `lastUsedAt` in E2), and the
  test folders listed in FILE_STRUCTURE do not exist. Rewrite the
  `CLAUDE.md` documentation policy to reference only the three files.
  *Done when:* the six inner docs are gone, no doc names a symbol that is not
  in the code, `CLAUDE.md` policy lists exactly three docs.

- [x] **A5 · iPhone-only target** (S)
  Set `TARGETED_DEVICE_FAMILY = 1` (currently `1,2,7` = iPhone/iPad/Vision)
  to match the docs and the terminal layout. Drop the iPad orientation key.
  *Done when:* project builds; setting verified in `project.pbxproj`.

## Phase B — Safety net

Tests and CI so that phases C–E can be reviewed on behaviour, not on faith.

- [x] **B1 · Unit-test target with Swift Testing** (L)
  Recreate `simplesshTests/` as a real target (the current one points at a
  deleted folder). Priority order:
  1. `TerminalEmulator` — feed byte sequences, assert grid/cursor/scrollback/
     alt-screen; cover CR/LF, SGR, CSI cursor moves, erase, insert/delete,
     DECSTBM, `?1049`, DSR/DA replies, and sequences split across two `feed`
     calls.
  2. Key parsing — OpenSSH Ed25519, OpenSSH RSA, PEM PKCS#1 RSA, and the
     rejection paths (encrypted key, truncated data, unknown type, and the
     under-11-byte input that currently crashes the type detector).
     **Test keys are generated at test time with CryptoKit and serialised by
     a test helper — no private-key material is ever committed** (the
     pre-push gate in B4 would reject it anyway).
  3. `AddConnectionView.isValidHost` — IPv4, IPv6, hostnames, the double-dot
     and empty-octet typos.
  *Done when:* `xcodebuild … test` passes on the simulator; the three areas
  above have tests; CLAUDE.md's test command works as written.
  *Done 2026-09-12:* 55 tests green on the iPhone 17 simulator
  (`simplesshTests/`, shared scheme `simplessh`). Testing the under-11-byte
  input required removing the crash: `detectOpenSSHKeyType` now walks the
  container with bounds checks instead of scanning for a marker (C2 still
  replaces the parsers). The `simplesshUITests` target, which also pointed at
  a deleted folder, was removed.

- [x] **B2 · Dependency seams** (M)
  Put `KeychainManager` behind a `KeyStore` protocol with an in-memory test
  implementation. Stop `SSHManager.scheduleRender` reading
  `TerminalSettingsStore.shared`; pass a render theme in (the view already
  observes the store). Inject the key store into `SSHManager.connect`.
  *Done when:* `SSHManager` and `SSHConnection` have no direct reference to
  `KeychainManager.shared`; B1's tests use the in-memory store.
  Also drop `SSHConnection.hasSSHKey()` and `retrieveSSHKeyWithoutAuth` — their
  only caller was the migration helper removed in A2.
  *Done 2026-09-12:* `KeyStore` protocol + `\.keyStore` environment entry
  (`Security/KeyStore.swift`), `SSHManager.connect(to:keyStore:)`,
  `SSHManager.renderTheme` (`TerminalRenderTheme` snapshot from the store,
  assigned by the view on change), `SSHConnection` carries no key logic at all
  (its three wrappers went with `hasSSHKey`). `SSHManagerTests` run `connect`
  against `InMemoryKeyStore`; 60 tests green.

- [x] **B3 · GitHub Actions CI** (M)
  Workflow: build + test on a macOS runner for every PR and push to `main`,
  path-filtered (`**/*.md` → no run; workflow file includes itself in
  `paths:`), all third-party actions SHA-pinned. Public repo ⇒ hosted macOS
  minutes are free. **Caveat:** the hosted image must ship Xcode 26.x for
  the `glassEffect` APIs; if the image lags, use the self-hosted Mac mini
  runner pattern from `vle` instead.
  *Decision 2026-09-11:* the hosted `macos-26` image defaults to Xcode 26.6
  build 17F113, identical to the local toolchain, so B3 uses hosted runners.
  The Mac mini (Xcode 26.6, no runner installed) stays a fallback only.
  *Done when:* a green run on a PR; a deliberate test failure turns it red.
  *Done 2026-09-12 (PR #8):* `.github/workflows/ci.yml`. The PR's first
  commit carried a deliberately failing test and its run was red (build,
  simulator and the other 60 tests fine; artifact uploaded); the second
  commit removed it and its run was green.

- [x] **B4 · Repo hardening** (S)
  Apply the four rulesets (`protect-main` with Admin bypass,
  `require-signed-commits` with none, and the two `v*` tag equivalents).
  Copy the private-data pre-push hook into `hooks/pre-push`, set
  `core.hooksPath=hooks`, scope the diff to exclude `hooks/`. Enable
  `sha_pinning_required` **after** B3 pins every action.
  *Note from B1:* the config-repo hook's `BEGIN … PRIVATE KEY` pattern is a
  substring match, so it fires on this repo's own parser (`hasPrefix` lines in
  `SSHManager.swift`), on `ARCHITECTURE.md` and on the test helper's armour
  code. The copied hook must anchor the pattern to a header **followed by a
  base64 body line** (or exclude Swift string literals and Markdown) so it
  catches a pasted key without blocking every parser change.
  *Done 2026-09-12:* four rulesets created via the API (ids 23095164/66/67/68);
  an unsigned commit created through the Git Data API and pushed at `main`
  was rejected with HTTP 422 "Commits must have verified signatures";
  `hooks/pre-push` anchors the PEM check on header + base64 body line and
  ships a `--self-test` (generated key blocked, header-only text passes,
  token blocked); `sha_pinning_required` on with GitHub-owned actions only.
  *Done when:* `gh api repos/miguelju/simplessh_ios/rulesets` lists four;
  an unsigned test push to `main` is rejected; the hook blocks a PEM block.

- [ ] **B5 · Formatting** (S)
  Check in a `.swift-format` config and run `swift format lint` in CI (uses
  the Xcode toolchain; no third-party tool). One-time reformat as its own
  commit so blame stays useful.
  *Done when:* CI fails on an unformatted file.

## Phase C — Security and correctness

- [ ] **C1 · Host-key verification (trust on first use)** (M)
  Replace `hostKeyValidator: .acceptAnything()` with a custom validator.
  First connection: show the trust sheet (mockup 5) with host, key type and
  SHA256 fingerprint; on accept, store the public key on the host record.
  Later connections: `trustedKeys` with the stored key; on mismatch, refuse
  and show a red warning with both fingerprints and an explicit "replace
  saved key" action. Keys screen (E1) lists known hosts.
  *Done when:* connecting to a host whose key changed is refused; test covers
  accept/store/mismatch paths via the validator delegate.

- [ ] **C2 · Use Citadel's key parsers; add passphrases and ECDSA** (M)
  Delete the hand-rolled OpenSSH Ed25519 parser and PKCS#1 DER walker in
  `SSHManager` in favour of Citadel's `init(sshEd25519:decryptionKey:)` /
  `init(sshRsa:decryptionKey:)`. Prompt for a passphrase when the key is
  encrypted (store it in the Keychain alongside the key, biometric-gated).
  Add `p256`/`p384`/`p521` auth methods. Fixes the negative-range crash in
  `detectOpenSSHKeyType` by removing it.
  *Done when:* an encrypted Ed25519 key and an ECDSA key both authenticate;
  tests from B1 updated; README's "encrypted keys not supported" note removed.

- [ ] **C3 · Single biometric prompt** (S)
  `SSHTerminalView.connectToServer` runs `authenticateUserWithPasscode`,
  then `retrieveSSHKey` creates a fresh `LAContext`, so the user is prompted
  twice. Reuse one context for both, or drop the explicit check and pass the
  reason via the context used by the Keychain query.
  *Done when:* verified on a physical device: one Face ID prompt per connect.

- [ ] **C4 · Keychain read off the main actor** (S)
  `SecItemCopyMatching` with biometric access control blocks the main thread
  while the system sheet is up. Run it on a background task and `await` it.
  *Done when:* main-thread checker is quiet; UI stays responsive during the
  prompt.

- [ ] **C5 · Confirm before delete** (S)
  Swipe-to-delete and the context-menu Delete destroy the private key with
  no undo. Add a confirmation dialog naming the host.
  *Done when:* deletion requires a second tap.

- [ ] **C6 · No auto-dismiss on disconnect** (S)
  Remove the 500 ms auto-`dismiss()` after the session drops; it hides the
  shell's last output and the error. Show a "Session ended" bar with
  **Reconnect** and **Close**.
  *Done when:* typing `exit` leaves the screen visible with the bar.

## Phase D — Terminal

- [ ] **D1 · Fit columns to the screen; window-change on resize** (M)
  Replace the hard-coded 80×24 PTY with a size computed from the view's
  width/height and the theme's cell size (≈46 cols at 14 pt on an iPhone).
  Make `TerminalEmulator` resizable. On rotation or font change, call
  `TTYStdinWriter.changeSize(cols:rows:…)` and resize the grid. Show the live
  size in the nav subtitle (mockup 2).
  *Done when:* no line wraps at the default size; `htop`/`vim` render at the
  phone width; rotating updates the PTY size (test on device).

- [ ] **D2 · Render the cursor** (S)
  Draw a block cursor at the emulator's cursor position (reverse-video cell),
  hidden when `?25l` is received.
  *Done when:* a caret is visible after the prompt; test asserts the cursor
  cell is styled.

- [ ] **D3 · Incremental rendering** (M)
  Render only the live screen per output batch; cache scrollback lines as
  they scroll off (they are immutable) and re-render them only on theme
  change. Keep the coalesced-render design.
  *Done when:* a `cat` of a 2,000-line file stays smooth; render time per
  batch measured before/after and recorded in the PR.

- [ ] **D4 · Key bar** (M)
  Horizontally scrollable bar above the keyboard: esc, tab, ctrl, alt, arrows,
  `-` `/` `|` `~`, plus pinned paste and hide-keyboard. Ctrl/alt are sticky
  modifiers with a visible active state. Pinch on the terminal changes font
  size (persisted per theme).
  *Done when:* matches mockup 2; ctrl+c and alt+b reach the PTY correctly.

- [ ] **D5 · Sessions survive navigation** (L)
  Move `SSHManager` instances into an app-level `SessionStore` keyed by host.
  Leaving the terminal no longer disconnects; the Hosts screen shows an
  "Active sessions" strip (mockup 1); reopening a host resumes its session;
  a dropped session offers reconnect. Sessions end on explicit Disconnect or
  when the app is terminated.
  *Done when:* navigate away and back keeps the shell state; two hosts can be
  open at once.

## Phase E — Workflow and UI

Design direction (from the mockups): keep iOS 26 Liquid Glass, but only on
chrome (toolbar pills, cards). Rows go from 100 pt to 60 pt; the tinted
magenta dark-mode cards go; the terminal carries the visual weight.

- [ ] **E1 · Keys as first-class objects** (L)
  New `SSHKey` model (name, type, public key, fingerprint, created, biometric
  flag); private material stays in the Keychain keyed by the key's id. Hosts
  reference a key. Keys screen (mockup 4): list, copy public key, usage
  count, delete with "still used by N hosts" guard, known-hosts list (C1).
  Generate Ed25519 on device with CryptoKit; import from Files or clipboard
  (with passphrase from C2). One-time migration: each existing host's key
  becomes an `SSHKey` named after the host.
  *Done when:* one key can be attached to several hosts; migration verified
  on a device with existing hosts; tests cover the model and migration.

- [ ] **E2 · Hosts screen** (M)
  Search (name, user, host, tag); sort by last use; group by tag; per-row
  key chip and relative last-used; active-sessions strip (D5). Swipe: Edit,
  Duplicate, Delete (C5). Denser rows per mockup 1.
  *Done when:* matches mockup 1; search and grouping have tests on the
  filtering logic.

- [ ] **E3 · New / Edit Host form** (M)
  Native grouped form (mockup 3): Server (name, host:port, user), Identity
  (picker + generate + import), Security (Face ID toggle, host-key status),
  Tags, and a **Test connection** button that runs the handshake without
  opening a shell. Pasting `user@host:port` or a full `ssh …` command into
  Host fills the fields.
  *Done when:* matches mockup 3; the paste parser has tests.

- [ ] **E4 · Status colours** (S)
  Connecting = grey, connected = green, reconnecting = orange, failed = red
  (today the pill is red while connecting).
  *Done when:* verified visually in each state.

---

## Deferred (not approved, noted for later)

- SFTP / file transfer
- Port forwarding
- Password authentication (deliberately unsupported)
- iPad / Vision layouts (dropped in A5)
