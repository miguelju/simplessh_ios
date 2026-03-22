# Quick Start Guide - SimpleSSH

## 5-Minute Setup

### Step 1: Open the Project (1 minute)

```bash
# Open the project
open simplessh.xcodeproj
```

### Step 2: Resolve Packages (1 minute)

Xcode will automatically resolve the Citadel SPM package and its dependencies on first open. If not:

1. In Xcode: **File > Packages > Resolve Package Versions**
2. Wait for packages to download (Citadel, SwiftNIO SSH, swift-crypto, etc.)

### Step 3: Build & Run (3 minutes)

1. **Connect a real iPhone** (Keychain/Face ID don't work in simulator)
2. **Select your device** in the Xcode toolbar
3. **Build & Run** (Cmd+R)
4. **Add a connection:**
   - Tap "Add Connection"
   - Enter server details (name, IP, username, port)
   - Paste your SSH private key (Ed25519 or RSA, in OpenSSH or PEM format)
   - Toggle Face ID requirement
   - Save
5. **Connect:**
   - Tap the connection
   - Authenticate with Face ID if required
   - Wait for SSH connection
   - Type commands in the terminal

---

## Verification Checklist

- [ ] Project builds without errors
- [ ] SPM packages resolved successfully
- [ ] App runs on real device
- [ ] Can add new connection
- [ ] Face ID/Touch ID prompts appear
- [ ] SSH key stored in Keychain
- [ ] Can connect to SSH server
- [ ] Terminal shows real output
- [ ] Commands execute properly
- [ ] Deletion removes Keychain entry

---

## Quick Test with a Local SSH Server

```bash
# On your SSH server machine:
# 1. Enable SSH
sudo systemsetup -setremotessh on  # macOS
# or
sudo service ssh start  # Linux

# 2. Find your IP address
ifconfig | grep "inet "  # Look for 192.168.x.x or 10.x.x.x

# 3. Generate SSH key (if needed)
ssh-keygen -t ed25519 -f ~/.ssh/test_key
# or for RSA:
# ssh-keygen -t rsa -b 4096 -f ~/.ssh/test_key

# 4. Add public key to authorized_keys
cat ~/.ssh/test_key.pub >> ~/.ssh/authorized_keys

# 5. Copy private key — paste into the app
cat ~/.ssh/test_key
# Copy everything including the header/footer lines:
# -----BEGIN OPENSSH PRIVATE KEY-----
# ... content ...
# -----END OPENSSH PRIVATE KEY-----
```

---

## Common Issues

### Issue: "Package resolution failed"
**Solution:** File > Packages > Reset Package Caches, then resolve again.

### Issue: "No such module 'Citadel'"
**Solution:** Wait for SPM to finish resolving. Check File > Packages > Resolve Package Versions.

### Issue: "Face ID not working"
**Solution:** Must use real device. Check Info.plist has Face ID usage description. Ensure Face ID is enrolled.

### Issue: "Connection timeout"
**Solution:** Check SSH server is running. Verify IP address. Ensure device and server on same network.

### Issue: "Authentication failed"
**Solution:** Verify SSH key format (Ed25519 or RSA, in OpenSSH or PEM format). Check public key is in authorized_keys. Ensure username is correct. Encrypted (passphrase-protected) keys are not supported.

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| UI | SwiftUI + Liquid Glass |
| Data | SwiftData |
| SSH | Citadel (SwiftNIO SSH) |
| Terminal Rendering | ANSI parser (Oh My Zsh compatible) |
| Appearance | Customizable font, size, colors (6 themes + custom) |
| Settings Persistence | @AppStorage (UserDefaults) |
| Key Storage | iOS Keychain |
| Auth | Face ID / Touch ID |
| Package Manager | Swift Package Manager |
