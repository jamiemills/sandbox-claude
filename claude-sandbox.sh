#!/bin/bash
# Version: 1.0

#
# Run Claude Code in a containerised sandbox environment. Supports Docker and Podman.
# Inspired by docker sandbox; See https://docs.docker.com/ai/sandboxes/ for more information.
#
# Required environment variables:
#   MODEL - The Claude model to use (e.g., haiku, opus). Example: MODEL=haiku ./claude-sandbox.sh
#
# Optional environment variables:
#   CONTAINER_RUNTIME - Container runtime to use (default: docker). Example: CONTAINER_RUNTIME=podman ./claude-sandbox.sh
#
# Google Vertex AI support (optional):
#   CLAUDE_CODE_USE_VERTEX - Enable Vertex AI
#   CLOUD_ML_REGION - Google Cloud region
#   ANTHROPIC_VERTEX_PROJECT_ID - GCP project ID
#

# Cleanup function for temporary files
# shellcheck disable=SC2329
cleanup() {
	# Remove temporary SSH config if it exists (legacy cleanup)
	[ -f ~/.ssh/config.container ] && rm -f ~/.ssh/config.container
}

trap cleanup EXIT

# Validate MODEL environment variable is set
if [ -z "${MODEL}" ]; then
	echo "Error: MODEL environment variable not set. Usage: MODEL=haiku ./claude-sandbox.sh"
	exit 1
fi

# Validate KEYFILE environment variable is set
if [ -z "${KEYFILE}" ]; then
	echo "Error: KEYFILE environment variable not set. Usage: KEYFILE=~/.ssh/id_ed25519 MODEL=haiku ./claude-sandbox.sh"
	exit 1
fi

# Set container runtime (default: docker, can be overridden with CONTAINER_RUNTIME env var)
CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-docker}

# Validate specified runtime is available
if ! command -v "${CONTAINER_RUNTIME}" &>/dev/null; then
	echo "Error: ${CONTAINER_RUNTIME} not found. Please install it."
	exit 1
fi

# Determine mount strategy based on whether we're in a git repo
CURRENT_DIR=$(pwd)
DIR_HASH=$(echo -n "${CURRENT_DIR}" | sha256sum | cut -c1-8)

if git rev-parse --git-dir >/dev/null 2>&1; then
	# In a repo: mount repo root at /home/agent/<repo-name>
	REPO_ROOT=$(git rev-parse --show-toplevel)
	REPO_NAME=$(basename "${REPO_ROOT}")
	RELATIVE_PATH=$(python3 -c "import os.path; print(os.path.relpath('${CURRENT_DIR}', '${REPO_ROOT}'))")
	CONTAINER_WORKDIR="/home/agent/${REPO_NAME}/${RELATIVE_PATH}"
	# Mount repo root with repo name
	WORKSPACE_MOUNT="-v ${REPO_ROOT}:/home/agent/${REPO_NAME}"
	# Container name based on repo name + directory hash (for directory isolation)
	CONTAINER_NAME="claude-${REPO_NAME}-${DIR_HASH}"
else
	# Not in a repo: mount current directory as workspace
	CONTAINER_WORKDIR="/home/agent/workspace"
	WORKSPACE_MOUNT="-v ${CURRENT_DIR}:/home/agent/workspace"
	# Container name based on current directory hash
	CONTAINER_NAME="claude-workspace-${DIR_HASH}"
fi

# Create tmux session name (includes runtime)
TMUX_SESSION="${CONTAINER_RUNTIME}-${CONTAINER_NAME}"

# Mount points (credentials mounted under workspace)
ADC_SOURCE=$HOME/.config/gcloud/application_default_credentials.json
ADC_IN_CONTAINER=/home/agent/workspace/.config/gcloud/application_default_credentials.json

# SSH key forwarding for git operations
# Mount SSH keys specified by KEYFILE environment variable
# Container generates its own GitHub-only SSH config at startup
SSH_AUTH_MOUNT=""
# Mount private key if it exists (destination path must be absolute)
[ -f "${KEYFILE}" ] && SSH_AUTH_MOUNT="$SSH_AUTH_MOUNT -v ${KEYFILE}:/home/agent/.ssh/$(basename "${KEYFILE}"):ro"
# Mount public key if it exists
[ -f "${KEYFILE}.pub" ] && SSH_AUTH_MOUNT="$SSH_AUTH_MOUNT -v ${KEYFILE}.pub:/home/agent/.ssh/$(basename "${KEYFILE}").pub:ro"

# Claude state directory mount (includes memory file and todos) - read-write
CLAUDE_STATE_SOURCE=$HOME/.claude
CLAUDE_STATE_CONTAINER=/home/agent/.claude

# GitHub CLI configuration mount (allows gh config persistence)
GH_CONFIG_SOURCE=$HOME/.config/gh
GH_CONFIG_CONTAINER=/home/agent/.config/gh

# GitHub token mapping mount (for KEYFILE-based authentication)
GHTOKEN_SOURCE=$REPO_ROOT/.sandbox.ghtoken
GHTOKEN_CONTAINER=/home/agent/.ghtoken

# Check if tmux session already exists
if tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
	# Session exists, attach to it
	echo "Attaching to existing tmux session: ${TMUX_SESSION}"
	if ! tmux attach -t "${TMUX_SESSION}"; then
		echo "Error: Failed to attach to tmux session ${TMUX_SESSION}"
		exit 1
	fi
else
	# Check if container already exists (for resume)
	CONTAINER_EXISTS=false
	if ${CONTAINER_RUNTIME} ps -a --filter "name=^${CONTAINER_NAME}$" --format "{{.Names}}" | grep -q "${CONTAINER_NAME}"; then
		CONTAINER_EXISTS=true
	fi

	# Create container command based on whether it exists
	if [ "$CONTAINER_EXISTS" = true ]; then
		# Container exists, create command to restart and attach
		CONTAINER_CMD="${CONTAINER_RUNTIME} start -ai ${CONTAINER_NAME}"
	else
		# Container doesn't exist, create and run it
		# shellcheck disable=SC2089,SC2090,SC2124
		CONTAINER_CMD="${CONTAINER_RUNTIME} run -it \
    --name ${CONTAINER_NAME} \
    -e CLAUDE_CODE_USE_VERTEX=${CLAUDE_CODE_USE_VERTEX} \
    -e CLOUD_ML_REGION=${CLOUD_ML_REGION} \
    -e ANTHROPIC_VERTEX_PROJECT_ID=${ANTHROPIC_VERTEX_PROJECT_ID} \
    -e GOOGLE_APPLICATION_CREDENTIALS=${ADC_IN_CONTAINER} \
    -e EDITOR=vim \
    -e SSH_AGENT_RELAY_PORT=6010 \
    -e SSH_AUTH_SOCK=/tmp/ssh-agent-relay-dir/ssh-agent \
    ${WORKSPACE_MOUNT} \
    -v ${ADC_SOURCE}:${ADC_IN_CONTAINER}:ro \
    --tmpfs /tmp:rw,noexec,nosuid,size=1g \
    -v ${CLAUDE_STATE_SOURCE}:${CLAUDE_STATE_CONTAINER} \
    -v ${GH_CONFIG_SOURCE}:${GH_CONFIG_CONTAINER} \
    $([ -f "${GHTOKEN_SOURCE}" ] && echo "-v ${GHTOKEN_SOURCE}:${GHTOKEN_CONTAINER}:ro") \
    ${SSH_AUTH_MOUNT} \
    -w ${CONTAINER_WORKDIR} \
    --group-add=root \
    --entrypoint /home/agent/.entrypoint.sh \
    claude_sandbox \
    --model ${MODEL} --dangerously-skip-permissions ${@}"
	fi

	# Create tmux session and run container command
	echo "Creating tmux session: ${TMUX_SESSION}"
	echo "Container runtime: ${CONTAINER_RUNTIME}"
	echo "Container name: ${CONTAINER_NAME}"
	echo ""
	echo "To reconnect to this session later, run:"
	echo "  tmux attach -t ${TMUX_SESSION}"
	echo ""

	tmux new-session -d -s "${TMUX_SESSION}" "${CONTAINER_CMD}"
	sleep 1

	# Validate container is running before attempting to attach
	if ! ${CONTAINER_RUNTIME} inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
		echo "Error: Container ${CONTAINER_NAME} failed to start"
		echo "Check container logs for details: ${CONTAINER_RUNTIME} logs ${CONTAINER_NAME}"
		exit 1
	fi

	# Attach to the tmux session
	if ! tmux attach -t "${TMUX_SESSION}"; then
		echo "Error: Failed to attach to tmux session ${TMUX_SESSION}"
		exit 1
	fi
fi

exit 0
