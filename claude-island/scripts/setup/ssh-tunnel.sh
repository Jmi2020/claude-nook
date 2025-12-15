#!/bin/bash
#
# Create a persistent SSH tunnel for Claude Island
# Run this on the REMOTE machine to tunnel traffic to your Mac
#
# Usage: ./ssh-tunnel.sh <mac-hostname> [port]
#

set -e

# Configuration
REMOTE_HOST="${1:-}"
PORT="${2:-${CLAUDE_ISLAND_PORT:-4851}}"
RETRY_DELAY=5

# Validate input
if [[ -z "$REMOTE_HOST" ]]; then
    echo "Usage: $0 <mac-hostname> [port]"
    echo ""
    echo "Creates a persistent SSH tunnel for Claude Island TCP connections."
    echo ""
    echo "Arguments:"
    echo "  mac-hostname  Your Mac's hostname, IP, or SSH alias"
    echo "  port          TCP port (default: $PORT)"
    echo ""
    echo "Examples:"
    echo "  $0 mymac.local"
    echo "  $0 user@192.168.1.100"
    echo "  $0 mac-mini 4851"
    echo ""
    echo "The tunnel will automatically reconnect if the connection drops."
    exit 1
fi

echo "=== Claude Island SSH Tunnel ==="
echo ""
echo "Creating tunnel: localhost:$PORT -> $REMOTE_HOST:$PORT"
echo "Press Ctrl+C to stop"
echo ""

# Function to create tunnel
create_tunnel() {
    ssh -N -L "$PORT:localhost:$PORT" "$REMOTE_HOST" \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes \
        -o ConnectTimeout=10
}

# Check if autossh is available (better for persistent tunnels)
if command -v autossh &> /dev/null; then
    echo "Using autossh for automatic reconnection..."
    echo ""

    # Use autossh for more robust connection handling
    AUTOSSH_GATETIME=0 autossh -M 0 -N \
        -L "$PORT:localhost:$PORT" "$REMOTE_HOST" \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes \
        -o ConnectTimeout=10
else
    echo "Tip: Install 'autossh' for better automatic reconnection"
    echo ""

    # Manual reconnection loop
    while true; do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Connecting to $REMOTE_HOST..."

        if create_tunnel; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Tunnel closed normally"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Tunnel connection failed or dropped"
        fi

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Reconnecting in ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
    done
fi
