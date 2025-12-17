#!/bin/bash
#
# Setup Claude Nook on the LOCAL macOS machine (where the app runs)
# This script prepares the host machine to accept remote connections
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config/claude-nook"
TOKEN_FILE="$CONFIG_DIR/token"

echo "=== Claude Nook Local Setup ==="
echo ""
echo "This script configures your Mac to accept remote Claude Nook connections."
echo ""

# Create config directory
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

# Generate token if not exists
if [[ -f "$TOKEN_FILE" ]]; then
    echo "Existing token found at $TOKEN_FILE"
    read -p "Generate new token? (y/N): " REGEN
    if [[ "$REGEN" == "y" || "$REGEN" == "Y" ]]; then
        "$SCRIPT_DIR/generate-token.sh" --save "$TOKEN_FILE"
    fi
else
    echo "Generating new auth token..."
    "$SCRIPT_DIR/generate-token.sh" --save "$TOKEN_FILE"
fi

TOKEN=$(cat "$TOKEN_FILE")

# Detect local IP addresses
echo ""
echo "=== Network Interfaces ==="
echo ""
echo "Your Mac's IP addresses:"

# Get all non-loopback IPv4 addresses
if command -v ifconfig &> /dev/null; then
    ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print "  - " $2}'
fi

# Check for Tailscale
if command -v tailscale &> /dev/null; then
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
    if [[ -n "$TAILSCALE_IP" ]]; then
        echo ""
        echo "Tailscale IP:"
        echo "  - $TAILSCALE_IP (recommended for remote access)"
    fi
fi

# Default port
PORT="${CLAUDE_NOOK_PORT:-4851}"

# Create setup info file for sharing
INFO_FILE="$CONFIG_DIR/remote-setup-info.txt"
cat > "$INFO_FILE" << EOF
# Claude Nook Remote Setup Information
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
#
# Share this information with your remote machine setup.
# IMPORTANT: Keep the token secure - anyone with it can send events to your app.

# Connection Settings
CLAUDE_NOOK_HOST=<your-ip-or-tailscale-hostname>
CLAUDE_NOOK_PORT=$PORT
CLAUDE_NOOK_TOKEN=$TOKEN
CLAUDE_NOOK_MODE=tcp
EOF

chmod 600 "$INFO_FILE"

echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Enable TCP in Claude Nook app:"
echo "   - Open Claude Nook settings (click the notch)"
echo "   - Go to 'Remote Access' section"
echo "   - Select 'Localhost Only' (for SSH tunnel) or 'All Interfaces' (for direct/Tailscale)"
echo "   - Copy the token shown there, or use the one generated here"
echo ""
echo "2. Set up your connection method:"
echo ""
echo "   Option A - SSH Tunnel (most secure):"
echo "     On remote machine:"
echo "     ssh -L $PORT:localhost:$PORT your-mac-hostname"
echo ""
echo "   Option B - Tailscale (easiest):"
echo "     Use your Tailscale hostname directly"
echo ""
echo "   Option C - Direct (local network only):"
echo "     Use your Mac's IP address"
echo ""
echo "3. On the REMOTE machine, run:"
echo "   ./remote-setup.sh"
echo ""
echo "4. Test the connection:"
echo "   ./test-connection.sh"
echo ""
echo "=== Configuration Files ==="
echo ""
echo "Token:      $TOKEN_FILE"
echo "Setup info: $INFO_FILE"
echo ""
echo "Your auth token (copy this for remote setup):"
echo "$TOKEN"
