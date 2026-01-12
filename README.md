# Claude Sandbox

A Docker-based sandbox environment that containerises Claude Code with a pre-configured development toolchain. This project provides isolated, reproducible execution of Claude Code with integrated Google Vertex AI support for model access.

## Overview

Claude Sandbox encapsulates Claude Code and its dependencies in a Docker container, eliminating environment setup complexity. It runs as a non-root user with secure credential management, persistent session support, and seamless git integration.

**Key features:**

- **Containerised environment** — Consistent toolchain across all executions
- **Session persistence** — Named containers resume where you left off
- **Credential isolation** — Read-only mounting of sensitive credentials (Google Cloud, SSH keys)
- **Smart mount strategy** — Automatically detects git repositories and mounts intelligently
- **SSH agent relay** — Use password-protected SSH keys securely in containers without exposing passphrases
- **Secure SSH for git** — SSH keys mounted read-only with optional passphrase support via relay
- **State preservation** — Claude memory and todo lists persist across sessions
- **Non-root execution** — Runs as unprivileged user for enhanced security
- **Health checks** — Built-in container health verification

## Quick Start

### Prerequisites

- **Docker** (with Daemon running) or **Podman**
- Bash shell
- Google Application Default Credentials (optional, for Vertex AI)
- SSH keys configured for GitHub (optional, for git SSH operations)

### Build the Image

**Using Docker:**

```bash
docker build -f docker/Dockerfile -t claude_sandbox .
```

**Using Podman:**

```bash
podman build -f docker/Dockerfile -t claude_sandbox .
```

### Important: Choose Your Container Runtime

Docker and Podman maintain **separate image registries**. An image built with Docker is not visible to Podman, and vice versa.

**You must build and run with the same container runtime:**

```bash
# Option A: Use Docker for both build and run
docker build -f docker/Dockerfile -t claude_sandbox .
MODEL=haiku ./claude-sandbox.sh

# Option B: Use Podman for both build and run
podman build -f docker/Dockerfile -t claude_sandbox .
MODEL=haiku CONTAINER_RUNTIME=podman ./claude-sandbox.sh
```

Do not mix runtimes (e.g., Docker build with Podman run) — the container runtime will not find the image and will attempt to pull from a remote registry, resulting in an error.

### Run Claude Code

The `MODEL` environment variable is **required**:

```bash
MODEL=haiku ./claude-sandbox.sh
```

Supported models: `haiku`, `sonnet`, `opus`, or any valid Claude model identifier.

The script automatically:
- Detects whether you're in a git repository
- Mounts your project at an appropriate location
- Forwards SSH credentials for git operations
- Passes Google Cloud credentials for Vertex AI access
- Connects to the SSH agent relay (if running) for passphrase-protected keys
- Resumes previous sessions or starts a new one
- Sets the editor to vim
- **Runs the container in a tmux session for easy reconnection**

### Tmux Session Management

Each time you run the script, the container starts in a **named tmux session**. This allows you to detach and reconnect without restarting the container.

**Session naming format:** `{runtime}-{container-name}`

Examples:
- `docker-claude-sandbox-claude` (Docker + sandbox-claude repo)
- `podman-claude-sandbox-claude` (Podman + sandbox-claude repo)

**Workflow:**

```bash
# First run: Creates tmux session and attaches
MODEL=haiku ./claude-sandbox.sh

# In the container, work as usual. When you want to exit:
# Press Ctrl+B then D to detach (keeps container running)

# Later, reconnect to the running session:
# Option 1: Run the same command again
MODEL=haiku ./claude-sandbox.sh

# Option 2: Attach directly using tmux
tmux attach -t docker-claude-sandbox-claude

# List all sessions
tmux list-sessions

# Kill a session (stops the container)
tmux kill-session -t docker-claude-sandbox-claude
```

**Benefits:**
- Container keeps running after you exit
- No need to rebuild or restart the container
- Multiple containers can run simultaneously in different sessions
- Works with both Docker and Podman

### Using SSH Keys with Passphrases (SSH Agent Relay)

If your SSH key has a passphrase, you can use it in containers without removing the passphrase:

**One-time setup per session:**

1. Start the SSH agent relay in a tmux session:
   ```bash
   tmux new-session -d -s ssh-relay './start-ssh-agent-relay.sh'
   ```
   The relay script automatically caches your passphrase and starts the relay on port 6010.

2. Start Claude Code normally:
   ```bash
   MODEL=haiku ./claude-sandbox.sh
   ```

Inside the container, SSH operations work without prompting for a passphrase:
```bash
ssh -T git@github.com
git clone git@github.com:user/repo.git
```

**How it works:** Your passphrase is cached on the host machine (never enters the container). The relay bridges your host's ssh-agent to the container via TCP, allowing containers to request signed operations without ever seeing the passphrase.

**Manage the relay:**
```bash
# View relay output
tmux attach -t ssh-relay

# Detach without stopping the relay (Ctrl+B then D)

# Stop the relay when done
tmux kill-session -t ssh-relay
```

**Optional: Auto-start relay in Ghostty**

If you use Ghostty, you can auto-start the relay when opening a new terminal by adding this to `~/.config/ghostty/config`:

```ini
initial-command = tmux new-session -d -s ssh-relay '/path/to/sandbox-claude/start-ssh-agent-relay.sh'
```

Replace `/path/to/sandbox-claude` with the actual path to your repository. This starts the relay automatically in each new terminal session.

### Using Podman Instead of Docker

To use Podman as your container runtime:

```bash
MODEL=haiku CONTAINER_RUNTIME=podman ./claude-sandbox.sh
```

SSH git operations work seamlessly with Podman. Your SSH keys from `~/.ssh` are mounted read-only into the container, enabling native git SSH operations (e.g., `git clone git@github.com:...`, `git push`, etc.) for any repository.

## How It Works

### Mount Strategy

The script intelligently determines how to mount your workspace based on whether you're in a git repository.

**In a git repository:**
- Repository root mounts at `/home/agent/<repo-name>`
- Relative paths are preserved in the container
- Container is named `claude-<repo-name>` for easy identification
- Example: In `/home/user/projects/my-app`, the repository mounts at `/home/agent/my-app`

**Outside a git repository:**
- Current directory mounts at `/home/agent/workspace`
- Container is named `claude-workspace-<hash>` based on directory path hash

### Working Directory Resolution

When the container starts, the working directory is automatically set based on your location:

**In a repository:**
- If you run the script from the repo root, you start in `/home/agent/<repo-name>`
- If you run it from a subdirectory (e.g., `src/`), you start in `/home/agent/<repo-name>/src`
- Relative paths are preserved, so `cd ../../` works as expected

**Outside a repository:**
- You always start in `/home/agent/workspace`

### Credential Handling

Credentials are securely mounted with careful attention to read/write permissions:

| Credential | Host Location | Container Path | Purpose | Read-Only |
|---|---|---|---|---|
| **Google Cloud ADC** | `~/.config/gcloud/application_default_credentials.json` | `<workspace>/.config/gcloud/...` | Vertex AI access | ✓ |
| **SSH keys** | `~/.ssh/id_*` (individual key files) | `/home/agent/.ssh/id_*` | Git SSH operations | ✓ |
| **SSH config** | Generated in container | `/home/agent/.ssh/config` | GitHub SSH settings | ✗ |
| **Claude state** | `~/.claude` | `/home/agent/.claude` | Memory and todos | ✗ |
| **Git config** | `~/.gitconfig` | `/home/agent/.gitconfig` | User identity | ✓ |
| **GitHub CLI config** | `~/.config/gh` | `/home/agent/.config/gh` | gh authentication | ✗ |
| **GitHub token** | Via `~/.claude/.env` | `GH_TOKEN` env var | gh API access | N/A |

**Note on ADC path:** Google Cloud credentials mount within your workspace. In a git repository, that's `<repo-name>/.config/gcloud/...`; outside a repository, it's `workspace/.config/gcloud/...`. The `GOOGLE_APPLICATION_CREDENTIALS` environment variable is automatically set to point to the correct location.

**Note on SSH keys:** Individual SSH key files from `~/.ssh` are mounted read-only into the container.

**Passphrase-protected keys:** If your SSH key has a passphrase, use the SSH agent relay to access it securely in containers (see "Using SSH Keys with Passphrases" in Quick Start). The relay caches your passphrase on the host and bridges access to the container via TCP, so the passphrase never enters the container.

**Passphrase-free keys:** If you prefer not to use the relay, you can remove your SSH key's passphrase: `ssh-keygen -p -f ~/.ssh/id_ed25519 -N "" -P "<passphrase>"`.

A clean SSH config is automatically generated in the container for GitHub connectivity. This works for both Docker and Podman.

**Note on git configuration:** Your host's `~/.gitconfig` is mounted read-only, ensuring your git user identity (name and email) is available for commits without risk of accidental modification.

### Session Persistence & Resilience

The script implements smart session management with graceful fallback:

**Container Lifecycle:**
1. If a named container exists for your workspace, it's restarted and you reconnect
2. If it doesn't exist, a new container is created and Claude Code starts fresh
3. All state (memory, todos, etc.) is preserved across sessions

**Resilience Strategy:**
When starting a fresh container, the script attempts to continue the previous session using the `--continue` flag. If Claude Code detects state corruption or other issues, this may fail. In such cases, the script automatically falls back to restarting the container with a clean session, ensuring you never get stuck.

This design means interrupted or problematic sessions recover gracefully without manual intervention.

## Configuration

### Environment Variables

Set these before running `./claude-sandbox.sh` to use Google Vertex AI:

```bash
export CLAUDE_CODE_USE_VERTEX=1                    # Enable Vertex AI
export CLOUD_ML_REGION=us-central1                 # Cloud region
export ANTHROPIC_VERTEX_PROJECT_ID=my-project-id  # GCP project
```

### Credential Configuration

**Git Configuration:** Your host's `~/.gitconfig` is automatically mounted read-only into the container, so your git user identity (name and email) is available for commits.

If you don't have a global git config on your host, you can set one:

```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

**Google Cloud Credentials:** If you want to use Vertex AI, ensure `~/.config/gcloud/application_default_credentials.json` exists on your host. See "Credential Handling" in the "How It Works" section for details.

**GitHub Token:** See "GitHub CLI (gh) Configuration" below for GitHub token setup.

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
- **socat** — Socket relay utility (for SSH agent relay functionality)

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

### Container Health Checks

The container includes built-in health checks that verify Claude Code is functioning correctly:

- **Health check command:** Runs `claude --version` every 30 seconds
- **Startup grace period:** 5 seconds (allows Claude Code to initialise)
- **Timeout:** 3 seconds per check
- **Retry threshold:** 3 consecutive failures before marking unhealthy

These health checks ensure your container is always in a reliable state. Docker automatically restarts unhealthy containers based on restart policies.

## Directory Structure

```
sandbox-claude/
├── README.md                         # User-facing documentation (this file)
├── CLAUDE.md                         # AI assistant guidelines and development notes
├── claude-sandbox.sh                 # Main entry point script (executable)
├── start-ssh-agent-relay.sh          # SSH agent relay script for passphrase-protected keys
├── docker/
│   └── Dockerfile                   # Container image definition with all dependencies
├── .claude/
│   ├── settings.local.json          # Claude Code permission allowlist
│   └── plans/                        # Development plans and documentation
├── .config/                          # (Optional) Host configuration directory
├── .git/                             # Git repository metadata
└── .gitignore                        # Files to exclude from version control
```

**Key Files:**
- `claude-sandbox.sh` — The main script you run; handles container lifecycle and mount strategy
- `start-ssh-agent-relay.sh` — Optional relay script to support passphrase-protected SSH keys in containers
- `Dockerfile` — Defines the container image with Node.js, Python, Git, GitHub CLI, Claude Code, and socat
- `CLAUDE.md` — Contains guidelines for AI assistants working on this project
- `settings.local.json` — Explicitly allows certain commands (Docker, GitHub, gcloud) for Claude Code security

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

**For passphrase-protected keys:**

Use the SSH agent relay to securely use password-protected keys in containers:

```bash
# On host: Start relay in tmux (caches passphrase automatically)
tmux new-session -d -s ssh-relay './start-ssh-agent-relay.sh'

# Start container (relay provides SSH agent access)
MODEL=haiku ./claude-sandbox.sh

# Inside container: SSH works without passphrase prompt
ssh -T git@github.com
```

See "Using SSH Keys with Passphrases (SSH Agent Relay)" in Quick Start for more details.

**For passphrase-free keys:**

If you prefer not to use the relay, remove your SSH key's passphrase:

```bash
ssh-keygen -p -f ~/.ssh/id_ed25519 -N "" -P "<your_current_passphrase>"
```

Replace:
- `~/.ssh/id_ed25519` with your key path (e.g., `~/.ssh/id_rsa`)
- `<your_current_passphrase>` with your actual passphrase

Then verify inside the container:

```bash
# Inside container
ssh -T git@github.com
```

This should authenticate without prompting.

### Container won't start

Check the Docker image built successfully:

```bash
docker images | grep claude_sandbox
```

Rebuild if needed:

```bash
docker build --no-cache -f docker/Dockerfile -t claude_sandbox .
```

### Working directory is incorrect

The container's working directory depends on where you run the script:

**In a git repository:**
```bash
# Running from repo root
cd /home/user/projects/my-app
./claude-sandbox.sh
# Container starts in /home/agent/my-app

# Running from subdirectory
cd /home/user/projects/my-app/src
./claude-sandbox.sh
# Container starts in /home/agent/my-app/src (relative path preserved)
```

**Outside a git repository:**
```bash
cd /tmp/my-project
./claude-sandbox.sh
# Container always starts in /home/agent/workspace
```

To verify the correct working directory inside the container:

```bash
pwd
```

If you're in the wrong directory, exit the container and re-run the script from the desired location.

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

If the container exists but `--continue` fails (corrupted state), the script automatically falls back to restarting with a clean session, so you shouldn't get stuck.

## Development

### Building the Docker Image

**Quick build (both Docker and Podman):**

```bash
./build.sh
```

This script:
- Stops all running containers using the `claude_sandbox` image
- Removes stopped containers to clean up old artifacts
- Rebuilds both Docker and Podman images with `--no-cache` to pick up all changes

**Manual builds:**

```bash
# Docker only
docker build -f docker/Dockerfile -t claude_sandbox .

# Podman only
podman build -f docker/Dockerfile -t claude_sandbox .
```

### Adding Tools to the Container

Modify `docker/Dockerfile` and add `apt-get install` commands in the system dependencies section, then rebuild:

```bash
./build.sh
```

Or manually:

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
