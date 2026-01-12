#!/bin/bash

podman build --no-cache -t claude_sandbox:latest docker/
docker build --no-cache -t claude_sandbox:latest docker/
