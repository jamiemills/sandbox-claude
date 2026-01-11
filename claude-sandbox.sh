#!/bin/bash

#
# Run the specialist Docker Sandbox command to wrap Claude. See https://docs.docker.com/ai/sandboxes/
#
# This will 
# - use Google Application Default Credentials / Google Vertex to access the models (depends on /Users/jamie.mills/c9h/code/sandbox-claude/.config/gcloud/application_default_credentials.json being available)
# - use Haiku as the model
# - Run claude with --continue, or if that fails, just run it as a new session
# 

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
