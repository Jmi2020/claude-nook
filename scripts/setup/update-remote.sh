#!/bin/bash
#
# Update Claude Nook hook script on a remote machine
# Run this ON THE REMOTE MACHINE to get the latest hook script
#

set -e

HOOKS_DIR="$HOME/.claude/hooks"
HOOK_SCRIPT="$HOOKS_DIR/claude-nook-state.py"

# GitHub raw URL (update this if you publish to a different repo)
GITHUB_RAW="https://raw.githubusercontent.com/jmlingeman/claude-nook/main/ClaudeNook/Resources/claude-nook-state.py"

echo "=== Claude Nook Remote Update ==="
echo ""

# Check if hook exists
if [[ ! -f "$HOOK_SCRIPT" ]]; then
    echo "Hook script not found at $HOOK_SCRIPT"
    echo "Run the full setup first: remote-setup.sh"
    exit 1
fi

# Backup existing
cp "$HOOK_SCRIPT" "$HOOK_SCRIPT.bak"
echo "Backed up existing script to $HOOK_SCRIPT.bak"

# Download new version
echo "Downloading latest hook script..."
if curl -fsSL "$GITHUB_RAW" -o "$HOOK_SCRIPT.new"; then
    mv "$HOOK_SCRIPT.new" "$HOOK_SCRIPT"
    chmod +x "$HOOK_SCRIPT"
    echo "✓ Updated successfully!"
    echo ""
    echo "Restart any Claude Code sessions to use the new hook."
else
    echo "✗ Download failed. Keeping existing version."
    rm -f "$HOOK_SCRIPT.new"
    exit 1
fi
