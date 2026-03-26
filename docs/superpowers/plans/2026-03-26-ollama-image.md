# Ollama Image & Base Image Split — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the monolithic base Docker image into `base-core` and `base-cuda` layers, then add an Ollama service image that inherits from `base-core`.

**Architecture:** The current `images/base/` is split into `images/base-core/` (Ubuntu + SSH + FileBrowser + rclone) and `images/base-cuda/` (CUDA + PyTorch + Jupyter, inheriting from base-core). A new `images/ollama/` service image inherits from base-core directly. Downstream images (ComfyUI, AI Toolkit) are unchanged — the bake context key stays as `base` pointing to `base-cuda`.

**Tech Stack:** Docker, Docker Buildx (HCL bake), bash, Ollama

**Spec:** `docs/superpowers/specs/2026-03-26-ollama-image-design.md`

---

### Task 1: Create `base-core` Dockerfile

**Files:**
- Create: `images/base-core/Dockerfile`

This is the universal foundation layer extracted from the current `images/base/Dockerfile` runtime stage (lines 64-179), minus all CUDA/PyTorch/Jupyter content.

- [ ] **Step 1: Create `images/base-core/Dockerfile`**

```dockerfile
# ============================================================================
# base-core: Universal RunPod foundation
# SSH, FileBrowser, rclone, Python 3.12 — no CUDA or PyTorch
# ============================================================================
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# ---- FileBrowser version pin (set in docker-bake.hcl) ----
ARG FILEBROWSER_VERSION
ARG FILEBROWSER_SHA256
ARG RCLONE_VERSION
ARG RCLONE_SHA256

# Update and install runtime dependencies and common tools
RUN apt-get update && \
  apt-get upgrade -y && \
  apt-get install -y --no-install-recommends \
  git \
  python3.12 \
  python3.12-venv \
  python3.12-dev \
  build-essential \
  libssl-dev \
  wget \
  gnupg \
  xz-utils \
  openssh-client \
  openssh-server \
  nano \
  curl \
  htop \
  tmux \
  ca-certificates \
  less \
  net-tools \
  iputils-ping \
  procps \
  unzip \
  openssl \
  ffmpeg \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED

# Install pip
RUN curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
  python3.12 get-pip.py && \
  rm get-pip.py

# Install FileBrowser (pinned version with checksum)
RUN curl -fSL "https://github.com/filebrowser/filebrowser/releases/download/${FILEBROWSER_VERSION}/linux-amd64-filebrowser.tar.gz" -o /tmp/fb.tar.gz && \
  echo "${FILEBROWSER_SHA256}  /tmp/fb.tar.gz" | sha256sum -c - && \
  tar xzf /tmp/fb.tar.gz -C /usr/local/bin filebrowser && \
  rm /tmp/fb.tar.gz

# Install rclone (pinned version with checksum)
RUN curl -fSL "https://downloads.rclone.org/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-linux-amd64.zip" -o /tmp/rclone.zip && \
  echo "${RCLONE_SHA256}  /tmp/rclone.zip" | sha256sum -c - && \
  unzip -j /tmp/rclone.zip "*/rclone" -d /usr/local/bin && \
  chmod +x /usr/local/bin/rclone && \
  rm /tmp/rclone.zip

# Allow container to start on hosts with older CUDA drivers
ENV NVIDIA_REQUIRE_CUDA=""
ENV NVIDIA_DISABLE_REQUIRE=true
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all

# Configure SSH for root login
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
  sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
  mkdir -p /run/sshd && \
  rm -f /etc/ssh/ssh_host_*

# Set Python 3.12 as default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
  update-alternatives --set python3 /usr/bin/python3.12 && \
  ln -sf /usr/bin/python3 /usr/bin/python

# Copy shared start helpers
COPY images/base-core/start-helpers.sh /start-helpers.sh

# Create workspace directory
RUN mkdir -p /workspace
WORKDIR /workspace

# Expose common ports: SSH, FileBrowser
EXPOSE 22 8080
```

- [ ] **Step 2: Verify the file was created correctly**

Run: `head -5 images/base-core/Dockerfile`
Expected: The comment header and `FROM ubuntu:24.04` line

- [ ] **Step 3: Commit**

```bash
git add images/base-core/Dockerfile
git commit -m "feat: create base-core Dockerfile (universal RunPod foundation)"
```

---

### Task 2: Move `start-helpers.sh` to `base-core` and update grep pattern

**Files:**
- Move: `images/base/start-helpers.sh` → `images/base-core/start-helpers.sh`
- Modify: `images/base-core/start-helpers.sh:42` (export_env_vars grep pattern)

- [ ] **Step 1: Copy `start-helpers.sh` to `base-core`**

```bash
cp images/base/start-helpers.sh images/base-core/start-helpers.sh
```

- [ ] **Step 2: Update the `export_env_vars` grep pattern**

In `images/base-core/start-helpers.sh:42`, change:

```bash
    printenv | grep -E '^RUNPOD_|^PATH=|^_=|^CUDA|^LD_LIBRARY_PATH|^PYTHONPATH|^RCLONE_|^S3_|^SYNC_' | while read -r line; do
```

to:

```bash
    printenv | grep -E '^RUNPOD_|^PATH=|^_=|^CUDA|^LD_LIBRARY_PATH|^PYTHONPATH|^RCLONE_|^S3_|^SYNC_|^OLLAMA_' | while read -r line; do
```

- [ ] **Step 3: Commit**

```bash
git add images/base-core/start-helpers.sh
git commit -m "feat: move start-helpers.sh to base-core, add OLLAMA_ env var export"
```

---

### Task 3: Create `base-cuda` Dockerfile

**Files:**
- Create: `images/base-cuda/Dockerfile`

This image inherits from `base-core` and adds the CUDA/PyTorch/Jupyter layers. It combines the builder stage (current `images/base/Dockerfile:1-59`) and the CUDA-specific parts of the runtime stage.

- [ ] **Step 1: Create `images/base-cuda/Dockerfile`**

```dockerfile
# ============================================================================
# Stage 1: Builder - Install CUDA, PyTorch, and shared Python packages
# ============================================================================
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# ---- Version pins (set in docker-bake.hcl) ----
ARG CUDA_VERSION_DASH=13-0
ARG TORCH_INDEX_SUFFIX=cu130
ARG TORCH_VERSION
ARG TORCHVISION_VERSION
ARG TORCHAUDIO_VERSION

# Install minimal dependencies needed for building
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  wget \
  curl \
  git \
  ca-certificates \
  python3.12 \
  python3.12-venv \
  python3.12-dev \
  build-essential \
  && wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
  && dpkg -i cuda-keyring_1.1-1_all.deb \
  && apt-get update \
  && apt-get install -y --no-install-recommends cuda-minimal-build-${CUDA_VERSION_DASH} libcusparse-dev-${CUDA_VERSION_DASH} \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && rm cuda-keyring_1.1-1_all.deb \
  && rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED

# Install pip and pip-tools for lock file generation
RUN curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
  python3.12 get-pip.py && \
  python3.12 -m pip install --no-cache-dir "pip-tools>=7.0" && \
  rm get-pip.py

# Set CUDA environment for building
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64

# Install PyTorch (pinned version)
RUN python3.12 -m pip install --no-cache-dir \
  torch==${TORCH_VERSION} torchvision==${TORCHVISION_VERSION} torchaudio==${TORCHAUDIO_VERSION} \
  --index-url https://download.pytorch.org/whl/${TORCH_INDEX_SUFFIX}

# Install Jupyter and shared Python packages, generate lock file
WORKDIR /tmp/build
RUN echo "jupyter" > requirements.in && \
  echo "jupyter-resource-usage" >> requirements.in && \
  echo "jupyterlab-nvdashboard" >> requirements.in && \
  echo "torch==${TORCH_VERSION}" >> constraints.txt && \
  echo "torchvision==${TORCHVISION_VERSION}" >> constraints.txt && \
  echo "torchaudio==${TORCHAUDIO_VERSION}" >> constraints.txt && \
  PIP_CONSTRAINT=constraints.txt pip-compile --generate-hashes --output-file=requirements.lock --strip-extras --allow-unsafe requirements.in && \
  python3.12 -m pip install --no-cache-dir --ignore-installed --require-hashes -r requirements.lock

# ============================================================================
# Stage 2: Runtime - Add CUDA/PyTorch/Jupyter on top of base-core
# ============================================================================
FROM base-core

ENV IMAGEIO_FFMPEG_EXE=/usr/bin/ffmpeg
ENV TORCH_CUDA_ARCH_LIST="8.0 8.6 8.9 9.0 10.0 12.0"

# ---- CUDA variant (re-declared for runtime stage) ----
ARG CUDA_VERSION_DASH=13-0

# Install CUDA runtime packages
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb && \
  dpkg -i cuda-keyring_1.1-1_all.deb && \
  apt-get update && \
  apt-get install -y --no-install-recommends cuda-minimal-build-${CUDA_VERSION_DASH} && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  rm cuda-keyring_1.1-1_all.deb

# Copy Python packages and Jupyter data from builder stage
COPY --from=builder /usr/local/lib/python3.12 /usr/local/lib/python3.12
COPY --from=builder /usr/local/share/jupyter /usr/local/share/jupyter

# Copy specific executables from builder (avoid overwriting filebrowser/rclone from base-core)
RUN --mount=from=builder,src=/usr/local/bin,dst=/tmp/builder-bin \
  cp /tmp/builder-bin/pip* /usr/local/bin/ && \
  cp /tmp/builder-bin/pip-compile /usr/local/bin/ && \
  cp /tmp/builder-bin/pip-sync /usr/local/bin/ && \
  cp /tmp/builder-bin/jupyter* /usr/local/bin/ && \
  cp /tmp/builder-bin/ipython* /usr/local/bin/ 2>/dev/null || true

# Register Jupyter extensions (pip --ignore-installed skips post-install hooks)
RUN mkdir -p /usr/local/etc/jupyter/jupyter_server_config.d && \
  echo '{"ServerApp":{"jpserver_extensions":{"jupyter_server_terminals":true,"jupyterlab":true,"jupyter_resource_usage":true,"jupyterlab_nvdashboard":true}}}' \
  > /usr/local/etc/jupyter/jupyter_server_config.d/extensions.json

# ---- PyTorch version pins (re-declared for runtime stage) ----
ARG TORCH_VERSION
ARG TORCHVISION_VERSION
ARG TORCHAUDIO_VERSION

# Pin PyTorch packages so runtime pip installs cannot overwrite the CUDA wheels
RUN echo "torch==${TORCH_VERSION}" > /etc/pip-torch-constraints.txt && \
  echo "torchvision==${TORCHVISION_VERSION}" >> /etc/pip-torch-constraints.txt && \
  echo "torchaudio==${TORCHAUDIO_VERSION}" >> /etc/pip-torch-constraints.txt

# Set CUDA and PyTorch library paths
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/lib/python3.12/dist-packages/torch/lib:/usr/local/lib/python3.12/dist-packages/torchaudio/lib:/usr/local/cuda/lib64

# Expose Jupyter port
EXPOSE 8888
```

- [ ] **Step 2: Verify the file was created correctly**

Run: `grep -c '^FROM' images/base-cuda/Dockerfile`
Expected: `2` (ubuntu:24.04 AS builder, base-core)

- [ ] **Step 3: Commit**

```bash
git add images/base-cuda/Dockerfile
git commit -m "feat: create base-cuda Dockerfile (CUDA + PyTorch + Jupyter layer)"
```

---

### Task 4: Create Ollama image

**Files:**
- Create: `images/ollama/Dockerfile`
- Create: `images/ollama/start.sh`

- [ ] **Step 1: Create `images/ollama/Dockerfile`**

```dockerfile
# ============================================================================
# Ollama service image — inherits SSH, FileBrowser, rclone from base-core
# ============================================================================
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

- [ ] **Step 2: Create `images/ollama/start.sh`**

```bash
#!/bin/bash
set -e

# Source shared helper functions
source /start-helpers.sh

OLLAMA_DIR="/workspace/ollama"

# ---------------------------------------------------------------------------- #
#                               Main Program                                     #
# ---------------------------------------------------------------------------- #

# Configure S3 sync (must be before export_env_vars so SYNC_* vars are exported)
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

- [ ] **Step 3: Make start.sh executable**

```bash
chmod +x images/ollama/start.sh
```

- [ ] **Step 4: Commit**

```bash
git add images/ollama/Dockerfile images/ollama/start.sh
git commit -m "feat: add Ollama service image"
```

---

### Task 5: Update `docker-bake.hcl`

**Files:**
- Modify: `docker-bake.hcl`

- [ ] **Step 1: Add `OLLAMA_VERSION` variable**

After the `RCLONE_VERSION` variable block (line 46), add:

```hcl
variable "OLLAMA_VERSION" {
  default = "v0.9.0"
}
```

- [ ] **Step 2: Replace `base` target with `base-core` and `base-cuda` targets**

Replace the current `target "base"` block (lines 74-93) with:

```hcl
# Universal foundation (SSH, FileBrowser, rclone — no CUDA/PyTorch)
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

# ML stack (CUDA, PyTorch, Jupyter) — inherits from base-core
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
```

- [ ] **Step 3: Update ComfyUI and AI Toolkit targets**

In the `comfyui` target (line 98), change:
```hcl
  contexts   = { base = "target:base" }
```
to:
```hcl
  contexts   = { base = "target:base-cuda" }
```

In the `ai-toolkit` target (line 120), make the same change:
```hcl
  contexts   = { base = "target:base" }
```
to:
```hcl
  contexts   = { base = "target:base-cuda" }
```

- [ ] **Step 4: Add Ollama target**

After the `ai-toolkit` target, add:

```hcl
# Ollama service image — inherits from base-core (no CUDA/PyTorch)
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
```

- [ ] **Step 5: Update default build group**

Change:
```hcl
group "default" {
  targets = ["comfyui", "ai-toolkit"]
}
```
to:
```hcl
group "default" {
  targets = ["comfyui", "ai-toolkit", "ollama"]
}
```

- [ ] **Step 6: Commit**

```bash
git add docker-bake.hcl
git commit -m "feat: update bake config for base-core/base-cuda split and ollama target"
```

---

### Task 6: Remove old `images/base/` directory

**Files:**
- Delete: `images/base/Dockerfile`
- Delete: `images/base/start-helpers.sh`

- [ ] **Step 1: Remove the old base directory**

```bash
rm -rf images/base
```

- [ ] **Step 2: Verify removal and that base-core has the files**

```bash
ls images/base-core/
```

Expected: `Dockerfile  start-helpers.sh`

- [ ] **Step 3: Commit**

```bash
git add -A images/base
git commit -m "chore: remove old images/base/ directory (replaced by base-core + base-cuda)"
```

---

### Task 7: Build validation

**Files:** None (validation only)

- [ ] **Step 1: Validate bake file parses correctly**

```bash
docker buildx bake --print 2>&1 | head -20
```

Expected: JSON output showing all targets with resolved args. No parse errors.

- [ ] **Step 2: Build base-core image**

```bash
make build SERVICE=base-core
```

Expected: Successful build of the base-core image.

- [ ] **Step 3: Build base-cuda image**

```bash
make build SERVICE=base-cuda
```

Expected: Successful build inheriting from base-core.

- [ ] **Step 4: Build ollama image**

```bash
make build SERVICE=ollama
```

Expected: Successful build inheriting from base-core, with Ollama binary installed.

- [ ] **Step 5: Build comfyui image (regression check)**

```bash
make build SERVICE=comfyui
```

Expected: Successful build, functionally identical to before the split.

- [ ] **Step 6: Build ai-toolkit image (regression check)**

```bash
make build SERVICE=ai-toolkit
```

Expected: Successful build, functionally identical to before the split.
