# Ollama Image & Base Image Split — Design Spec

## Overview

Add an Ollama service image for running local LLMs (e.g., hermes3) on RunPod, and split the current monolithic base image into two layers to support services that don't need CUDA/PyTorch.

## Architecture: Two-Tier Base

The current `images/base/` image gets split into two layers:

### `base-core` (new — `images/base-core/Dockerfile`)

Universal RunPod foundation. Every service image inherits from this.

**Contents (extracted from current base runtime stage):**
- Ubuntu 24.04
- Common system packages: git, curl, wget, nano, htop, tmux, less, net-tools, iputils-ping, procps, unzip, openssl, openssh-client, openssh-server, ca-certificates, gnupg, xz-utils
- Python 3.12 (with `python3` and `python` symlinks, EXTERNALLY-MANAGED removed)
- SSH server (configured for root login, host key generation deferred to runtime)
- FileBrowser (pinned version with checksum, port 8080)
- rclone (pinned version with checksum, for S3 workspace sync)
- `start-helpers.sh` (shared shell functions: SSH, env export, FileBrowser, S3 sync)
- `/workspace` directory
- Exposed ports: 22 (SSH), 8080 (FileBrowser)

**What moves OUT of base-core (compared to current base):**
- CUDA keyring + cuda-minimal-build package
- Builder stage (pip-tools, PyTorch compilation)
- Python packages from builder (torch, torchvision, torchaudio, jupyter, nvdashboard, resource-usage)
- Jupyter server config + extension registration
- PyTorch constraint file (`/etc/pip-torch-constraints.txt`)
- CUDA/PyTorch environment variables (`LD_LIBRARY_PATH` torch/torchaudio paths, `TORCH_CUDA_ARCH_LIST`)
- Jupyter port exposure (8888)

**What stays but changes:**
- `python3.12-dev` and `build-essential` stay in base-core (needed for pip installs in service images)
- `libssl-dev` stays (build dependency)
- `ffmpeg` stays (general utility)
- NVIDIA env vars (`NVIDIA_VISIBLE_DEVICES=all`, `NVIDIA_DRIVER_CAPABILITIES=all`, `NVIDIA_REQUIRE_CUDA=""`, `NVIDIA_DISABLE_REQUIRE=true`) stay in base-core since GPU access is needed even without PyTorch (Ollama uses the GPU directly)

**`start-helpers.sh` changes:**
- `start_jupyter()` function stays in the file but is only called by services that have Jupyter installed. No code change needed — it's already opt-in (each `start.sh` chooses which helpers to call).

### `base-cuda` (renamed — `images/base-cuda/Dockerfile`)

ML-specific layer. Inherits from `base-core`.

**Contents (everything removed from base-core, plus):**
- `FROM base-core` (instead of `FROM ubuntu:24.04`)
- Builder stage: CUDA toolkit, pip-tools, PyTorch wheel installation, Jupyter + extensions
- Runtime additions: CUDA packages, Python packages from builder, Jupyter config, PyTorch constraints
- CUDA/PyTorch-specific environment variables
- Exposed port: 8888 (Jupyter)

**Downstream impact:**
- ComfyUI Dockerfile: `FROM base` → `FROM base-cuda` (functionally identical)
- AI Toolkit Dockerfile: `FROM base` → `FROM base-cuda` (functionally identical)

## Ollama Service Image

### `images/ollama/Dockerfile`

```dockerfile
FROM base-core

# Install Ollama
RUN curl -fsSL https://ollama.com/install.sh | sh

# Configure Ollama for remote access
ENV OLLAMA_HOST=0.0.0.0

# Store models on persistent workspace
ENV OLLAMA_MODELS=/workspace/ollama/models

# Expose Ollama API port
EXPOSE 11434

# Copy start script
COPY images/ollama/start.sh /start.sh

WORKDIR /workspace

ENTRYPOINT ["/start.sh"]
```

### `images/ollama/start.sh`

Follows the established service startup pattern:

```bash
#!/bin/bash
set -e

source /start-helpers.sh

OLLAMA_DIR="/workspace/ollama"

# Configure S3 sync
SYNC_SERVICE=ollama
configure_sync

# Setup environment
setup_ssh
export_env_vars
init_filebrowser
start_filebrowser

# Create ollama directory if needed
mkdir -p "$OLLAMA_DIR/models"

# Download workspace from S3 (restores previously synced models)
sync_download

# SIGTERM/SIGINT handler: final S3 upload before exit
shutdown() {
    set +e
    echo "Shutting down — syncing workspace to S3..."
    kill $APP_PID 2>/dev/null
    kill $SYNC_PID 2>/dev/null
    sync_upload wait
    exit 0
}
trap 'shutdown' SIGTERM SIGINT

# Start Ollama server
echo "Starting Ollama server..."
ollama serve &
APP_PID=$!

# Start periodic S3 sync
start_periodic_sync

# Wait for app — if it exits (crash), fall through to keep-alive
wait $APP_PID || true

echo "============================================="
echo "  Ollama crashed — check the logs above."
echo "  SSH and FileBrowser are still available."
echo "  To restart: ollama serve"
echo "============================================="

# Block forever while allowing traps to fire
while true; do sleep 86400 & wait $!; done
```

**Key details:**
- No `start_jupyter` call (Jupyter is not installed in base-core)
- No baked application copy (Ollama is installed system-wide, models download at runtime)
- `OLLAMA_MODELS` env var points to `/workspace/ollama/models` so models persist and sync to S3
- `OLLAMA_HOST=0.0.0.0` set at image level for remote access

## Build System Changes

### `docker-bake.hcl`

New target structure:

```hcl
# base-core: universal foundation (SSH, FileBrowser, rclone)
target "base-core" {
  context    = "."
  dockerfile = "images/base-core/Dockerfile"
  platforms  = ["linux/amd64"]
  tags = [
    "andyhite/runpod-base-core:${TAG}",
    "andyhite/runpod-base-core:latest"
  ]
  args = {
    FILEBROWSER_SHA256  = FILEBROWSER_SHA256
    FILEBROWSER_VERSION = FILEBROWSER_VERSION
    RCLONE_SHA256       = RCLONE_SHA256
    RCLONE_VERSION      = RCLONE_VERSION
  }
}

# base-cuda: ML stack (CUDA, PyTorch, Jupyter) — inherits from base-core
target "base-cuda" {
  context    = "."
  contexts   = { base-core = "target:base-core" }
  dockerfile = "images/base-cuda/Dockerfile"
  platforms  = ["linux/amd64"]
  tags = [
    "andyhite/runpod-base-cuda:${TAG}",
    "andyhite/runpod-base-cuda:latest"
  ]
  args = {
    CUDA_VERSION_DASH   = CUDA_VERSION_DASH
    TORCHAUDIO_VERSION  = TORCHAUDIO_VERSION
    TORCHVISION_VERSION = TORCHVISION_VERSION
    TORCH_INDEX_SUFFIX  = TORCH_INDEX_SUFFIX
    TORCH_VERSION       = TORCH_VERSION
  }
}

# Ollama service image — inherits from base-core
target "ollama" {
  context    = "."
  contexts   = { base-core = "target:base-core" }
  dockerfile = "images/ollama/Dockerfile"
  platforms  = ["linux/amd64"]
  tags = [
    "andyhite/runpod-ollama:${TAG}",
    "andyhite/runpod-ollama:latest"
  ]
}

# ComfyUI — inherits from base-cuda (unchanged behavior)
target "comfyui" {
  context    = "."
  contexts   = { base-cuda = "target:base-cuda" }  # was: base = "target:base"
  dockerfile = "images/comfyui/Dockerfile"
  # ... rest unchanged
}

# AI Toolkit — inherits from base-cuda (unchanged behavior)
target "ai-toolkit" {
  context    = "."
  contexts   = { base-cuda = "target:base-cuda" }  # was: base = "target:base"
  dockerfile = "images/ai-toolkit/Dockerfile"
  # ... rest unchanged
}

# Default build group
group "default" {
  targets = ["comfyui", "ai-toolkit", "ollama"]
}
```

**TAG variable:** The current `TAG` defaults to `cuda${CUDA_VERSION}`. For the Ollama image (no CUDA), this tag is misleading. Options:
- Keep it simple: Ollama target overrides with a plain tag like `latest` only
- Or change the default TAG to something version-neutral

Since Ollama doesn't have a meaningful version pin (installed via script), using just `latest` is fine for now.

### Directory Structure (after changes)

```
images/
├── base-core/              # NEW: universal foundation
│   ├── Dockerfile
│   └── start-helpers.sh    # MOVED from images/base/
├── base-cuda/              # RENAMED from images/base/
│   └── Dockerfile          # Rewritten to inherit from base-core
├── ollama/                 # NEW: Ollama service
│   ├── Dockerfile
│   └── start.sh
├── comfyui/                # UPDATED: FROM base → FROM base-cuda
│   ├── Dockerfile
│   ├── start.sh
│   └── scripts/
│       └── prebake-manager-cache.py
└── ai-toolkit/             # UPDATED: FROM base → FROM base-cuda
    ├── Dockerfile
    └── start.sh
```

## What Does NOT Change

- `start-helpers.sh` — no code changes needed. Functions are already opt-in.
- `Makefile` — already supports `SERVICE=<name>` for any target. No changes needed.
- `.env.example` — no new env vars required (OLLAMA_HOST and OLLAMA_MODELS are set in the Dockerfile).
- `scripts/fetch-hashes.sh` — Ollama has no pinned commit hashes.
- ComfyUI/AI Toolkit `start.sh` scripts — no changes needed.
- ComfyUI/AI Toolkit runtime behavior — functionally identical after the split.

## Ports Summary

| Service | Port | Protocol |
|---------|------|----------|
| SSH | 22 | TCP (base-core) |
| FileBrowser | 8080 | HTTP (base-core) |
| Jupyter | 8888 | HTTP (base-cuda) |
| Ollama API | 11434 | HTTP (ollama) |
| ComfyUI | 8188 | HTTP (comfyui) |
| AI Toolkit | 8675 | HTTP (ai-toolkit) |

## Environment Variables (Ollama-specific)

| Variable | Default | Description |
|----------|---------|-------------|
| `OLLAMA_HOST` | `0.0.0.0` | Bind address for Ollama API (set in Dockerfile) |
| `OLLAMA_MODELS` | `/workspace/ollama/models` | Model storage directory (set in Dockerfile) |

All existing env vars (S3_*, RUNPOD_*, PUBLIC_KEY, etc.) work unchanged via base-core.
