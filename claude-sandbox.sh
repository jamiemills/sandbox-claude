#!/bin/bash

#
# Run the specialist Docker Sandbox command to wrap Claude. See https://docs.docker.com/ai/sandboxes/
#
# This will 
# - use Google Application Default Credentials / Google Vertex to access the models (depends on /Users/jamie.mills/c9h/code/sandbox-claude/.config/gcloud/application_default_credentials.json being available)
# - use Haiku as the model
# - Run claude with --continue, or if that fails, just run it as a new session
# 

ADC_SOURCE=$HOME/.config/gcloud/application_default_credentials.json
ADC_IN_CONTAINER=$HOME/c9h/code/.application_default_credentials.json
SSH_SOURCE=$HOME/.ssh
SSH_IN_CONTAINER=/root/.ssh

docker sandbox run \
-e CLAUDE_CODE_USE_VERTEX=${CLAUDE_CODE_USE_VERTEX} \
-e CLOUD_ML_REGION=${CLOUD_ML_REGION} \
-e ANTHROPIC_VERTEX_PROJECT_ID=${ANTHROPIC_VERTEX_PROJECT_ID} \
-e GOOGLE_APPLICATION_CREDENTIALS=${ADC_IN_CONTAINER}  \
-v ${ADC_SOURCE}:${ADC_IN_CONTAINER}:ro \
-v ${SSH_SOURCE}:${SSH_IN_CONTAINER}:ro \
claude --model ${MODEL}

exit


docker sandbox run \
-e CLAUDE_CODE_USE_VERTEX=1 \
-e CLOUD_ML_REGION=global \
-e ANTHROPIC_VERTEX_PROJECT_ID=prj-mediaopt-vertex-npd \
-e GOOGLE_APPLICATION_CREDENTIALS=/Users/jamie.mills/c9h/code/sandbox-claude/.config/gcloud/application_default_credentials.json  \
claude --model claude-haiku-4-5@20251001 --continue || \
docker sandbox run \
-e CLAUDE_CODE_USE_VERTEX=1 \
-e CLOUD_ML_REGION=global \
-e ANTHROPIC_VERTEX_PROJECT_ID=prj-mediaopt-vertex-npd \
-e GOOGLE_APPLICATION_CREDENTIALS=/Users/jamie.mills/c9h/code/sandbox-claude/.config/gcloud/application_default_credentials.json  \
claude --model claude-haiku-4-5@20251001 



