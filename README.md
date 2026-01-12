# Claude Sandbox

A Docker-based sandbox environment that containerises Claude Code with a pre-configured development toolchain. This project provides isolated, reproducible execution of Claude Code with integrated Google Vertex AI support for model access.

## Overview

Claude Sandbox encapsulates Claude Code and its dependencies in a Docker container, eliminating environment setup complexity. It runs as a non-root user with secure credential management, persistent session support, and seamless git integration.

**Key features:**

- **Containerised environment** — Consistent toolchain across all executions
- **Session persistence** — Named containers resume where you left off
- **Credential isolation** — Read-only mounting of sensitive credentials (Google Cloud, SSH keys)
- **Smart mount strategy** — Automatically detects git repositories and mounts intelligently
- **SSH agent forwarding** — Secure git operations without passing private keys
- **State preservation** — Claude memory and todo lists persist across sessions
- **Non-root execution** — Runs as unprivileged user for enhanced security
- **Health checks** — Built-in container health verification

## Quick Start

### Prerequisites

- Docker (with Daemon running)
- Bash shell
- Google Application Default Credentials (optional, for Vertex AI)
- SSH keys configured for GitHub (optional, for git operations)

### Build the Image

```bash
docker build -f docker/Dockerfile -t claude_sandbox .
```

### Run Claude Code

```bash
./claude-sandbox.sh
```

The script automatically:
- Detects whether you're in a git repository
- Mounts your project at an appropriate location
- Forwards SSH credentials for git operations
- Passes Google Cloud credentials for Vertex AI access
- Resumes previous sessions or starts a new one
- Sets the editor to vim

## How It Works

### Mount Strategy

The script intelligently determines how to mount your workspace:

**In a git repository:**
- Mounts the repository root at `/home/agent/<repo-name>`
- Preserves relative paths within the container
- Container is named `claude-<repo-name>` for easy identification

**Outside a git repository:**
- Mounts the current directory at `/home/agent/workspace`
- Container is named `claude-workspace-<hash>` based on directory path

### Credential Handling

Three types of credentials are mounted:

| Credential | Host Location | Container Path | Purpose | Read-Only |
|---|---|---|---|---|
| Google Cloud ADC | `~/.config/gcloud/application_default_credentials.json` | `/home/agent/workspace/.config/gcloud/...` | Vertex AI access | ✓ |
| SSH keys | Via `SSH_AUTH_SOCK` | Socket forwarded | Git operations | ✓ |
| Claude state | `~/.claude` | `/home/agent/.claude` | Memory and todos | ✗ |

### Session Persistence

The script checks if a named container for your workspace already exists:
- If it exists, the container is restarted and you reconnect to the running session
- If it doesn't exist, a new container is created and Claude Code starts fresh
- All state (memory, todos, etc.) is preserved across sessions

## Configuration

### Environment Variables

Set these before running `./claude-sandbox.sh` to use Google Vertex AI:

```bash
export CLAUDE_CODE_USE_VERTEX=1                    # Enable Vertex AI
export CLOUD_ML_REGION=us-central1                 # Cloud region
export ANTHROPIC_VERTEX_PROJECT_ID=my-project-id  # GCP project
```

### Git Configuration

To include your git identity in commits:

```bash
docker run -v ~/.gitconfig:/home/agent/.gitconfig:ro ...
```

Or configure inside the container:

```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

## Installed Tools

The Docker image includes:

- **Claude Code CLI** — Anthropic's Claude Code tool
- **Node.js 20.x** — JavaScript runtime
- **Python 3** — Python runtime with uv
- **Git** — Version control with GitHub CLI
- **GitHub CLI** (`gh`) — GitHub command-line interface
- **SSH client** — Secure shell access (pre-configured for GitHub)
- **Vim** — Text editor (default)
- **curl & wget** — HTTP clients
- **tmux** — Terminal multiplexing (pre-installed)

The container aliases `pip` to `uv pip` for Python package management.

### GitHub CLI (gh) Configuration

The container includes GitHub CLI (`gh`) with pre-configured SSH authentication. Your host's gh configuration is automatically mounted into the container for persistence.

#### Setup

Create a `.env` file with your GitHub token (one-time setup):

```bash
cat > ~/.claude/.env << 'EOF'
# GitHub token for gh CLI API access
export GH_TOKEN=$(gh auth token)
EOF
chmod 600 ~/.claude/.env
```

The script automatically sources `~/.claude/.env` before starting the container, passing the token securely without exposing it in process listings.

#### How It Works

- Your `~/.config/gh` directory is mounted read-write into the container
- SSH authentication is forwarded from your host's SSH agent for git operations
- GitHub token is passed via environment variable for API access
- Configuration persists across container restarts

#### Using gh in the Container

```bash
# Inside container
gh repo list
gh pr create --title "My PR"
gh issue list
gh repo clone owner/repo
```

All gh commands work seamlessly using your host's authentication and configuration.

#### Troubleshooting

If gh commands fail:

```bash
# Check gh auth status in container
gh auth status

# Check SSH authentication
ssh -T git@github.com
```

Both should work without prompts.

## Directory Structure

```
sandbox-claude/
├── README.md                    # This file
├── CLAUDE.md                    # Project instructions for Claude AI
├── claude-sandbox.sh            # Entry point script (executable)
├── docker/
│   └── Dockerfile              # Container image definition
├── .claude/
│   └── settings.local.json     # Claude Code permission allowlist
├── .git/                        # Git repository
└── .gitignore                  # Git ignore rules
```

## Troubleshooting

### Docker daemon not running

```bash
# Start Docker (macOS with Docker Desktop)
open /Applications/Docker.app

# Or, verify it's running
docker ps
```

### Credentials not found

```bash
# Verify Google Cloud credentials exist
ls -la ~/.config/gcloud/application_default_credentials.json

# Verify SSH keys exist
ls -la ~/.ssh
```

### SSH authentication fails inside container

Ensure SSH agent is running on the host:

```bash
# Check if agent is running
echo $SSH_AUTH_SOCK

# If empty, start the agent
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_ed25519  # or your key path
```

### Container won't start

Check the Docker image built successfully:

```bash
docker images | grep claude_sandbox
```

Rebuild if needed:

```bash
docker build --no-cache -f docker/Dockerfile -t claude_sandbox .
```

### Previous session won't resume

Check for existing containers:

```bash
docker ps -a
```

Remove stalled containers:

```bash
docker rm <container-id>
```

Then restart the session script.

## Development

### Adding Tools to the Container

Modify `docker/Dockerfile` and add `apt-get install` commands in the system dependencies section, then rebuild:

```bash
docker build -f docker/Dockerfile -t claude_sandbox .
```

### Updating Claude Code Version

Edit `docker/Dockerfile` and modify the npm install line:

```dockerfile
RUN npm install -g @anthropic-ai/claude-code@<version> && \
    npm cache clean --force
```

### Testing the Build

Verify the image builds and tools are available:

```bash
docker build -f docker/Dockerfile -t claude_sandbox .
docker run --rm claude_sandbox claude --version
docker run --rm claude_sandbox node --version
docker run --rm claude_sandbox uv --version
```

## Security Notes

- The container runs as the unprivileged `agent` user
- Credentials are mounted as read-only volumes
- `--group-add=root` is used for specific operations requiring elevated privileges
- No secrets should be committed to the repository
- `.application_default_credentials.json` is in `.gitignore` to prevent accidental leaks

## License

See LICENSE file for details.
