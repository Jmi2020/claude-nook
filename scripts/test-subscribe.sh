#!/bin/bash
#
# Test SUBSCRIBE mode for iOS client connections
# Usage: ./test-subscribe.sh [host] [port] [token]
#

HOST="${1:-127.0.0.1}"
PORT="${2:-4851}"
TOKEN="${3:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Testing SUBSCRIBE mode on ${HOST}:${PORT}${NC}"

# Check if nc (netcat) is available
if ! command -v nc &> /dev/null; then
    echo -e "${RED}Error: netcat (nc) is required but not installed${NC}"
    exit 1
fi

# Create a named pipe for bidirectional communication
PIPE_IN=$(mktemp -u)
PIPE_OUT=$(mktemp -u)
mkfifo "$PIPE_IN"
mkfifo "$PIPE_OUT"

# Cleanup on exit
cleanup() {
    rm -f "$PIPE_IN" "$PIPE_OUT"
    kill $NC_PID 2>/dev/null
}
trap cleanup EXIT

# Start netcat in background
nc "$HOST" "$PORT" < "$PIPE_IN" > "$PIPE_OUT" &
NC_PID=$!

# Open file descriptors
exec 3>"$PIPE_IN"
exec 4<"$PIPE_OUT"

echo -e "${YELLOW}1. Sending AUTH${NC}"

if [ -n "$TOKEN" ]; then
    echo "AUTH $TOKEN" >&3
else
    echo -e "${YELLOW}   (No token provided, trying without auth - will work for Tailscale IPs)${NC}"
fi

# Read response with timeout
read -t 5 response <&4
echo "   Response: $response"

if [[ "$response" != "OK" ]]; then
    echo -e "${RED}   Auth failed! Expected 'OK' but got '$response'${NC}"
    exit 1
fi
echo -e "${GREEN}   Auth successful!${NC}"

echo -e "${YELLOW}2. Sending SUBSCRIBE${NC}"
echo "SUBSCRIBE" >&3

echo -e "${YELLOW}3. Waiting for server messages...${NC}"
echo "   (Press Ctrl+C to stop)"
echo ""

# Read and display messages
while read -t 30 line <&4; do
    if [ -n "$line" ]; then
        echo -e "${GREEN}Received:${NC}"
        # Pretty print JSON if jq is available
        if command -v jq &> /dev/null; then
            echo "$line" | jq .
        else
            echo "$line"
        fi
        echo ""
    fi
done

echo -e "${YELLOW}Connection closed or timeout${NC}"
