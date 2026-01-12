#!/bin/bash
# SSH Agent Relay - Bridges host's ssh-agent to containers via TCP

set -e

# Find the SSH agent socket
if [ -z "$SSH_AUTH_SOCK" ]; then
	# Try macOS default location
	SSH_AGENT_SOCK="$HOME/Library/Group Containers/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.apple.ssh_agent.recent.plist"

	# If not found, try Linux default
	if [ ! -e "$SSH_AGENT_SOCK" ]; then
		SSH_AGENT_SOCK="/run/user/1000/keyring/ssh"
	fi

	# If still not found, try common Linux location
	if [ ! -e "$SSH_AGENT_SOCK" ]; then
		SSH_AGENT_SOCK="/tmp/ssh-*"
	fi
else
	SSH_AGENT_SOCK="$SSH_AUTH_SOCK"
fi

# Expand wildcard if necessary
SSH_AGENT_SOCK=$(eval echo "$SSH_AGENT_SOCK")

# Validate socket exists
if [ ! -e "$SSH_AGENT_SOCK" ]; then
	echo "Error: Could not find SSH agent socket at: $SSH_AGENT_SOCK"
	echo "Ensure ssh-agent is running and ssh-add has loaded your key:"
	echo "  ssh-add ~/.ssh/id_ed25519"
	exit 1
fi

echo "Found SSH agent socket at: $SSH_AGENT_SOCK"

# Kill any existing relay on port 6010
pkill -f "socat.*TCP-LISTEN:6010" || true

# Start socat relay on port 6010
echo "Starting SSH agent relay on port 6010..."
socat TCP-LISTEN:6010,reuseaddr,fork UNIX-CONNECT:"$SSH_AGENT_SOCK" &
RELAY_PID=$!

echo "SSH Agent relay started (PID: $RELAY_PID) on port 6010"
echo ""
echo "Container can now access your ssh-agent via:"
echo "  SSH_AUTH_SOCK=/tmp/ssh-agent-relay"
echo ""
echo "You can now start the container:"
echo "  MODEL=haiku ./claude-sandbox.sh"
