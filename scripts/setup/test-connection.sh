#!/bin/bash
#
# Test Claude Nook TCP connection
# Run this on the REMOTE machine to verify connectivity
#

set -e

# Load configuration
CONFIG_FILE="$HOME/.config/claude-nook/claude-nook.env"
if [[ -f "$CONFIG_FILE" ]]; then
    set -a
    source "$CONFIG_FILE"
    set +a
fi

HOST="${CLAUDE_NOOK_HOST:-127.0.0.1}"
PORT="${CLAUDE_NOOK_PORT:-4851}"
TOKEN="${CLAUDE_NOOK_TOKEN:-}"
SOCKET_PATH="/tmp/claude-nook.sock"

echo "=== Claude Nook Connection Test ==="
echo ""
echo "Configuration:"
echo "  Host:   $HOST"
echo "  Port:   $PORT"
echo "  Token:  ${TOKEN:0:4}...${TOKEN: -4} ($(echo -n "$TOKEN" | wc -c | tr -d ' ') chars)"
echo ""

# Test 1: Unix socket (local only)
echo "1. Testing Unix socket ($SOCKET_PATH)..."
if [[ -S "$SOCKET_PATH" ]]; then
    echo "   [OK] Socket exists - Claude Nook is running locally"
else
    echo "   [--] Socket not found (expected for remote machines)"
fi

# Test 2: TCP port reachability
echo ""
echo "2. Testing TCP port reachability ($HOST:$PORT)..."

# Try different methods to test connectivity
TCP_OK=false

if command -v nc &> /dev/null; then
    # Use netcat
    if echo "" | timeout 5 nc -w 2 "$HOST" "$PORT" 2>/dev/null; then
        TCP_OK=true
    fi
elif command -v bash &> /dev/null; then
    # Use bash /dev/tcp
    if timeout 5 bash -c "echo '' > /dev/tcp/$HOST/$PORT" 2>/dev/null; then
        TCP_OK=true
    fi
fi

if [[ "$TCP_OK" == "true" ]]; then
    echo "   [OK] TCP port is reachable"
else
    echo "   [FAIL] Cannot connect to $HOST:$PORT"
    echo ""
    echo "   Troubleshooting:"
    echo "   - Is Claude Nook running on your Mac?"
    echo "   - Is TCP enabled in Claude Nook settings?"
    echo "   - Check firewall settings on your Mac"
    echo ""
    echo "   For SSH tunnel:"
    echo "     ssh -L $PORT:localhost:$PORT your-mac-hostname"
    echo ""
    echo "   For Tailscale:"
    echo "     Verify both machines are on the same Tailscale network"
    exit 1
fi

# Test 3: Authentication
echo ""
echo "3. Testing authentication..."

if [[ -z "$TOKEN" ]]; then
    echo "   [SKIP] No token configured (CLAUDE_NOOK_TOKEN not set)"
    exit 0
fi

# Create test payload
TEST_PAYLOAD=$(cat << EOF
{
  "session_id": "connection-test-$(date +%s)",
  "cwd": "/tmp",
  "event": "Notification",
  "status": "notification",
  "notification_type": "connection_test",
  "message": "Connection test from remote at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)

# Send authenticated request
AUTH_RESPONSE=""
if command -v nc &> /dev/null; then
    AUTH_RESPONSE=$(echo -e "AUTH $TOKEN\n" | timeout 5 nc -w 2 "$HOST" "$PORT" 2>&1 | head -1) || true
fi

if [[ "$AUTH_RESPONSE" == "OK" ]]; then
    echo "   [OK] Authentication successful"

    # Try sending full payload
    echo ""
    echo "4. Testing event delivery..."

    FULL_RESPONSE=$( (echo -e "AUTH $TOKEN\n"; sleep 0.1; echo "$TEST_PAYLOAD") | timeout 5 nc -w 2 "$HOST" "$PORT" 2>&1) || true

    if [[ "$FULL_RESPONSE" == "OK"* ]]; then
        echo "   [OK] Event sent successfully"
        echo ""
        echo "   If Claude Nook is visible, you should see a notification appear!"
    else
        echo "   [WARN] Event may not have been delivered: $FULL_RESPONSE"
    fi
else
    echo "   [FAIL] Authentication failed: $AUTH_RESPONSE"
    echo ""
    echo "   Check that your token matches the one in Claude Nook settings."
    exit 1
fi

echo ""
echo "=== All Tests Passed ==="
echo ""
echo "Claude Nook is reachable and authenticated at $HOST:$PORT"
echo "Remote Claude Code sessions should now sync with your Mac."
