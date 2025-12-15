<div align="center">
  <img src="ClaudeIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Logo" width="100" height="100">
  <h3 align="center">Claude Island TCP</h3>
  <p align="center">
    A macOS menu bar app that brings Dynamic Island-style notifications to Claude Code CLI sessions — now with remote TCP support.
    <br />
    <br />
    <em>Fork of <a href="https://github.com/farouqaldori/claude-island">farouqaldori/claude-island</a> with TCP socket support for remote sessions.</em>
  </p>
</div>

## What's New in This Fork

This fork adds **TCP socket support** for remote Claude Code sessions:

- **Remote Notifications** — Get Claude Island notifications on your Mac while running Claude Code on remote servers, VMs, or containers
- **Dual-Mode Operation** — Unix socket (local) + TCP (remote) run simultaneously
- **Token Authentication** — Secure 64-character hex token for remote connections
- **Multiple Connection Methods** — SSH tunnels, Tailscale/mesh VPNs, or direct LAN connections
- **Easy Setup** — Configuration scripts and environment variable-based setup

## Features

- **Notch UI** — Animated overlay that expands from the MacBook notch
- **Live Session Monitoring** — Track multiple Claude Code sessions in real-time
- **Permission Approvals** — Approve or deny tool executions directly from the notch
- **Chat History** — View full conversation history with markdown rendering
- **Auto-Setup** — Hooks install automatically on first launch
- **Remote Access** — TCP support for remote Claude Code sessions (new!)

## Requirements

- macOS 14.0+ (Sonoma) or macOS 15.0+ (Sequoia)
- Claude Code CLI
- For remote connections: Network access between machines (SSH, Tailscale, or LAN)

## Install

Download the latest release or build from source:

```bash
git clone https://github.com/Jmi2020/claude-island-tcp.git
cd claude-island-tcp/claude-island
xcodebuild -scheme ClaudeIsland -configuration Release build
```

The built app will be in `~/Library/Developer/Xcode/DerivedData/ClaudeIsland-*/Build/Products/Release/`

## Quick Start

### Local Use (Same Machine)

Just launch Claude Island — it automatically installs hooks and works with local Claude Code sessions via Unix socket.

### Remote Use (Different Machine)

**On your Mac (receives notifications):**

1. Launch Claude Island
2. Click the notch → expand "Remote Access"
3. Select "All Interfaces" (or "Localhost Only" for SSH tunnel)
4. Click "Copy" to copy the auth token

**On the remote machine (runs Claude Code):**

```bash
# Clone the repo
git clone https://github.com/Jmi2020/claude-island-tcp.git ~/claude-island-tcp

# Install the hook script
mkdir -p ~/.claude/hooks
cp ~/claude-island-tcp/claude-island/ClaudeIsland/Resources/claude-island-state.py ~/.claude/hooks/
chmod +x ~/.claude/hooks/claude-island-state.py

# Create config
mkdir -p ~/.config/claude-island
cat > ~/.config/claude-island/claude-island.env << EOF
CLAUDE_ISLAND_HOST=your-mac-ip-or-hostname
CLAUDE_ISLAND_PORT=4851
CLAUDE_ISLAND_TOKEN=your-64-char-token-here
CLAUDE_ISLAND_MODE=tcp
EOF
chmod 600 ~/.config/claude-island/claude-island.env

# Add to shell profile (~/.zshrc or ~/.bashrc)
echo '
if [ -f ~/.config/claude-island/claude-island.env ]; then
    set -a; source ~/.config/claude-island/claude-island.env; set +a
fi' >> ~/.zshrc

# Load and test
source ~/.zshrc
nc -zv $CLAUDE_ISLAND_HOST $CLAUDE_ISLAND_PORT
```

For detailed instructions, see [REMOTE_SETUP.md](REMOTE_SETUP.md).

## How It Works

### Local Mode
Claude Island installs hooks into `~/.claude/hooks/` that communicate session state via a Unix socket at `/tmp/claude-island.sock`.

### Remote Mode
The TCP-enabled hook script connects to Claude Island over the network:

```
┌─────────────────────┐         ┌─────────────────────┐
│   Remote Machine    │         │    Your Mac         │
│                     │         │                     │
│  Claude Code CLI    │         │  Claude Island.app  │
│        │            │         │        │            │
│        ▼            │         │        ▼            │
│  claude-island-     │────────►│  TCP Server :4851   │
│  state.py (hook)    │  AUTH   │        │            │
│                     │  +JSON  │        ▼            │
│                     │         │  Notch UI Display   │
└─────────────────────┘         └─────────────────────┘
```

The hook script:
1. Sends `AUTH <token>\n` for authentication
2. Receives `OK\n` on success
3. Sends JSON event payload
4. For permission requests, waits for `ALLOW` or `DENY` response

## Connection Methods

| Method | Best For | Mac Setting |
|--------|----------|-------------|
| **SSH Tunnel** | Secure connections over internet | Localhost Only |
| **Tailscale** | Always-on without manual tunnels | All Interfaces |
| **Direct LAN** | Same trusted network | All Interfaces |

See [REMOTE_SETUP.md](REMOTE_SETUP.md) for detailed setup instructions for each method.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_ISLAND_MODE` | `auto`, `socket`, or `tcp` | `auto` |
| `CLAUDE_ISLAND_HOST` | Mac's IP or hostname | `127.0.0.1` |
| `CLAUDE_ISLAND_PORT` | TCP port | `4851` |
| `CLAUDE_ISLAND_TOKEN` | 64-char auth token | (none) |
| `CLAUDE_ISLAND_DEBUG` | Enable debug output | `0` |

## Security

- **Token Authentication**: All TCP connections require a 64-character cryptographic token
- **Bind Modes**: Choose between localhost-only (for SSH tunnels) or all-interfaces
- **No Secrets in Repo**: Tokens stored in user config files with restricted permissions

## Documentation

- [REMOTE_SETUP.md](REMOTE_SETUP.md) — Detailed remote setup guide
- [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md) — Technical implementation details

## Contributing

This fork is designed for potential upstream contribution. The TCP features are:
- Backwards compatible (Unix socket still works)
- Secure by default (TCP disabled until enabled)
- Easy to configure (environment variables)

## Analytics

Claude Island uses Mixpanel to collect anonymous usage data:
- **App Launched** — App version, build number, macOS version
- **Session Started** — When a new Claude Code session is detected

No personal data or conversation content is collected.

## License

Apache 2.0

## Credits

- Original [claude-island](https://github.com/farouqaldori/claude-island) by [@farouqaldori](https://github.com/farouqaldori)
- TCP remote support by [@Jmi2020](https://github.com/Jmi2020)
