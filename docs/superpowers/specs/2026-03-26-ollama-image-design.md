# Ollama Image & Base Image Split — Design Spec

## Overview

Add an Ollama service image for running local LLMs (e.g., hermes3) on RunPod, and split the current monolithic base image into two layers to support services that don't need CUDA/PyTorch.

## Architecture: Two-Tier Base

The current `images/base/` image gets split into two layers. The `images/base/` directory is removed after the split.

### `base-core` (new — `images/base-core/Dockerfile`)

Universal RunPod foundation. Every service image inherits from this.

**Contents (extracted from current base runtime stage):**
- Ubuntu 24.04
- Common system packages: git, curl, wget, nano, htop, tmux, less, net-tools, iputils-ping, procps, unzip, openssl, openssh-client, openssh-server, ca-certificates, gnupg, xz-utils, ffmpeg
- Python 3.12 with `python3.12-venv`, `python3.12-dev`, `build-essential`, `libssl-dev` (with `python3` and `python` symlinks, EXTERNALLY-MANAGED removed)
- SSH server (configured for root login, host key generation deferred to runtime)
- FileBrowser (pinned version with checksum, port 8080)
- rclone (pinned version with checksum, for S3 workspace sync)
- `start-helpers.sh` (shared shell functions: SSH, env export, FileBrowser, S3 sync)
- NVIDIA env vars (`NVIDIA_VISIBLE_DEVICES=all`, `NVIDIA_DRIVER_CAPABILITIES=all`, `NVIDIA_REQUIRE_CUDA=""`, `NVIDIA_DISABLE_REQUIRE=true`) — GPU access is needed even without PyTorch (Ollama uses the GPU directly)
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

**`start-helpers.sh` changes:**
- `start_jupyter()` function stays in the file but is only called by services that have Jupyter installed. Already opt-in (each `start.sh` chooses which helpers to call).
- `export_env_vars()` grep pattern must be updated to include `^OLLAMA_` so that `OLLAMA_HOST` and `OLLAMA_MODELS` are exported to SSH sessions. Updated pattern:
  ```
  grep -E '^RUNPOD_|^PATH=|^_=|^CUDA|^LD_LIBRARY_PATH|^PYTHONPATH|^RCLONE_|^S3_|^SYNC_|^OLLAMA_'
  ```

### `base-cuda` (renamed — `images/base-cuda/Dockerfile`)

ML-specific layer. Inherits from `base-core`.

**Contents (everything removed from base-core, plus):**
- `FROM base-core` (instead of `FROM ubuntu:24.04`)
- Builder stage: CUDA toolkit, pip-tools, PyTorch wheel installation, Jupyter + extensions
- Runtime additions: CUDA packages, Python packages from builder, Jupyter config, PyTorch constraints (`/etc/pip-torch-constraints.txt`)
- CUDA/PyTorch-specific environment variables
- Exposed port: 8888 (Jupyter)

**Invariant:** ComfyUI and AI Toolkit **must** inherit from `base-cuda`, not `base-core`. Both depend on `/etc/pip-torch-constraints.txt` (created by base-cuda) for constraining PyTorch during pip installs.

**Downstream impact:**
- To minimize the diff, the bake context key stays as `base` pointing to `base-cuda`: `contexts = { base = "target:base-cuda" }`. This way ComfyUI and AI Toolkit Dockerfiles keep `FROM base` unchanged.

## Ollama Service Image

### `images/ollama/Dockerfile`

```dockerfile
FROM base-core

# Install Ollama (pinned version)
ARG OLLAMA_VERSION
RUN curl -fSL "https://github.com/ollama/ollama/releases/download/${OLLAMA_VERSION}/ollama-linux-amd64.tgz" -o /tmp/ollama.tgz && \
  tar xzf /tmp/ollama.tgz -C /usr && \
  rm /tmp/ollama.tgz

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

# Wait for Ollama to be ready
echo "Waiting for Ollama to be ready..."
until curl -s http://localhost:11434/api/tags > /dev/null 2>&1; do sleep 1; done
echo "Ollama is ready. Pull a model with: ollama pull hermes3"

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
- Readiness check waits for Ollama API before logging "ready"

**S3 sync considerations for large models:** LLM models are multi-gigabyte files. Users with large model collections should consider:
- Increasing `SYNC_INTERVAL` (default 600s may trigger frequent large uploads)
- Disabling S3 sync entirely if using RunPod network volumes for persistence
- The sync uses `rclone sync` which mirrors local state including deletions — removing a model locally will remove it from S3 on next sync

## Build System Changes

### `docker-bake.hcl`

New target structure:

```hcl
# Ollama version pin
variable "OLLAMA_VERSION" {
  default = "v0.9.0"
}

# base-core: universal foundation (SSH, FileBrowser, rclone)
target "base-core" {
  context    = "."
  dockerfile = "images/base-core/Dockerfile"
  platforms  = ["linux/amd64"]
  tags = [
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
    "andyhite/runpod-ollama:latest"
  ]
  args = {
    OLLAMA_VERSION = OLLAMA_VERSION
  }
}

# ComfyUI — inherits from base-cuda
# Context key stays as "base" so Dockerfile keeps `FROM base` unchanged
target "comfyui" {
  context    = "."
  contexts   = { base = "target:base-cuda" }
  dockerfile = "images/comfyui/Dockerfile"
  # ... rest unchanged
}

# AI Toolkit — inherits from base-cuda
# Context key stays as "base" so Dockerfile keeps `FROM base` unchanged
target "ai-toolkit" {
  context    = "."
  contexts   = { base = "target:base-cuda" }
  dockerfile = "images/ai-toolkit/Dockerfile"
  # ... rest unchanged
}

# Default build group
group "default" {
  targets = ["comfyui", "ai-toolkit", "ollama"]
}
```

**TAG handling:** The `cuda${CUDA_VERSION}` tag applies to base-cuda and its downstream images. The Ollama image uses only `latest` since it has no CUDA version dimension. The base-core image also uses only `latest`.

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
├── comfyui/                # UNCHANGED (FROM base still works via bake context key)
│   ├── Dockerfile
│   ├── start.sh
│   └── scripts/
│       └── prebake-manager-cache.py
└── ai-toolkit/             # UNCHANGED (FROM base still works via bake context key)
    ├── Dockerfile
    └── start.sh
```

The old `images/base/` directory is removed.

## What Does NOT Change

- `Makefile` — already supports `SERVICE=<name>` for any target. No changes needed.
- `.env.example` — no new env vars required (OLLAMA_HOST and OLLAMA_MODELS are set in the Dockerfile).
- `scripts/fetch-hashes.sh` — Ollama has no pinned commit hashes.
- ComfyUI/AI Toolkit Dockerfiles — `FROM base` unchanged (bake context key preserved).
- ComfyUI/AI Toolkit `start.sh` scripts — no changes needed.
- ComfyUI/AI Toolkit runtime behavior — functionally identical after the split.

## What DOES Change

- `images/base/` → split into `images/base-core/` and `images/base-cuda/`
- `start-helpers.sh` — `export_env_vars()` grep pattern updated to include `^OLLAMA_`
- `docker-bake.hcl` — new `base-core` and `ollama` targets; `base` target renamed to `base-cuda`; ComfyUI/AI Toolkit contexts updated to `{ base = "target:base-cuda" }`
- `start-helpers.sh` moved from `images/base/` to `images/base-core/`
- `COPY` path in `base-core` Dockerfile updated to `images/base-core/start-helpers.sh`

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

## Usage

After deploying the Ollama image on RunPod:

1. Connect via SSH or Web Terminal
2. Pull a model: `ollama pull hermes3`
3. Run interactively: `ollama run hermes3`
4. Or connect remotely to the Ollama API on port 11434 (e.g., from SillyTavern or other clients)
