#!/bin/bash

#
# Run the specialist Docker Sandbox command to wrap Claude. See https://docs.docker.com/ai/sandboxes/
#
# This will
# - use Google Application Default Credentials / Google Vertex to access the models (depends on /Users/jamie.mills/c9h/code/sandbox-claude/.config/gcloud/application_default_credentials.json being available)
# - use Haiku as the model
# - Run claude with --continue, or if that fails, just run it as a new session
#

# Source environment file if it exists (for GH_TOKEN and other secrets)
if [ -f ~/.claude/.env ]; then
    source ~/.claude/.env
fi

# Determine mount strategy based on whether we're in a git repo
if git rev-parse --git-dir > /dev/null 2>&1; then
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

# Check if container already exists
if docker ps -a --filter "name=^${CONTAINER_NAME}$" --format "{{.Names}}" | grep -q "${CONTAINER_NAME}"; then
    # Container exists, restart it and attach
    docker start -ai "${CONTAINER_NAME}"
else
    # Container doesn't exist, create and run it
    CLAUDE_DOCKER_CMD="docker run -it \
    --name "${CONTAINER_NAME}" \
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
    ${SSH_AUTH_MOUNT} \
    -w ${CONTAINER_WORKDIR} \
    --group-add=root \
    claude_sandbox \
    claude"

    # ${CLAUDE_DOCKER_CMD} --model ${MODEL} --dangerously-skip-permissions --continue ${@} || \
    ${CLAUDE_DOCKER_CMD} --model ${MODEL} --dangerously-skip-permissions ${@} || \
    ${CLAUDE_DOCKER_CMD} --model ${MODEL} --dangerously-skip-permissions ${@} 
fi

exit 0

