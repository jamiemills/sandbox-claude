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

# Copy git configuration from repo (before switching to non-root user)
COPY .sandbox.gitconfig /home/agent/.gitconfig
RUN chown agent:agent /home/agent/.gitconfig && chmod 600 /home/agent/.gitconfig

# Switch to non-root user
USER agent

# Configure bash environment with pip alias and SSH agent relay support
RUN echo 'alias pip="uv pip"' >> ~/.bashrc && \
    echo '# Set SSH_AUTH_SOCK for relay support if running in relay mode' >> ~/.bashrc && \
    echo 'if [ -S /tmp/ssh-agent-relay-dir/ssh-agent ]; then' >> ~/.bashrc && \
    echo '  export SSH_AUTH_SOCK=/tmp/ssh-agent-relay-dir/ssh-agent' >> ~/.bashrc && \
    echo 'fi' >> ~/.bashrc && \
    echo '' >> ~/.bashrc && \
    echo '# Track working directory changes for Claude Code session persistence' >> ~/.bashrc && \
    echo '# This allows cd commands to persist within a Claude Code session' >> ~/.bashrc && \
    echo 'export CLAUDE_CWD="$PWD"' >> ~/.bashrc && \
    echo 'cd() { builtin cd "$@" && export CLAUDE_CWD="$PWD" && echo "$PWD" > ~/.claude_session_cwd; }' >> ~/.bashrc && \
    echo '# Restore previous directory if in a Claude Code command' >> ~/.bashrc && \
    echo 'if [ -f ~/.claude_session_cwd ]; then' >> ~/.bashrc && \
    echo '  _CWD_TO_RESTORE=$(cat ~/.claude_session_cwd)' >> ~/.bashrc && \
    echo '  if [ -d "$_CWD_TO_RESTORE" ]; then' >> ~/.bashrc && \
    echo '    builtin cd "$_CWD_TO_RESTORE"' >> ~/.bashrc && \
    echo '  fi' >> ~/.bashrc && \
    echo 'fi' >> ~/.bashrc

# Create SSH directory (config will be generated dynamically by entrypoint)
RUN mkdir -p ~/.ssh && chmod 700 ~/.ssh

# Create entrypoint script that generates SSH config dynamically and manages relay
RUN printf '#!/bin/bash\n\n# Generate SSH config based on mounted keys\nif [ ! -f ~/.ssh/config ]; then\n    {\n        echo "# GitHub SSH configuration (dynamically generated)"\n        echo "Host github.com"\n        echo "  HostName github.com"\n        echo "  User git"\n        echo "  StrictHostKeyChecking accept-new"\n        \n        # Add IdentityFile entries for all mounted keys\n        for key in ~/.ssh/id_*; do\n            if [ -f "$key" ] && [ "${key##*.}" != "pub" ]; then\n                echo "  IdentityFile $key"\n            fi\n        done\n        \n        echo "  IdentitiesOnly yes"\n    } > ~/.ssh/config\n    chmod 600 ~/.ssh/config\nfi\n\n# Dynamically set GH_TOKEN from .sandbox.ghtoken mapping based on mounted KEYFILE\nKEYFILE_NAME=$(basename /home/agent/.ssh/id_* 2>/dev/null | head -1)\nif [ -f ~/.ghtoken ]; then\n    GH_TOKEN_VALUE=$(grep "^${KEYFILE_NAME}|" ~/.ghtoken 2>/dev/null | cut -d'"'"'|'"'"' -f2 | head -1)\n    if [ -n "$GH_TOKEN_VALUE" ]; then\n        export GH_TOKEN="$GH_TOKEN_VALUE"\n    else\n        unset GH_TOKEN\n    fi\nelse\n    unset GH_TOKEN\nfi\n\n# Set up SSH agent relay if host provides the relay port\nif [ -n "$SSH_AGENT_RELAY_PORT" ]; then\n    echo "Setting up SSH agent relay to host ssh-agent..."\n\n    # Create directory for relay socket\n    mkdir -p /tmp/ssh-agent-relay-dir\n\n    # Start socat client that:\n    # - Listens on Unix socket at /tmp/ssh-agent-relay-dir/ssh-agent\n    # - Forwards connections to host'"'"'s TCP relay on port 6010\n    socat UNIX-LISTEN:/tmp/ssh-agent-relay-dir/ssh-agent,fork \\\n          TCP:host.docker.internal:${SSH_AGENT_RELAY_PORT} &\n    RELAY_PID=$!\n\n    echo "SSH agent relay configured (PID: $RELAY_PID)"\n    echo "SSH_AUTH_SOCK=/tmp/ssh-agent-relay-dir/ssh-agent"\n    \n    # Pass SSH_AUTH_SOCK through environment to Claude Code subprocess\n    exec env SSH_AUTH_SOCK=/tmp/ssh-agent-relay-dir/ssh-agent /bin/bash -c '"'"'exec claude "$@"'"'"' _ "$@"\nelse\n    # No relay, continue normally\n    exec claude "$@"\nfi\n' > ~/.entrypoint.sh && chmod +x ~/.entrypoint.sh

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
