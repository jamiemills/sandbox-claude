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

# Source environment file if it exists (for GH_TOKEN and other secrets)
if [ -f ~/.claude/.env ]; then
	# shellcheck source=/dev/null
	source ~/.claude/.env
fi

# Validate MODEL environment variable is set
if [ -z "${MODEL}" ]; then
	echo "Error: MODEL environment variable not set. Usage: MODEL=haiku ./claude-sandbox.sh"
	exit 1
fi

# Set container runtime (default: docker, can be overridden with CONTAINER_RUNTIME env var)
CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-docker}

# Validate specified runtime is available
if ! command -v "${CONTAINER_RUNTIME}" &>/dev/null; then
	echo "Error: ${CONTAINER_RUNTIME} not found. Please install it."
	exit 1
fi

# SSH Key Setup for Podman
# For SSH keys with passphrases: Remove the passphrase before using in containers.
# SSH agent socket forwarding doesn't work reliably across Podman's VM boundary on macOS.
# Use passphrase-free keys for container SSH operations. The key file permissions
# are protected by the container's read-only mount and non-root user execution.
#
# To remove passphrase from an SSH key:
#   ssh-keygen -p -f ~/.ssh/id_ed25519 -N "" -P "<current_passphrase>"
#
# See .claude/CLAUDE.md for full SSH setup documentation.

# Determine mount strategy based on whether we're in a git repo
if git rev-parse --git-dir >/dev/null 2>&1; then
	# In a repo: mount repo root at /home/agent/<repo-name>
	REPO_ROOT=$(git rev-parse --show-toplevel)
	REPO_NAME=$(basename "${REPO_ROOT}")
	CURRENT_DIR=$(pwd)
	RELATIVE_PATH=$(python3 -c "import os.path; print(os.path.relpath('${CURRENT_DIR}', '${REPO_ROOT}'))")
	CONTAINER_WORKDIR="/home/agent/${REPO_NAME}/${RELATIVE_PATH}"
	# Mount repo root with repo name
	WORKSPACE_MOUNT="-v ${REPO_ROOT}:/home/agent/${REPO_NAME}"
	# Container name based on repo
	CONTAINER_NAME="claude-${REPO_NAME}"
else
	# Not in a repo: mount current directory as workspace
	CURRENT_DIR=$(pwd)
	CONTAINER_WORKDIR="/home/agent/workspace"
	WORKSPACE_MOUNT="-v ${CURRENT_DIR}:/home/agent/workspace"
	# Container name based on current directory hash
	DIR_HASH=$(echo -n "${CURRENT_DIR}" | sha256sum | cut -c1-8)
	CONTAINER_NAME="claude-workspace-${DIR_HASH}"
fi

# Mount points (credentials mounted under workspace)
ADC_SOURCE=$HOME/.config/gcloud/application_default_credentials.json
ADC_IN_CONTAINER=/home/agent/workspace/.config/gcloud/application_default_credentials.json

# SSH key forwarding for git operations
# Mount SSH keys directly (but not config) to avoid platform-specific issues
# Keys are regular files that work across VM boundaries and socket forwarding issues
# Only mount key files to prevent host SSH config (which may contain platform-specific options
# like "usekeychain" for macOS) from interfering with container SSH
SSH_AUTH_MOUNT=""
# Mount private keys if they exist
[ -f "$HOME/.ssh/id_rsa" ] && SSH_AUTH_MOUNT="$SSH_AUTH_MOUNT -v $HOME/.ssh/id_rsa:/home/agent/.ssh/id_rsa:ro"
[ -f "$HOME/.ssh/id_ed25519" ] && SSH_AUTH_MOUNT="$SSH_AUTH_MOUNT -v $HOME/.ssh/id_ed25519:/home/agent/.ssh/id_ed25519:ro"
[ -f "$HOME/.ssh/id_ecdsa" ] && SSH_AUTH_MOUNT="$SSH_AUTH_MOUNT -v $HOME/.ssh/id_ecdsa:/home/agent/.ssh/id_ecdsa:ro"
# Mount public keys if they exist
[ -f "$HOME/.ssh/id_rsa.pub" ] && SSH_AUTH_MOUNT="$SSH_AUTH_MOUNT -v $HOME/.ssh/id_rsa.pub:/home/agent/.ssh/id_rsa.pub:ro"
[ -f "$HOME/.ssh/id_ed25519.pub" ] && SSH_AUTH_MOUNT="$SSH_AUTH_MOUNT -v $HOME/.ssh/id_ed25519.pub:/home/agent/.ssh/id_ed25519.pub:ro"
[ -f "$HOME/.ssh/id_ecdsa.pub" ] && SSH_AUTH_MOUNT="$SSH_AUTH_MOUNT -v $HOME/.ssh/id_ecdsa.pub:/home/agent/.ssh/id_ecdsa.pub:ro"

# Claude state directory mount (includes memory file and todos) - read-write
CLAUDE_STATE_SOURCE=$HOME/.claude
CLAUDE_STATE_CONTAINER=/home/agent/.claude

# GitHub CLI configuration mount (allows gh config persistence)
GH_CONFIG_SOURCE=$HOME/.config/gh
GH_CONFIG_CONTAINER=/home/agent/.config/gh

# Git configuration mount (allows git config persistence)
GITCONFIG_SOURCE=$HOME/.gitconfig
GITCONFIG_CONTAINER=/home/agent/.gitconfig

# Check if container already exists
if ${CONTAINER_RUNTIME} ps -a --filter "name=^${CONTAINER_NAME}$" --format "{{.Names}}" | grep -q "${CONTAINER_NAME}"; then
	# Container exists, restart it and attach
	${CONTAINER_RUNTIME} start -ai "${CONTAINER_NAME}"
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
    -e GH_TOKEN=${GH_TOKEN:-} \
    ${WORKSPACE_MOUNT} \
    -v ${ADC_SOURCE}:${ADC_IN_CONTAINER}:ro \
    -v /tmp:/tmp \
    -v ${CLAUDE_STATE_SOURCE}:${CLAUDE_STATE_CONTAINER} \
    -v ${GH_CONFIG_SOURCE}:${GH_CONFIG_CONTAINER} \
    -v ${GITCONFIG_SOURCE}:${GITCONFIG_CONTAINER}:ro \
    ${SSH_AUTH_MOUNT} \
    -w ${CONTAINER_WORKDIR} \
    --group-add=root \
    --entrypoint /home/agent/.entrypoint.sh \
    claude_sandbox"

	${CONTAINER_CMD} --model "${MODEL}" --dangerously-skip-permissions --continue "${@}" ||
		${CONTAINER_RUNTIME} start -ai "${CONTAINER_NAME}"
fi

exit 0
