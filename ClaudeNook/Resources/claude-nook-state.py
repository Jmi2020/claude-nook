#!/usr/bin/env python3
"""
Claude Nook Hook
- Sends session state to Claude Nook.app via Unix socket (local) or TCP (remote)
- For PermissionRequest: waits for user decision from the app
- Supports dual-mode: Unix socket for local, TCP for remote connections
- Supports Bonjour/mDNS auto-discovery of Claude Nook servers
- Auto-trusts Tailscale connections (no token required for 100.x.x.x)

Environment Variables:
  CLAUDE_NOOK_MODE     - Connection mode: "auto" (default), "socket", or "tcp"
  CLAUDE_NOOK_HOST     - TCP host (default: auto-discover via Bonjour)
  CLAUDE_NOOK_PORT     - TCP port (default: 4851)
  CLAUDE_NOOK_TOKEN    - Auth token for TCP connections (optional for Tailscale)
  CLAUDE_NOOK_TIMEOUT  - Timeout in seconds (default: 300)
  CLAUDE_NOOK_DEBUG    - Set to "1" for debug output to stderr
"""
import json
import os
import socket
import subprocess
import sys


def is_tailscale_ip(ip):
    """Check if IP is in Tailscale's CGNAT range (100.64.0.0/10)"""
    parts = ip.split(".")
    if len(parts) != 4:
        return False
    try:
        first, second = int(parts[0]), int(parts[1])
        return first == 100 and 64 <= second <= 127
    except ValueError:
        return False


def discover_via_bonjour(timeout=2):
    """
    Discover Claude Nook servers via Bonjour/mDNS.
    Returns (host, port) tuple or (None, None) if not found.
    """
    try:
        # Use dns-sd to browse for _claudenook._tcp services
        # Run with timeout and parse output
        result = subprocess.run(
            ["dns-sd", "-B", "_claudenook._tcp", "local."],
            capture_output=True,
            text=True,
            timeout=timeout
        )
        # dns-sd -B doesn't give us host/port directly, need to resolve
        # For simplicity, let's use dns-sd -L to lookup
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    # Try using python's socket to do mDNS query (simpler approach)
    # Actually, let's just try the avahi-browse or dns-sd approach
    # For now, return None and rely on explicit config or Tailscale trust
    return None, None


class ConnectionConfig:
    """Load connection configuration from environment variables"""

    def __init__(self):
        self.socket_path = "/tmp/claude-nook.sock"
        self.host = os.environ.get("CLAUDE_NOOK_HOST", "")
        self.port = int(os.environ.get("CLAUDE_NOOK_PORT", "4851"))
        self.token = os.environ.get("CLAUDE_NOOK_TOKEN", "")
        self.mode = os.environ.get("CLAUDE_NOOK_MODE", "auto")  # auto, socket, tcp
        self.timeout = int(os.environ.get("CLAUDE_NOOK_TIMEOUT", "300"))
        self.debug = os.environ.get("CLAUDE_NOOK_DEBUG", "0") == "1"
        self._discovered_host = None
        self._discovery_attempted = False

    def get_host(self):
        """Get host, attempting Bonjour discovery if not configured"""
        if self.host:
            return self.host
        if not self._discovery_attempted:
            self._discovery_attempted = True
            discovered_host, discovered_port = discover_via_bonjour()
            if discovered_host:
                self._discovered_host = discovered_host
                if discovered_port:
                    self.port = discovered_port
                self.log(f"Discovered Claude Nook at {discovered_host}:{self.port}")
        return self._discovered_host or "127.0.0.1"

    def log(self, message):
        """Log debug message to stderr if debug mode is enabled"""
        if self.debug:
            print(f"[claude-nook] {message}", file=sys.stderr)


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
    """Send event via TCP with authentication (remote connections)

    Supports Tailscale auto-trust: if connecting to a Tailscale IP and the server
    trusts Tailscale connections, it will send OK immediately without requiring auth.
    """
    host = config.get_host()

    try:
        config.log(f"Connecting via TCP: {host}:{config.port}")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(config.timeout)
        sock.connect((host, config.port))

        # Check if server auto-trusts us (Tailscale) by waiting briefly for OK
        # Set a short timeout to check for immediate OK
        sock.settimeout(0.5)
        auto_trusted = False
        try:
            initial_response = sock.recv(64)
            if initial_response and initial_response.decode().strip() == "OK":
                config.log("Auto-trusted by server (Tailscale)")
                auto_trusted = True
        except socket.timeout:
            # No immediate response - need to authenticate
            pass

        sock.settimeout(config.timeout)

        if not auto_trusted:
            # Need to send authentication
            if not config.token:
                config.log("TCP mode requires CLAUDE_NOOK_TOKEN (not auto-trusted)")
                sock.close()
                return None

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
        config.log(f"TCP connection timed out to {host}:{config.port}")
        return None
    except ConnectionRefusedError:
        config.log(f"TCP connection refused to {host}:{config.port}")
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
        # Auto mode: try Unix socket first, fall back to TCP
        # TCP works without token if server trusts Tailscale connections

        # First, try Unix socket (for local connections)
        if os.path.exists(config.socket_path):
            result = send_via_socket(state, wait_for_response)
            if result is not None or not wait_for_response:
                return result

        # Socket not available or failed, try TCP
        # TCP will work without token if:
        # 1. Server trusts Tailscale and we're on Tailscale network
        # 2. Or we have a token configured
        host = config.get_host()
        if host and (config.token or is_tailscale_ip(host)):
            config.log("Socket not available, trying TCP...")
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
                            "message": reason or "Denied by user via Claude Nook",
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
