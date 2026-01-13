#!/bin/bash
# SSH Agent Relay - Bridges host's ssh-agent to containers via TCP

#
# >> Relay runs in background detached session
# tmux new-session -d -s ssh-agent-relay './start-ssh-agent-relay.sh'
#
# >> Reconnect anytime:
# tmux attach -t ssh-agent-relay
#

set -e

# Validate KEYFILE environment variable is set
if [ -z "${KEYFILE}" ]; then
	echo "Error: KEYFILE environment variable not set. Usage: KEYFILE=~/.ssh/id_ed25519 $0"
	exit 1
fi

# cache the passphrase
ssh-add "${KEYFILE}"

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

# Start socat relay on port 6010 in detached tmux session
echo "Starting SSH agent relay on port 6010..."
tmux new-session -d -s ssh-relay "socat TCP-LISTEN:6010,reuseaddr,fork UNIX-CONNECT:\"$SSH_AGENT_SOCK\""

echo "Relay running in tmux session 'ssh-relay'"
echo "Reconnect with: tmux attach -t ssh-relay"

exit 0
