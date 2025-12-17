#!/bin/bash
#
# Generate a secure auth token for Claude Nook TCP connections
# Usage: ./generate-token.sh [--save [filepath]]
#

set -e

# Generate a 64-character hex token (32 bytes of randomness)
generate_token() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 32
    elif [ -f /dev/urandom ]; then
        head -c 32 /dev/urandom | xxd -p | tr -d '\n'
    else
        # Fallback: use date and process info (less secure, but works)
        echo "Warning: Using less secure token generation" >&2
        echo "$(date +%s%N)$$" | sha256sum | head -c 64
    fi
}

TOKEN=$(generate_token)

echo "=== Claude Nook Auth Token ==="
echo ""
echo "Generated token:"
echo "  $TOKEN"
echo ""
echo "Add to your environment (on the REMOTE machine):"
echo "  export CLAUDE_NOOK_TOKEN=\"$TOKEN\""
echo ""
echo "Or add to ~/.config/claude-nook/claude-nook.env:"
echo "  CLAUDE_NOOK_TOKEN=$TOKEN"
echo ""

# Optionally save to file
if [[ "$1" == "--save" ]]; then
    TOKEN_FILE="${2:-$HOME/.config/claude-nook/token}"
    mkdir -p "$(dirname "$TOKEN_FILE")"
    echo "$TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    echo "Token saved to: $TOKEN_FILE"
fi
