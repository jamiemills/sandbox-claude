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

# SSH Agent forwarding for git operations
SSH_AUTH_SOCK=${SSH_AUTH_SOCK:-}
SSH_AUTH_MOUNT=""
if [ -n "$SSH_AUTH_SOCK" ]; then
	SSH_AUTH_MOUNT="-v $SSH_AUTH_SOCK:$SSH_AUTH_SOCK -e SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
fi

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
	CLAUDE_DOCKER_CMD="${CONTAINER_RUNTIME} run -it \
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
    claude_sandbox \
    claude"

	# ${CLAUDE_DOCKER_CMD} --model "${MODEL}" --dangerously-skip-permissions --continue "${@}" || \
	${CLAUDE_DOCKER_CMD} --model "${MODEL}" --dangerously-skip-permissions --continue "${@}" ||
		${CONTAINER_RUNTIME} start -ai "${CONTAINER_NAME}"
fi

exit 0
