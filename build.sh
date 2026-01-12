#!/bin/bash

# Stop any running containers from the previous build. Required before removal and rebuild
# because running containers lock the image and prevent cleanup or rebuilding.
podman stop "$(podman ps -a --filter "ancestor=claude_sandbox" --format "{{.ID}}")"
docker stop "$(docker ps -a --filter "ancestor=claude_sandbox" --format "{{.ID}}")"

# Remove stopped containers to clear old container artifacts. This ensures a clean rebuild
# without orphaned containers from previous builds that may consume disk space.
podman rm "$(podman ps -a --filter "ancestor=claude_sandbox" --format "{{.ID}}")"
docker rm "$(docker ps -a --filter "ancestor=claude_sandbox" --format "{{.ID}}")"

# Rebuild both container runtimes with --no-cache to ensure all layers are rebuilt fresh.
# This guarantees any Dockerfile changes, dependency updates, or package changes are picked up
# rather than using stale cached layers from previous builds.
podman build --no-cache -t claude_sandbox:latest docker/
docker build --no-cache -t claude_sandbox:latest docker/
