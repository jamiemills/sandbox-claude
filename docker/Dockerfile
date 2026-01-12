# syntax=docker/dockerfile:1

FROM debian:bookworm-slim

# Set environment variables
ENV HOME=/home/agent \
    SHELL=/bin/bash \
    PATH=/home/agent/.local/bin:$PATH

# Install system dependencies, Node.js 20.x, GitHub CLI, vim, and tmux
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    git \
    openssh-client \
    python3 \
    ca-certificates \
    gnupg \
    lsb-release \
    wget \
    unzip \
    vim \
    tmux \
    gh && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | sh - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install uv globally using the standalone installer
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Create non-root user and set up workspace with config and SSH directories
RUN useradd -m -s /bin/bash agent && \
    mkdir -p /home/agent/workspace /home/agent/workspace/.config /home/agent/workspace/.ssh /home/agent/.claude /home/agent/.config/gh && \
    chmod 700 /home/agent/workspace/.ssh && \
    chmod 755 /home/agent/workspace/.config && \
    chmod 755 /home/agent/.claude && \
    chmod 755 /home/agent/.config/gh && \
    chown -R agent:agent /home/agent

# Install Claude Code globally via npm and clean cache
RUN npm install -g @anthropic-ai/claude-code && \
    npm cache clean --force

# Switch to non-root user
USER agent

# Configure bash environment with pip alias
RUN echo 'alias pip="uv pip"' >> ~/.bashrc

# Configure SSH to use agent and auto-accept GitHub host key
RUN mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
    echo "Host github.com" >> ~/.ssh/config && \
    echo "  HostName github.com" >> ~/.ssh/config && \
    echo "  User git" >> ~/.ssh/config && \
    echo "  StrictHostKeyChecking accept-new" >> ~/.ssh/config && \
    echo "  AddKeysToAgent yes" >> ~/.ssh/config && \
    chmod 600 ~/.ssh/config

# Set working directory
WORKDIR /home/agent/workspace

# Verify critical tools installed successfully as agent user
RUN claude --version && \
    node --version && \
    git --version && \
    uv --version && \
    gh --version

# Add health check to validate container startup
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD claude --version > /dev/null 2>&1

# Define workspace volume mount point for persistent project storage
VOLUME ["/home/agent/workspace"]

# Git configuration: Mount your host ~/.gitconfig to /home/agent/.gitconfig for commits
# Example: docker run -v ~/.gitconfig:/home/agent/.gitconfig:ro ...

# Set default command
CMD ["claude"]

# Metadata
LABEL description="Claude Code sandbox with SSH, GitHub CLI, Claude, and uv" \
      version="2.3" \
      maintainer="Claude Sandbox"
