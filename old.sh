docker sandbox run \
-e CLAUDE_CODE_USE_VERTEX=1 \
-e CLOUD_ML_REGION=global \
-e ANTHROPIC_VERTEX_PROJECT_ID=prj-mediaopt-vertex-npd \
-e GOOGLE_APPLICATION_CREDENTIALS=/root/.config/gcloud/application_default_credentials.json \
-v /tmp/adc.json:/root/.config/gcloud/application_default_credentials.json:ro \
claude
