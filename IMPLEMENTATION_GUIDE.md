# Claude Nook - Implementation Guide

This guide walks you through setting up Claude Nook with TCP support for remote Claude Code sessions, including the iOS companion app.

## Overview

This fork adds TCP socket support and an iOS companion app to Claude Nook, allowing you to:
- Run Claude Code on a remote machine (server, VM, container)
- See the Claude Nook notch UI on your local Mac
- Approve/deny permissions from your Mac or iPhone for remote sessions
- Monitor multiple Claude sessions from your iOS device

## Prerequisites

### On Your Mac (Local Machine)
- macOS 14.0+ (Sonoma) or macOS 15.0+ (Sequoia)
- Xcode 15.0+ (for building the app)
- Git

### On Your Remote Machine
- Claude Code CLI installed
- Python 3.6+
- Git (to clone the repo)
- Network access to your Mac (SSH, Tailscale, or local network)

### For iOS Companion App
- iOS 16.0+
- iPhone on the same network as your Mac (or via Tailscale)

---

## Part 1: Setup on Your Mac

### Step 1.1: Clone the Repository

```bash
# Clone the TCP-enabled fork
git clone https://github.com/Jmi2020/claude-nook.git
cd claude-nook
```

### Step 1.2: Build the macOS App

**Option A: Using Xcode GUI**

1. Open the Xcode project:
   ```bash
   open ClaudeNook.xcodeproj
   ```

2. In Xcode:
   - Select the `ClaudeNook` scheme (top left dropdown)
   - Select "My Mac" as the destination
   - Press `Cmd+B` to build, or `Cmd+R` to build and run

3. If you get signing errors:
   - Go to Project Settings → Signing & Capabilities
   - Select your Apple Developer team (or Personal Team)
   - Let Xcode manage signing automatically

**Option B: Using Command Line**

```bash
# Build for debugging/testing
xcodebuild -scheme ClaudeNook -configuration Debug build

# The app will be in:
# ~/Library/Developer/Xcode/DerivedData/ClaudeNook-*/Build/Products/Debug/Claude Nook.app
```

### Step 1.3: Build the iOS App

**Using Xcode GUI (Recommended)**

1. In Xcode with `ClaudeNook.xcodeproj` open:
   - Select the `ClaudeNookiOS` scheme
   - Select an iOS Simulator or your connected iPhone
   - Press `Cmd+R` to build and run

**Using Command Line**

```bash
# Build for iOS Simulator
xcodebuild -scheme "ClaudeNookiOS" -destination "platform=iOS Simulator,name=iPhone 16" -configuration Debug build

# The app will be in:
# ~/Library/Developer/Xcode/DerivedData/ClaudeNook-*/Build/Products/Debug-iphonesimulator/Claude Nook iOS.app
```

### Step 1.4: Run the macOS App

If you built via command line, locate and run the app:

```bash
# Find the built app
find ~/Library/Developer/Xcode/DerivedData -name "Claude Nook.app" -type d 2>/dev/null | head -1

# Run it (adjust path as needed)
open ~/Library/Developer/Xcode/DerivedData/ClaudeNook-*/Build/Products/Debug/Claude\ Nook.app
```

Or simply run from Xcode with `Cmd+R`.

### Step 1.5: Configure TCP Settings

1. **Click on the Claude Nook notch** at the top of your screen

2. **Click anywhere to open the menu**

3. **Find "Remote Access"** and click to expand

4. **Select your bind mode:**
   - **Localhost Only** - Use this if you'll connect via SSH tunnel (most secure)
   - **All Interfaces** - Use this for Tailscale, iOS app, or direct LAN connections

5. **Note the configuration:**
   - The port (default: 4851)
   - Click "Regenerate" if no token exists
   - Click "Copy" to copy the token

6. **Click "Copy Remote Setup Info"** to get all settings at once

### Step 1.6: Note Your Mac's Address

Depending on your connection method:

```bash
# For local network - get your IP
ifconfig | grep "inet " | grep -v 127.0.0.1

# For Tailscale - get your Tailscale IP/hostname
tailscale status
```

---

## Part 2: Setup the iOS Companion App

### Step 2.1: Launch the iOS App

Run the iOS app on your iPhone or Simulator from Xcode.

### Step 2.2: Connect to Your Mac

1. **On first launch**, the app shows the Connection view

2. **If your Mac is on the same network**, it should appear in the "Discovered Macs" list via Bonjour/mDNS

3. **Tap your Mac** to select it, or manually enter:
   - Host: Your Mac's IP or hostname
   - Port: 4851 (default)
   - Token: Paste the 64-character token from Claude Nook

4. **Tap "Connect"**

### Step 2.3: Using the iOS App

Once connected, you'll see:

- **Session List** - Grid of active Claude Code sessions
- **Status Indicators** - Processing (blue), Waiting (green), Needs Approval (orange)
- **Permission Requests** - Sheet appears when a tool needs approval

**To approve a permission:**
1. A sheet automatically appears when a tool needs approval
2. Review the tool name and input
3. Tap "Approve" or "Deny"

**To view session details:**
- Tap any session card to see details
- View project name, session ID, and current status

---

## Part 3: Setup on Your Remote Machine

### Step 3.1: Clone the Repository

```bash
# Clone to get the updated hook script and setup tools
git clone https://github.com/Jmi2020/claude-nook.git
cd claude-nook
```

### Step 3.2: Install the Hook Script

```bash
# Create hooks directory if it doesn't exist
mkdir -p ~/.claude/hooks

# Copy the TCP-enabled hook script
cp ClaudeNook/Resources/claude-nook-state.py ~/.claude/hooks/

# Make it executable
chmod +x ~/.claude/hooks/claude-nook-state.py
```

### Step 3.3: Configure the Connection

**Option A: Interactive Setup (Recommended)**

```bash
# Run the setup script
./scripts/setup/remote-setup.sh
```

This will prompt you for:
- Your Mac's hostname/IP
- The port (default: 4851)
- The auth token from Claude Nook

**Option B: Manual Setup**

```bash
# Create config directory
mkdir -p ~/.config/claude-nook
chmod 700 ~/.config/claude-nook

# Create the environment file
cat > ~/.config/claude-nook/claude-nook.env << 'EOF'
# Claude Nook Remote Configuration
CLAUDE_NOOK_HOST=YOUR_MAC_IP_OR_HOSTNAME
CLAUDE_NOOK_PORT=4851
CLAUDE_NOOK_TOKEN=YOUR_64_CHAR_TOKEN_HERE
CLAUDE_NOOK_MODE=tcp
EOF

# Secure the file
chmod 600 ~/.config/claude-nook/claude-nook.env
```

### Step 3.4: Add Shell Integration

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
# Claude Nook remote configuration
if [ -f ~/.config/claude-nook/claude-nook.env ]; then
    set -a
    source ~/.config/claude-nook/claude-nook.env
    set +a
fi
```

Then reload:
```bash
source ~/.zshrc  # or ~/.bashrc
```

### Step 3.5: Verify Hook Registration

Check that Claude Code knows about the hook:

```bash
cat ~/.claude/settings.json | grep claude-nook
```

If the hook isn't registered, you may need to run Claude Nook on your Mac first (it auto-registers hooks), or manually add it to `~/.claude/settings.json`.

---

## Part 4: Establish the Connection

### Option A: SSH Tunnel (Most Secure)

Best for: Connections over the internet or untrusted networks.

**On your Mac:** Set Claude Nook to "Localhost Only" mode.

**On your remote machine:**

```bash
# Simple tunnel (runs in foreground)
ssh -L 4851:localhost:4851 your-mac-hostname

# Or use the helper script for auto-reconnect
./scripts/setup/ssh-tunnel.sh your-mac-hostname
```

Keep this terminal open while using Claude Code.

### Option B: Tailscale (Easiest)

Best for: Always-on connectivity without manual tunnels.

1. Install Tailscale on both machines
2. On Mac: Set Claude Nook to "All Interfaces" mode
3. Use your Mac's Tailscale hostname (e.g., `my-macbook.tail1234.ts.net`)

### Option C: Direct LAN Connection

Best for: Both machines on the same trusted network.

1. On Mac: Set Claude Nook to "All Interfaces" mode
2. Use your Mac's local IP (e.g., `192.168.1.100`)
3. Ensure firewall allows port 4851:
   ```bash
   # On Mac, add firewall rule if needed
   sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /path/to/Claude\ Nook.app
   ```

---

## Part 5: Test the Connection

### Step 5.1: Run the Test Script

On your remote machine:

```bash
./scripts/setup/test-connection.sh
```

Expected output:
```
=== Claude Nook Connection Test ===

Configuration:
  Host:   your-mac-ip
  Port:   4851
  Token:  abcd...wxyz (64 chars)

1. Testing Unix socket (/tmp/claude-nook.sock)...
   [--] Socket not found (expected for remote machines)

2. Testing TCP port reachability (your-mac:4851)...
   [OK] TCP port is reachable

3. Testing authentication...
   [OK] Authentication successful

4. Testing event delivery...
   [OK] Event sent successfully

=== All Tests Passed ===
```

### Step 5.2: Test with Claude Code

On your remote machine:

```bash
# Enable debug mode to see connection logs
export CLAUDE_NOOK_DEBUG=1

# Run Claude Code
claude
```

In the debug output, you should see:
```
[claude-nook] Mode: tcp, Event: SessionStart
[claude-nook] Connecting via TCP: your-mac:4851
[claude-nook] Sending auth...
[claude-nook] Auth response: OK
[claude-nook] TCP send successful
```

On your Mac, the Claude Nook notch should light up showing the session!

On your iPhone, the session should appear in the Session List!

---

## Troubleshooting

### "Connection refused"

1. Is Claude Nook running on your Mac?
2. Is TCP enabled in Claude Nook settings?
3. Check firewall on Mac:
   ```bash
   sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
   ```

### "Authentication failed"

1. Verify the token matches exactly (no extra spaces)
2. Try regenerating the token in Claude Nook and reconfiguring remote

### "Socket not found" on remote

This is expected! The remote machine should use TCP mode:
```bash
echo $CLAUDE_NOOK_MODE  # Should output: tcp
```

### Hook not triggering

1. Check hook is in settings:
   ```bash
   cat ~/.claude/settings.json | python3 -m json.tool | grep -A5 hooks
   ```

2. Verify the hook script path exists:
   ```bash
   ls -la ~/.claude/hooks/claude-nook-state.py
   ```

3. Test the hook manually:
   ```bash
   echo '{"session_id":"test","hook_event_name":"SessionStart","cwd":"/tmp"}' | python3 ~/.claude/hooks/claude-nook-state.py
   ```

### iOS App Won't Connect

1. Ensure Mac and iPhone are on the same network
2. Verify "All Interfaces" mode is enabled in Claude Nook
3. Check the token is correct (64 characters)
4. Try the Mac's IP address instead of hostname

### Debug mode

Enable verbose logging:
```bash
export CLAUDE_NOOK_DEBUG=1
```

---

## Quick Reference

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_NOOK_MODE` | `auto`, `socket`, or `tcp` | `auto` |
| `CLAUDE_NOOK_HOST` | Mac's IP or hostname | `127.0.0.1` |
| `CLAUDE_NOOK_PORT` | TCP port | `4851` |
| `CLAUDE_NOOK_TOKEN` | 64-char auth token | (none) |
| `CLAUDE_NOOK_DEBUG` | Enable debug output | `0` |

### File Locations

| File | Location | Purpose |
|------|----------|---------|
| Hook script | `~/.claude/hooks/claude-nook-state.py` | Claude Code hook |
| Config | `~/.config/claude-nook/claude-nook.env` | Environment config |
| Claude settings | `~/.claude/settings.json` | Hook registration |

### Useful Commands

```bash
# Test connection
./scripts/setup/test-connection.sh

# Generate new token
./scripts/setup/generate-token.sh

# Start SSH tunnel
./scripts/setup/ssh-tunnel.sh your-mac-hostname

# Check current config
env | grep CLAUDE_NOOK
```

---

## Architecture Diagram

```
┌────────────────────────────────────────────────────────────────────────┐
│                          YOUR MAC (Local)                               │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    Claude Nook.app                               │  │
│  │                                                                  │  │
│  │  ┌─────────────────┐    ┌─────────────────────────────────────┐  │  │
│  │  │ Unix Socket     │    │ TCP Socket                          │  │  │
│  │  │ /tmp/claude-    │    │ 0.0.0.0:4851                        │  │  │
│  │  │ nook.sock       │    │ (or 127.0.0.1:4851)                 │  │  │
│  │  │                 │    │                                     │  │  │
│  │  │ Local Claude    │    │ ◄── Remote connections              │  │  │
│  │  │ Code sessions   │    │     (authenticated)                 │  │  │
│  │  └─────────────────┘    │                                     │  │  │
│  │                         │ ◄── iOS app connections             │  │  │
│  │                         │     (SUBSCRIBE mode)                │  │  │
│  │                         └─────────────────────────────────────┘  │  │
│  │                              │                                   │  │
│  │                              ▼                                   │  │
│  │                    ┌─────────────────┐                           │  │
│  │                    │   Notch UI      │                           │  │
│  │                    │   (SwiftUI)     │                           │  │
│  │                    └─────────────────┘                           │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                              ▲                                         │
└──────────────────────────────│─────────────────────────────────────────┘
                               │
            ┌──────────────────┼──────────────────┐
            │                  │                  │
   TCP Connection      TCP Connection      TCP Connection
   AUTH + JSON         SUBSCRIBE mode      AUTH + JSON
            │                  │                  │
┌───────────▼──────┐ ┌────────▼────────┐ ┌───────▼──────────┐
│  REMOTE MACHINE  │ │    iOS APP      │ │  REMOTE MACHINE  │
│                  │ │                  │ │                  │
│  Claude Code CLI │ │  Session List   │ │  Claude Code CLI │
│        │         │ │  Permission     │ │        │         │
│        ▼         │ │  Approval UI    │ │        ▼         │
│  claude-nook-    │ │                  │ │  claude-nook-    │
│  state.py (hook) │ │  Approve/Deny   │ │  state.py (hook) │
│                  │ │  from iPhone    │ │                  │
└──────────────────┘ └─────────────────┘ └──────────────────┘
```

---

## iOS App Protocol

The iOS app uses a persistent SUBSCRIBE connection to receive real-time updates.

### Connection Flow

1. iOS sends: `AUTH <token>\n`
2. Server responds: `OK\n`
3. iOS sends: `SUBSCRIBE\n`
4. Server responds: `OK\n`
5. Server pushes: JSON messages (state, updates, permission requests)

### Message Types (Server → iOS)

| Message | Description |
|---------|-------------|
| `state` | Full session snapshot on connect |
| `sessionUpdate` | Session phase/activity change |
| `permissionRequest` | Tool waiting for approval |
| `permissionResolved` | Tool was approved/denied |
| `sessionRemoved` | Session ended |
| `ping` | Heartbeat (every 30s) |

### Message Types (iOS → Server)

| Message | Description |
|---------|-------------|
| `approve` | Allow tool execution |
| `deny` | Reject tool with optional reason |
| `pong` | Heartbeat response |

---

## Contributing Back

Once tested and working, this can be submitted as a PR to the original [claude-island](https://github.com/farouqaldori/claude-island) repository.

The changes are designed to be:
- Backwards compatible (Unix socket still works for local)
- Secure by default (TCP disabled until explicitly enabled)
- Easy to configure (environment variables, setup scripts)
- Cross-platform (macOS + iOS support)
