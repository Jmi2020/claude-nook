# Claude Island Remote Setup Guide

This guide explains how to use Claude Island with remote Claude Code sessions. This is useful when you're running Claude Code on a remote server (via SSH, VS Code Remote, etc.) but want the Claude Island UI to display on your local Mac.

## Architecture Overview

```
┌─────────────────────┐         ┌─────────────────────┐
│   Remote Machine    │         │    Your Mac         │
│                     │         │                     │
│  Claude Code CLI    │◄────────│  Claude Island.app  │
│        │            │   TCP   │        │            │
│        ▼            │         │        ▼            │
│  claude-island-     │────────►│  HookSocketServer   │
│  state.py (hook)    │  :4851  │        │            │
│                     │         │        ▼            │
│                     │         │  Notch UI Display   │
└─────────────────────┘         └─────────────────────┘
```

## Quick Start

### Option A: SSH Tunnel (Most Secure)

**On your Mac:**
1. Open Claude Island settings (click the notch)
2. Expand "Remote Access"
3. Select "Localhost Only"
4. Copy the auth token

**On the remote machine:**
```bash
# Create persistent SSH tunnel
ssh -L 4851:localhost:4851 your-mac-hostname

# Or use the setup script
./scripts/setup/ssh-tunnel.sh your-mac-hostname
```

### Option B: Direct Connection (Tailscale/Local Network)

**On your Mac:**
1. Open Claude Island settings
2. Expand "Remote Access"
3. Select "All Interfaces"
4. Note your Tailscale hostname or IP address
5. Copy the auth token

**On the remote machine:**
```bash
# Run the interactive setup
./scripts/setup/remote-setup.sh
```

## Detailed Setup Instructions

### Step 1: Configure Your Mac (Local Machine)

1. **Open Claude Island** and click the notch to open the menu

2. **Find Remote Access** in the settings list and click to expand

3. **Choose your bind mode:**
   - **Disabled**: TCP server is off (default)
   - **Localhost Only**: Accepts connections on 127.0.0.1 only (use with SSH tunnel)
   - **All Interfaces**: Accepts connections from any IP (use with Tailscale or local network)

4. **Note the configuration:**
   - Port (default: 4851)
   - Auth Token (64-character hex string)

5. **Copy setup info** using the "Copy Remote Setup Info" button

### Step 2: Configure the Remote Machine

#### Using the Setup Script (Recommended)

```bash
# Navigate to the scripts directory
cd /path/to/claude-island/scripts/setup

# Run the interactive setup
./remote-setup.sh
```

The script will:
- Ask for your Mac's hostname/IP
- Ask for the port and token
- Create the configuration file
- Add shell integration

#### Manual Configuration

1. **Create the config directory:**
   ```bash
   mkdir -p ~/.config/claude-island
   chmod 700 ~/.config/claude-island
   ```

2. **Create the environment file:**
   ```bash
   cat > ~/.config/claude-island/claude-island.env << EOF
   CLAUDE_ISLAND_HOST=your-mac-ip-or-hostname
   CLAUDE_ISLAND_PORT=4851
   CLAUDE_ISLAND_TOKEN=your-64-char-token
   CLAUDE_ISLAND_MODE=tcp
   EOF
   chmod 600 ~/.config/claude-island/claude-island.env
   ```

3. **Add to your shell profile** (~/.zshrc or ~/.bashrc):
   ```bash
   if [ -f ~/.config/claude-island/claude-island.env ]; then
       set -a
       source ~/.config/claude-island/claude-island.env
       set +a
   fi
   ```

4. **Copy the hook script** from your Mac:
   ```bash
   # The TCP-enabled hook script is bundled with Claude Island
   scp your-mac:/Applications/Claude\ Island.app/Contents/Resources/claude-island-state.py \
       ~/.claude/hooks/
   ```

### Step 3: Test the Connection

```bash
# Source the config if not already loaded
source ~/.config/claude-island/claude-island.env

# Run the test script
./scripts/setup/test-connection.sh
```

Or test manually:
```bash
# Test TCP connectivity
nc -zv $CLAUDE_ISLAND_HOST $CLAUDE_ISLAND_PORT

# Test authentication
echo -e "AUTH $CLAUDE_ISLAND_TOKEN\n" | nc -w 2 $CLAUDE_ISLAND_HOST $CLAUDE_ISLAND_PORT
# Should respond with "OK"
```

## Connection Methods

### SSH Port Forwarding

Best for: Secure connections over untrusted networks

```bash
# Basic tunnel
ssh -L 4851:localhost:4851 user@your-mac

# Persistent tunnel with auto-reconnect (requires autossh)
autossh -M 0 -N -L 4851:localhost:4851 user@your-mac

# Or use the helper script
./scripts/setup/ssh-tunnel.sh user@your-mac
```

**Advantages:**
- All traffic encrypted through SSH
- No firewall changes needed on Mac
- Works through NAT

**Requirements:**
- SSH access to your Mac
- Claude Island set to "Localhost Only" mode

### Tailscale / ZeroTier (Mesh VPN)

Best for: Always-on connectivity without manual tunnels

1. Install Tailscale on both machines
2. Set Claude Island to "All Interfaces" mode
3. Use your Mac's Tailscale hostname (e.g., `my-mac.tail12345.ts.net`)

**Advantages:**
- No manual tunnel management
- Works across networks
- Encrypted connection

**Requirements:**
- Tailscale installed on both machines
- Claude Island set to "All Interfaces" mode

### Direct Connection (Local Network)

Best for: Development on trusted local networks

1. Set Claude Island to "All Interfaces" mode
2. Use your Mac's local IP (e.g., `192.168.1.100`)
3. Ensure firewall allows port 4851

**Advantages:**
- Simplest setup
- Lowest latency

**Requirements:**
- Both machines on same network
- Firewall configured to allow connection

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_ISLAND_MODE` | Connection mode: `auto`, `socket`, `tcp` | `auto` |
| `CLAUDE_ISLAND_HOST` | TCP host for remote connection | `127.0.0.1` |
| `CLAUDE_ISLAND_PORT` | TCP port number | `4851` |
| `CLAUDE_ISLAND_TOKEN` | Authentication token | (none) |
| `CLAUDE_ISLAND_TIMEOUT` | Timeout for permission requests (seconds) | `300` |
| `CLAUDE_ISLAND_DEBUG` | Enable debug output to stderr | `0` |

### Connection Modes

- **`auto`** (default): Try Unix socket first, fall back to TCP if socket doesn't exist and token is configured
- **`socket`**: Unix socket only (local connections)
- **`tcp`**: TCP only (remote connections)

## Troubleshooting

### Connection Refused

```
[FAIL] Cannot connect to host:port
```

**Check:**
1. Is Claude Island running on your Mac?
2. Is TCP enabled in Claude Island settings?
3. Is the correct bind mode selected?
4. Check firewall settings on your Mac

For SSH tunnel:
```bash
# Is the tunnel running?
ps aux | grep "ssh.*4851"

# Can you connect locally on the Mac?
nc -zv localhost 4851
```

### Authentication Failed

```
[FAIL] Authentication failed: ERR: Invalid token
```

**Check:**
1. Token matches between Mac and remote config
2. No extra whitespace in token
3. Token wasn't regenerated on the Mac

### Socket Not Found (Local)

```
[--] Socket not found: /tmp/claude-island.sock
```

This is expected on remote machines. Make sure `CLAUDE_ISLAND_MODE=tcp` is set.

### Debug Mode

Enable debug output to see detailed connection information:

```bash
export CLAUDE_ISLAND_DEBUG=1
claude  # Run Claude Code - debug output goes to stderr
```

## Security Considerations

1. **Token Security**: The auth token provides access to send events to Claude Island. Keep it secure and don't commit it to version control.

2. **Bind Mode**: Use "Localhost Only" with SSH tunnels when possible. Only use "All Interfaces" on trusted networks or with Tailscale.

3. **Firewall**: If using direct connections, ensure your Mac's firewall is properly configured.

4. **Token Rotation**: Regenerate the token periodically, especially if you suspect it may have been compromised.

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `generate-token.sh` | Generate a new secure auth token |
| `local-setup.sh` | Configure the Mac (local machine) |
| `remote-setup.sh` | Configure the remote machine |
| `test-connection.sh` | Test TCP connectivity and auth |
| `ssh-tunnel.sh` | Create persistent SSH tunnel |

## Frequently Asked Questions

**Q: Can I use this with VS Code Remote SSH?**
A: Yes! Set up an SSH tunnel or use Tailscale. The hook script will connect via TCP when the Unix socket isn't available.

**Q: Does this work with Docker containers?**
A: Yes, as long as the container can reach your Mac's IP/hostname on port 4851.

**Q: Can multiple remote machines connect to one Mac?**
A: Yes, Claude Island can handle multiple concurrent TCP connections.

**Q: What happens if the connection drops during a permission request?**
A: Claude Code's permission prompt will show in the terminal as a fallback.
