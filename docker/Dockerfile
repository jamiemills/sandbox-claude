# syntax=docker/dockerfile:1

FROM debian:bookworm-slim

# Set environment variables
ENV HOME=/home/agent \
    SHELL=/bin/bash \
    PATH=/home/agent/.local/bin:$PATH

# Install system dependencies, Node.js 20.x, GitHub CLI, vim, tmux, and socat
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
    socat \
    gh && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | sh - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install uv globally using the standalone installer
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Create non-root user and set up workspace directories
RUN useradd -m -s /bin/bash agent && \
    mkdir -p /home/agent/workspace /home/agent/workspace/.config /home/agent/.claude /home/agent/.config/gh && \
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

# Create SSH config for git operations (keys will be mounted from host at runtime)
# This config is used when SSH keys are mounted and provides proper GitHub settings
RUN mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
    echo "Host github.com" > ~/.ssh/config && \
    echo "  HostName github.com" >> ~/.ssh/config && \
    echo "  User git" >> ~/.ssh/config && \
    echo "  StrictHostKeyChecking accept-new" >> ~/.ssh/config && \
    chmod 600 ~/.ssh/config

# Create entrypoint script
# Note: SSH keys are mounted read-only, so we don't need (and can't) chmod them
RUN printf '#!/bin/bash\n\n# Set up SSH agent relay if host provides the relay port\nif [ -n "$SSH_AGENT_RELAY_PORT" ]; then\n    echo "Setting up SSH agent relay to host ssh-agent..."\n\n    # Create directory for relay socket\n    mkdir -p /tmp/ssh-agent-relay-dir\n\n    # Start socat client that:\n    # - Listens on Unix socket at /tmp/ssh-agent-relay-dir/ssh-agent\n    # - Forwards connections to host'"'"'s TCP relay on port 6010\n    socat UNIX-LISTEN:/tmp/ssh-agent-relay-dir/ssh-agent,fork \\\n          TCP:host.docker.internal:${SSH_AGENT_RELAY_PORT} &\n    RELAY_PID=$!\n\n    # Point SSH_AUTH_SOCK to the relay socket\n    export SSH_AUTH_SOCK=/tmp/ssh-agent-relay-dir/ssh-agent\n\n    echo "SSH agent relay configured (PID: $RELAY_PID)"\n    echo "SSH_AUTH_SOCK=$SSH_AUTH_SOCK"\nfi\n\n# Continue with normal Claude Code startup\nexec claude "$@"\n' > ~/.entrypoint.sh && chmod +x ~/.entrypoint.sh

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

# Set default command
CMD ["claude"]

# Metadata
LABEL description="Claude Code sandbox with GitHub CLI, Claude, and uv" \
      version="2.4" \
      maintainer="Claude Sandbox"
