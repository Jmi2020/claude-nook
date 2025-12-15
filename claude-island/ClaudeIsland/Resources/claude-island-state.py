#!/usr/bin/env python3
"""
Claude Island Hook
- Sends session state to ClaudeIsland.app via Unix socket (local) or TCP (remote)
- For PermissionRequest: waits for user decision from the app
- Supports dual-mode: Unix socket for local, TCP for remote connections

Environment Variables:
  CLAUDE_ISLAND_MODE     - Connection mode: "auto" (default), "socket", or "tcp"
  CLAUDE_ISLAND_HOST     - TCP host (default: 127.0.0.1)
  CLAUDE_ISLAND_PORT     - TCP port (default: 4851)
  CLAUDE_ISLAND_TOKEN    - Auth token for TCP connections (required for TCP)
  CLAUDE_ISLAND_TIMEOUT  - Timeout in seconds (default: 300)
  CLAUDE_ISLAND_DEBUG    - Set to "1" for debug output to stderr
"""
import json
import os
import socket
import sys


class ConnectionConfig:
    """Load connection configuration from environment variables"""

    def __init__(self):
        self.socket_path = "/tmp/claude-island.sock"
        self.host = os.environ.get("CLAUDE_ISLAND_HOST", "127.0.0.1")
        self.port = int(os.environ.get("CLAUDE_ISLAND_PORT", "4851"))
        self.token = os.environ.get("CLAUDE_ISLAND_TOKEN", "")
        self.mode = os.environ.get("CLAUDE_ISLAND_MODE", "auto")  # auto, socket, tcp
        self.timeout = int(os.environ.get("CLAUDE_ISLAND_TIMEOUT", "300"))
        self.debug = os.environ.get("CLAUDE_ISLAND_DEBUG", "0") == "1"

    def log(self, message):
        """Log debug message to stderr if debug mode is enabled"""
        if self.debug:
            print(f"[claude-island] {message}", file=sys.stderr)


# Global config instance
config = ConnectionConfig()


def get_tty():
    """Get the TTY of the Claude process (parent)"""
    import subprocess

    # Get parent PID (Claude process)
    ppid = os.getppid()

    # Try to get TTY from ps command for the parent process
    try:
        result = subprocess.run(
            ["ps", "-p", str(ppid), "-o", "tty="],
            capture_output=True,
            text=True,
            timeout=2
        )
        tty = result.stdout.strip()
        if tty and tty != "??" and tty != "-":
            # ps returns just "ttys001", we need "/dev/ttys001"
            if not tty.startswith("/dev/"):
                tty = "/dev/" + tty
            return tty
    except Exception:
        pass

    # Fallback: try current process stdin/stdout
    try:
        return os.ttyname(sys.stdin.fileno())
    except (OSError, AttributeError):
        pass
    try:
        return os.ttyname(sys.stdout.fileno())
    except (OSError, AttributeError):
        pass
    return None


def send_via_socket(state, wait_for_response=False):
    """Send event via Unix domain socket (local connections)"""
    try:
        config.log(f"Connecting via Unix socket: {config.socket_path}")
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(config.timeout)
        sock.connect(config.socket_path)
        sock.sendall(json.dumps(state).encode())

        if wait_for_response:
            config.log("Waiting for response...")
            response = sock.recv(4096)
            sock.close()
            if response:
                config.log(f"Received response: {response.decode()}")
                return json.loads(response.decode())
        else:
            sock.close()

        config.log("Socket send successful")
        return None
    except FileNotFoundError:
        config.log(f"Socket not found: {config.socket_path}")
        return None
    except (socket.error, OSError) as e:
        config.log(f"Socket error: {e}")
        return None
    except json.JSONDecodeError as e:
        config.log(f"JSON decode error: {e}")
        return None


def send_via_tcp(state, wait_for_response=False):
    """Send event via TCP with authentication (remote connections)"""
    if not config.token:
        config.log("TCP mode requires CLAUDE_ISLAND_TOKEN to be set")
        return None

    try:
        config.log(f"Connecting via TCP: {config.host}:{config.port}")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(config.timeout)
        sock.connect((config.host, config.port))

        # Send authentication header
        auth_line = f"AUTH {config.token}\n"
        config.log("Sending auth...")
        sock.sendall(auth_line.encode())

        # Wait for auth response
        auth_response = b""
        while b"\n" not in auth_response:
            chunk = sock.recv(64)
            if not chunk:
                config.log("Connection closed during auth")
                sock.close()
                return None
            auth_response += chunk

        auth_result = auth_response.decode().strip()
        config.log(f"Auth response: {auth_result}")

        if auth_result != "OK":
            config.log(f"Authentication failed: {auth_result}")
            sock.close()
            return None

        # Send JSON payload
        config.log("Sending event payload...")
        sock.sendall(json.dumps(state).encode())

        if wait_for_response:
            config.log("Waiting for response...")
            response = sock.recv(4096)
            sock.close()
            if response:
                config.log(f"Received response: {response.decode()}")
                return json.loads(response.decode())
        else:
            sock.close()

        config.log("TCP send successful")
        return None
    except socket.timeout:
        config.log(f"TCP connection timed out to {config.host}:{config.port}")
        return None
    except ConnectionRefusedError:
        config.log(f"TCP connection refused to {config.host}:{config.port}")
        return None
    except (socket.error, OSError) as e:
        config.log(f"TCP error: {e}")
        return None
    except json.JSONDecodeError as e:
        config.log(f"JSON decode error: {e}")
        return None


def send_event(state, wait_for_response=False):
    """Send event using configured connection strategy"""
    config.log(f"Mode: {config.mode}, Event: {state.get('event')}")

    if config.mode == "socket":
        # Unix socket only
        return send_via_socket(state, wait_for_response)

    elif config.mode == "tcp":
        # TCP only
        return send_via_tcp(state, wait_for_response)

    else:
        # Auto mode: try Unix socket first, fall back to TCP if configured
        result = send_via_socket(state, wait_for_response)
        if result is not None or not wait_for_response:
            # Socket worked or we don't need a response
            # Check if socket actually connected (for non-response events)
            pass

        # For auto mode, try TCP as fallback if socket fails AND token is configured
        if config.token:
            # Try TCP if socket didn't work
            # We need to detect if socket actually failed vs just returning None
            # For simplicity in auto mode: socket first, if file doesn't exist try TCP
            if not os.path.exists(config.socket_path):
                config.log("Socket not found, trying TCP fallback...")
                return send_via_tcp(state, wait_for_response)

        return result


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(1)

    session_id = data.get("session_id", "unknown")
    event = data.get("hook_event_name", "")
    cwd = data.get("cwd", "")
    tool_input = data.get("tool_input", {})

    # Get process info
    claude_pid = os.getppid()
    tty = get_tty()

    # Build state object
    state = {
        "session_id": session_id,
        "cwd": cwd,
        "event": event,
        "pid": claude_pid,
        "tty": tty,
    }

    # Map events to status
    if event == "UserPromptSubmit":
        # User just sent a message - Claude is now processing
        state["status"] = "processing"

    elif event == "PreToolUse":
        state["status"] = "running_tool"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        # Send tool_use_id to Swift for caching
        tool_use_id_from_event = data.get("tool_use_id")
        if tool_use_id_from_event:
            state["tool_use_id"] = tool_use_id_from_event

    elif event == "PostToolUse":
        state["status"] = "processing"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        # Send tool_use_id so Swift can cancel the specific pending permission
        tool_use_id_from_event = data.get("tool_use_id")
        if tool_use_id_from_event:
            state["tool_use_id"] = tool_use_id_from_event

    elif event == "PermissionRequest":
        # This is where we can control the permission
        state["status"] = "waiting_for_approval"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        # tool_use_id lookup handled by Swift-side cache from PreToolUse

        # Send to app and wait for decision
        response = send_event(state, wait_for_response=True)

        if response:
            decision = response.get("decision", "ask")
            reason = response.get("reason", "")

            if decision == "allow":
                # Output JSON to approve
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {"behavior": "allow"},
                    }
                }
                print(json.dumps(output))
                sys.exit(0)

            elif decision == "deny":
                # Output JSON to deny
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {
                            "behavior": "deny",
                            "message": reason or "Denied by user via ClaudeIsland",
                        },
                    }
                }
                print(json.dumps(output))
                sys.exit(0)

        # No response or "ask" - let Claude Code show its normal UI
        sys.exit(0)

    elif event == "Notification":
        notification_type = data.get("notification_type")
        # Skip permission_prompt - PermissionRequest hook handles this with better info
        if notification_type == "permission_prompt":
            sys.exit(0)
        elif notification_type == "idle_prompt":
            state["status"] = "waiting_for_input"
        else:
            state["status"] = "notification"
        state["notification_type"] = notification_type
        state["message"] = data.get("message")

    elif event == "Stop":
        state["status"] = "waiting_for_input"

    elif event == "SubagentStop":
        # SubagentStop fires when a subagent completes - usually means back to waiting
        state["status"] = "waiting_for_input"

    elif event == "SessionStart":
        # New session starts waiting for user input
        state["status"] = "waiting_for_input"

    elif event == "SessionEnd":
        state["status"] = "ended"

    elif event == "PreCompact":
        # Context is being compacted (manual or auto)
        state["status"] = "compacting"

    else:
        state["status"] = "unknown"

    # Send to socket (fire and forget for non-permission events)
    send_event(state)


if __name__ == "__main__":
    main()
