#!/bin/bash
#
# Setup Claude Island hooks on a REMOTE machine running Claude Code
# This script configures the hook to connect to your Mac via TCP
#

set -e

CONFIG_DIR="$HOME/.config/claude-island"
HOOKS_DIR="$HOME/.claude/hooks"
ENV_FILE="$CONFIG_DIR/claude-island.env"

echo "=== Claude Island Remote Setup ==="
echo ""
echo "This script configures Claude Code hooks to connect to Claude Island"
echo "running on your Mac via TCP."
echo ""

# Create directories
mkdir -p "$CONFIG_DIR"
mkdir -p "$HOOKS_DIR"
chmod 700 "$CONFIG_DIR"

# Check if already configured
if [[ -f "$ENV_FILE" ]]; then
    echo "Existing configuration found at $ENV_FILE"
    cat "$ENV_FILE" | grep -v "^#" | grep -v "^$"
    echo ""
    read -p "Reconfigure? (y/N): " RECONFIG
    if [[ "$RECONFIG" != "y" && "$RECONFIG" != "Y" ]]; then
        echo "Keeping existing configuration."
        exit 0
    fi
fi

# Interactive configuration
echo ""
echo "Enter connection details from your Mac's Claude Island setup:"
echo "(These are shown in the Claude Island app settings or local-setup.sh output)"
echo ""

read -p "Claude Island host (IP, hostname, or Tailscale name): " HOST
while [[ -z "$HOST" ]]; do
    echo "Host is required."
    read -p "Claude Island host: " HOST
done

read -p "Claude Island port [4851]: " PORT
PORT=${PORT:-4851}

read -p "Auth token: " TOKEN
while [[ -z "$TOKEN" ]]; do
    echo "Token is required for TCP connections."
    read -p "Auth token: " TOKEN
done

# Create environment file
cat > "$ENV_FILE" << EOF
# Claude Island Remote Configuration
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# TCP Connection Settings
CLAUDE_ISLAND_HOST=$HOST
CLAUDE_ISLAND_PORT=$PORT
CLAUDE_ISLAND_TOKEN=$TOKEN
CLAUDE_ISLAND_MODE=tcp

# Optional: Uncomment for debug output
# CLAUDE_ISLAND_DEBUG=1
EOF

chmod 600 "$ENV_FILE"

# Detect shell and add to profile
echo ""
echo "=== Shell Integration ==="

SHELL_RC=""
if [[ -n "$ZSH_VERSION" ]] || [[ "$SHELL" == *"zsh"* ]]; then
    SHELL_RC="$HOME/.zshrc"
elif [[ -n "$BASH_VERSION" ]] || [[ "$SHELL" == *"bash"* ]]; then
    SHELL_RC="$HOME/.bashrc"
fi

if [[ -n "$SHELL_RC" && -f "$SHELL_RC" ]]; then
    if grep -q "claude-island.env" "$SHELL_RC" 2>/dev/null; then
        echo "Shell integration already present in $SHELL_RC"
    else
        echo "" >> "$SHELL_RC"
        echo "# Claude Island remote configuration" >> "$SHELL_RC"
        echo 'if [ -f ~/.config/claude-island/claude-island.env ]; then' >> "$SHELL_RC"
        echo '    set -a' >> "$SHELL_RC"
        echo '    source ~/.config/claude-island/claude-island.env' >> "$SHELL_RC"
        echo '    set +a' >> "$SHELL_RC"
        echo 'fi' >> "$SHELL_RC"
        echo "Added environment loading to $SHELL_RC"
    fi
else
    echo "Could not detect shell RC file."
    echo "Add the following to your shell profile manually:"
    echo ""
    echo '  if [ -f ~/.config/claude-island/claude-island.env ]; then'
    echo '      set -a'
    echo '      source ~/.config/claude-island/claude-island.env'
    echo '      set +a'
    echo '  fi'
fi

# Check for hook script
echo ""
echo "=== Hook Script ==="

HOOK_SCRIPT="$HOOKS_DIR/claude-island-state.py"
if [[ -f "$HOOK_SCRIPT" ]]; then
    # Check if script has TCP support (look for CLAUDE_ISLAND_HOST)
    if grep -q "CLAUDE_ISLAND_HOST" "$HOOK_SCRIPT"; then
        echo "Hook script with TCP support found at $HOOK_SCRIPT"
    else
        echo "Hook script found but may not have TCP support."
        echo "Consider updating it from the Claude Island repository."
    fi
else
    echo "Hook script not found at $HOOK_SCRIPT"
    echo ""
    echo "You need to:"
    echo "1. Copy claude-island-state.py from the Claude Island app to $HOOK_SCRIPT"
    echo "2. Make sure it's the TCP-enabled version"
    echo ""
    echo "On your Mac, find it at:"
    echo "  /Applications/Claude Island.app/Contents/Resources/claude-island-state.py"
    echo ""
    echo "Or download from GitHub (when available):"
    echo "  curl -sL 'https://raw.githubusercontent.com/your-repo/claude-island/main/ClaudeIsland/Resources/claude-island-state.py' -o '$HOOK_SCRIPT'"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Configuration saved to: $ENV_FILE"
echo ""
echo "To activate now (without restarting shell):"
echo "  source $ENV_FILE"
echo ""
echo "To test the connection:"
echo "  ./test-connection.sh"
echo ""
echo "Or manually test with netcat:"
echo "  echo -e 'AUTH $TOKEN\n' | nc -w 2 $HOST $PORT"
