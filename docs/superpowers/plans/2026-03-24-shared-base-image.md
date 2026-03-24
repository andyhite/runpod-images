# Shared Base Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract common CUDA/PyTorch/tooling layers into a shared base image, update both service images to inherit from it, and migrate all paths from `/workspace/runpod-slim/...` to `/workspace/<service-name>`.

**Architecture:** Three-tier Docker build: shared base image (CUDA, PyTorch, Jupyter, FileBrowser, SSH, common tools) -> service images (comfyui, ai-toolkit) that add app-specific setup. Each service bakes its app to `/opt/<name>-baked` at build time and copies to `/workspace/<name>` at runtime. Common shell helpers are sourced by each service's start script.

**Tech Stack:** Docker (multi-stage builds, buildx bake), Ubuntu 24.04, CUDA 13.0, PyTorch 2.10.0, Python 3.12, FileBrowser, JupyterLab, bash

**Spec:** `docs/superpowers/specs/2026-03-24-shared-base-image-design.md`

---

### Task 1: Create shared start-helpers.sh

**Files:**
- Create: `images/base/start-helpers.sh`

This script contains common shell functions sourced by each service's `start.sh`. Extracted from `services/comfyui/start.sh:15-103` (the improved versions of SSH, env export, Jupyter) plus new FileBrowser functions from `services/comfyui/start.sh:113-128`.

- [ ] **Step 1: Create `images/base/start-helpers.sh`**

```bash
#!/bin/bash
# Shared helper functions for RunPod service containers.
# Sourced by each service's start.sh — do not execute directly.

# Setup SSH with optional public key or random password
setup_ssh() {
    mkdir -p ~/.ssh

    if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
        ssh-keygen -A -q
    fi

    if [[ $PUBLIC_KEY ]]; then
        echo "$PUBLIC_KEY" >>~/.ssh/authorized_keys
        chmod 700 -R ~/.ssh
    else
        RANDOM_PASS=$(openssl rand -base64 12)
        echo "root:${RANDOM_PASS}" | chpasswd
        echo "Generated random SSH password for root: ${RANDOM_PASS}"
    fi

    echo "PermitUserEnvironment yes" >>/etc/ssh/sshd_config
    /usr/sbin/sshd
}

# Export environment variables to all session types
export_env_vars() {
    echo "Exporting environment variables..."

    ENV_FILE="/etc/environment"
    PAM_ENV_FILE="/etc/security/pam_env.conf"
    SSH_ENV_DIR="/root/.ssh/environment"

    cp "$ENV_FILE" "${ENV_FILE}.bak" 2>/dev/null || true
    cp "$PAM_ENV_FILE" "${PAM_ENV_FILE}.bak" 2>/dev/null || true

    >"$ENV_FILE"
    >"$PAM_ENV_FILE"
    mkdir -p /root/.ssh
    >"$SSH_ENV_DIR"

    printenv | grep -E '^RUNPOD_|^PATH=|^_=|^CUDA|^LD_LIBRARY_PATH|^PYTHONPATH' | while read -r line; do
        name=$(echo "$line" | cut -d= -f1)
        value=$(echo "$line" | cut -d= -f2-)

        echo "$name=\"$value\"" >>"$ENV_FILE"
        echo "$name DEFAULT=\"$value\"" >>"$PAM_ENV_FILE"
        echo "$name=\"$value\"" >>"$SSH_ENV_DIR"
        echo "export $name=\"$value\"" >>/etc/rp_environment
    done

    echo 'source /etc/rp_environment' >>~/.bashrc
    echo 'source /etc/rp_environment' >>/etc/bash.bashrc

    chmod 644 "$ENV_FILE" "$PAM_ENV_FILE"
    chmod 600 "$SSH_ENV_DIR"
}

# Initialize FileBrowser config and user if not already done
init_filebrowser() {
    local db_file="/workspace/filebrowser.db"

    if [ ! -f "$db_file" ]; then
        echo "Initializing FileBrowser..."
        filebrowser config init
        filebrowser config set --address 0.0.0.0
        filebrowser config set --port 8080
        filebrowser config set --root /workspace
        filebrowser config set --auth.method=json
        filebrowser users add admin adminadmin12 --perm.admin
    else
        echo "Using existing FileBrowser configuration..."
    fi
}

# Start FileBrowser in background
start_filebrowser() {
    echo "Starting FileBrowser on port 8080..."
    nohup filebrowser &>/filebrowser.log &
}

# Start JupyterLab server
start_jupyter() {
    mkdir -p /workspace
    echo "Starting Jupyter Lab on port 8888..."
    nohup jupyter lab \
        --allow-root \
        --no-browser \
        --port=8888 \
        --ip=0.0.0.0 \
        --FileContentsManager.delete_to_trash=False \
        --FileContentsManager.preferred_dir=/workspace \
        --ServerApp.root_dir=/workspace \
        --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}' \
        --IdentityProvider.token="${JUPYTER_PASSWORD:-}" \
        --ServerApp.allow_origin=* &>/jupyter.log &
    echo "Jupyter Lab started"
}
```

- [ ] **Step 2: Commit**

```bash
git add images/base/start-helpers.sh
git commit -m "feat: add shared start-helpers.sh with common service functions"
```

---

### Task 2: Create shared base Dockerfile

**Files:**
- Create: `images/base/Dockerfile`

This is the two-stage base image. The builder stage is extracted from `services/comfyui/Dockerfile:1-50` (build deps, CUDA, pip, PyTorch) plus Jupyter deps. The runtime stage is extracted from `services/comfyui/Dockerfile:117-224` (runtime deps, CUDA, FileBrowser, SSH, env vars) minus the ComfyUI-specific parts.

- [ ] **Step 1: Create `images/base/Dockerfile`**

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
  python3.12 -m pip install --no-cache-dir pip-tools && \
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
# Stage 2: Runtime - Clean image with pre-installed packages
# ============================================================================
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV IMAGEIO_FFMPEG_EXE=/usr/bin/ffmpeg
ENV TORCH_CUDA_ARCH_LIST="8.0 8.6 8.9 9.0 10.0 12.0"

# ---- CUDA variant (re-declared for runtime stage) ----
ARG CUDA_VERSION_DASH=13-0

# ---- FileBrowser version pin (set in docker-bake.hcl) ----
ARG FILEBROWSER_VERSION
ARG FILEBROWSER_SHA256

# Update and install runtime dependencies, CUDA, and common tools
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
  openssl \
  ffmpeg \
  && wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
  && dpkg -i cuda-keyring_1.1-1_all.deb \
  && apt-get update \
  && apt-get install -y --no-install-recommends cuda-minimal-build-${CUDA_VERSION_DASH} \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && rm cuda-keyring_1.1-1_all.deb \
  && rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED

# Copy Python packages, executables, and Jupyter data from builder stage
COPY --from=builder /usr/local/lib/python3.12 /usr/local/lib/python3.12
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /usr/local/share/jupyter /usr/local/share/jupyter

# Register Jupyter extensions (pip --ignore-installed skips post-install hooks)
RUN mkdir -p /usr/local/etc/jupyter/jupyter_server_config.d && \
  echo '{"ServerApp":{"jpserver_extensions":{"jupyter_server_terminals":true,"jupyterlab":true,"jupyter_resource_usage":true,"jupyterlab_nvdashboard":true}}}' \
  > /usr/local/etc/jupyter/jupyter_server_config.d/extensions.json

# Install FileBrowser (pinned version with checksum)
RUN curl -fSL "https://github.com/filebrowser/filebrowser/releases/download/${FILEBROWSER_VERSION}/linux-amd64-filebrowser.tar.gz" -o /tmp/fb.tar.gz && \
  echo "${FILEBROWSER_SHA256}  /tmp/fb.tar.gz" | sha256sum -c - && \
  tar xzf /tmp/fb.tar.gz -C /usr/local/bin filebrowser && \
  rm /tmp/fb.tar.gz

# Set CUDA environment variables
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64

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
  update-alternatives --set python3 /usr/bin/python3.12

# Copy shared start helpers
COPY images/base/start-helpers.sh /start-helpers.sh

# Create workspace directory
RUN mkdir -p /workspace
WORKDIR /workspace

# Expose common ports: SSH, Jupyter, FileBrowser
EXPOSE 22 8888 8080
```

- [ ] **Step 2: Commit**

```bash
git add images/base/Dockerfile
git commit -m "feat: add shared base Dockerfile with CUDA, PyTorch, Jupyter, FileBrowser"
```

---

### Task 3: Rewrite comfyui Dockerfile to use base image

**Files:**
- Rewrite: `services/comfyui/Dockerfile`

The current file is a self-contained two-stage build (`services/comfyui/Dockerfile:1-225`). The new version uses `FROM base` and only contains ComfyUI-specific setup: downloading sources, init git repos, pip-compile app deps, prebake manager cache, bake to `/opt/comfyui-baked`. The builder stage, runtime deps, FileBrowser, Jupyter, SSH config, and NVIDIA env vars are all removed (inherited from base).

- [ ] **Step 1: Rewrite `services/comfyui/Dockerfile`**

```dockerfile
# ============================================================================
# ComfyUI service image — inherits CUDA, PyTorch, Jupyter, FileBrowser from base
# ============================================================================
FROM base

# ---- Version pins (set in docker-bake.hcl) ----
ARG COMFYUI_VERSION
ARG MANAGER_SHA
ARG KJNODES_SHA
ARG CIVICOMFY_SHA
ARG RUNPODDIRECT_SHA
ARG TORCH_VERSION
ARG TORCHVISION_VERSION
ARG TORCHAUDIO_VERSION

# Download pinned source archives
WORKDIR /tmp/build
RUN curl -fSL "https://github.com/comfyanonymous/ComfyUI/archive/refs/tags/${COMFYUI_VERSION}.tar.gz" -o comfyui.tar.gz && \
  mkdir -p ComfyUI && tar xzf comfyui.tar.gz --strip-components=1 -C ComfyUI && rm comfyui.tar.gz

WORKDIR /tmp/build/ComfyUI/custom_nodes
RUN curl -fSL "https://github.com/ltdrdata/ComfyUI-Manager/archive/${MANAGER_SHA}.tar.gz" -o manager.tar.gz && \
  mkdir -p ComfyUI-Manager && tar xzf manager.tar.gz --strip-components=1 -C ComfyUI-Manager && rm manager.tar.gz && \
  curl -fSL "https://github.com/kijai/ComfyUI-KJNodes/archive/${KJNODES_SHA}.tar.gz" -o kjnodes.tar.gz && \
  mkdir -p ComfyUI-KJNodes && tar xzf kjnodes.tar.gz --strip-components=1 -C ComfyUI-KJNodes && rm kjnodes.tar.gz && \
  curl -fSL "https://github.com/MoonGoblinDev/Civicomfy/archive/${CIVICOMFY_SHA}.tar.gz" -o civicomfy.tar.gz && \
  mkdir -p Civicomfy && tar xzf civicomfy.tar.gz --strip-components=1 -C Civicomfy && rm civicomfy.tar.gz && \
  curl -fSL "https://github.com/MadiatorLabs/ComfyUI-RunpodDirect/archive/${RUNPODDIRECT_SHA}.tar.gz" -o runpoddirect.tar.gz && \
  mkdir -p ComfyUI-RunpodDirect && tar xzf runpoddirect.tar.gz --strip-components=1 -C ComfyUI-RunpodDirect && rm runpoddirect.tar.gz

# Init git repos with upstream remotes so ComfyUI-Manager can detect versions
RUN cd /tmp/build/ComfyUI && \
  git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ComfyUI ${COMFYUI_VERSION}" && git tag "${COMFYUI_VERSION}" && \
  git remote add origin https://github.com/comfyanonymous/ComfyUI.git && \
  cd /tmp/build/ComfyUI/custom_nodes/ComfyUI-Manager && \
  git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ComfyUI-Manager ${MANAGER_SHA}" && \
  git remote add origin https://github.com/ltdrdata/ComfyUI-Manager.git && \
  cd /tmp/build/ComfyUI/custom_nodes/ComfyUI-KJNodes && \
  git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ComfyUI-KJNodes ${KJNODES_SHA}" && \
  git remote add origin https://github.com/kijai/ComfyUI-KJNodes.git && \
  cd /tmp/build/ComfyUI/custom_nodes/Civicomfy && \
  git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "Civicomfy ${CIVICOMFY_SHA}" && \
  git remote add origin https://github.com/MoonGoblinDev/Civicomfy.git && \
  cd /tmp/build/ComfyUI/custom_nodes/ComfyUI-RunpodDirect && \
  git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ComfyUI-RunpodDirect ${RUNPODDIRECT_SHA}" && \
  git remote add origin https://github.com/MadiatorLabs/ComfyUI-RunpodDirect.git

# Generate lock file from all requirements, then install with hash verification
WORKDIR /tmp/build
RUN cat ComfyUI/requirements.txt > requirements.in && \
  for node_dir in ComfyUI/custom_nodes/*/; do \
  if [ -f "$node_dir/requirements.txt" ]; then \
  cat "$node_dir/requirements.txt" >> requirements.in; \
  fi; \
  done && \
  echo "GitPython" >> requirements.in && \
  echo "opencv-python" >> requirements.in && \
  echo "torch==${TORCH_VERSION}" >> constraints.txt && \
  echo "torchvision==${TORCHVISION_VERSION}" >> constraints.txt && \
  echo "torchaudio==${TORCHAUDIO_VERSION}" >> constraints.txt && \
  echo "pillow>=12.1.1" >> constraints.txt && \
  PIP_CONSTRAINT=constraints.txt pip-compile --generate-hashes --output-file=requirements.lock --strip-extras --allow-unsafe requirements.in && \
  python3.12 -m pip install --no-cache-dir --ignore-installed --require-hashes -r requirements.lock

# Pre-populate ComfyUI-Manager cache so first cold start skips the slow registry fetch
COPY services/comfyui/scripts/prebake-manager-cache.py /tmp/prebake-manager-cache.py
RUN python3.12 /tmp/prebake-manager-cache.py /tmp/build/ComfyUI/user/__manager/cache

# Bake ComfyUI + custom nodes into a known location for runtime copy
RUN cp -r /tmp/build/ComfyUI /opt/comfyui-baked

# Clean up build artifacts
RUN rm -rf /tmp/build

# Expose ComfyUI port
EXPOSE 8188

# Copy start script
COPY services/comfyui/start.sh /start.sh

WORKDIR /workspace

ENTRYPOINT ["/start.sh"]
```

- [ ] **Step 2: Commit**

```bash
git add services/comfyui/Dockerfile
git commit -m "refactor: rewrite comfyui Dockerfile to use shared base image"
```

---

### Task 4: Rewrite comfyui start.sh with updated paths

**Files:**
- Rewrite: `services/comfyui/start.sh`

Updates from current `services/comfyui/start.sh`:
- Source `/start-helpers.sh` instead of defining functions inline (removes lines 15-103)
- All `/workspace/runpod-slim/ComfyUI` paths become `/workspace/comfyui`
- Venv name changes from `.venv-cu128` to `.venv-cu130`
- Migration logic updated to handle both `.venv` and `.venv-cu128` -> `.venv-cu130`
- `FILEBROWSER_CONFIG` reference removed (handled by helpers)
- Crash recovery message updated with new venv name

- [ ] **Step 1: Rewrite `services/comfyui/start.sh`**

```bash
#!/bin/bash
set -e

# Source shared helper functions
source /start-helpers.sh

COMFYUI_DIR="/workspace/comfyui"
VENV_DIR="$COMFYUI_DIR/.venv-cu130"
ARGS_FILE="$COMFYUI_DIR/comfyui_args.txt"

# ---------------------------------------------------------------------------- #
#                               Main Program                                     #
# ---------------------------------------------------------------------------- #

# Setup environment
setup_ssh
export_env_vars
init_filebrowser
start_filebrowser
start_jupyter

# Migrate old venvs (.venv or .venv-cu128) to .venv-cu130
for OLD_VENV_NAME in .venv .venv-cu128; do
    OLD_VENV_DIR="$COMFYUI_DIR/$OLD_VENV_NAME"
    if [ -d "$OLD_VENV_DIR" ] && [ ! -d "$VENV_DIR" ]; then
        NODE_COUNT=$(find "$COMFYUI_DIR/custom_nodes" -maxdepth 2 -name "requirements.txt" 2>/dev/null | wc -l)
        echo "============================================="
        echo "  CUDA migration: $OLD_VENV_NAME -> .venv-cu130"
        echo "  Reinstalling deps for $NODE_COUNT custom nodes"
        echo "  This may take several minutes"
        echo "============================================="
        mv "$OLD_VENV_DIR" "${OLD_VENV_DIR}.bak"
        cd "$COMFYUI_DIR"
        python3.12 -m venv --system-site-packages "$VENV_DIR"
        source "$VENV_DIR/bin/activate"
        python -m ensurepip
        BAKED_NODES="ComfyUI-Manager ComfyUI-KJNodes Civicomfy ComfyUI-RunpodDirect"
        CURRENT=0
        INSTALLED=0
        for req in "$COMFYUI_DIR"/custom_nodes/*/requirements.txt; do
            if [ -f "$req" ]; then
                NODE_NAME=$(basename "$(dirname "$req")")
                case " $BAKED_NODES " in
                *" $NODE_NAME "*) continue ;;
                esac
                CURRENT=$((CURRENT + 1))
                echo "[$CURRENT] $NODE_NAME"
                pip install -r "$req" 2>&1 | grep -E "^(Successfully|ERROR)" || true
                INSTALLED=$((INSTALLED + 1))
            fi
        done
        echo "Upgrading ComfyUI requirements..."
        pip install --upgrade -r "$COMFYUI_DIR/requirements.txt" 2>&1 | grep -E "^(Successfully|ERROR)" || true
        echo "Migration complete — $INSTALLED user nodes processed (${NODE_COUNT} total, baked nodes skipped)"
        echo "Old venv backed up at ${OLD_VENV_DIR}.bak — delete it to free space:"
        echo "  rm -rf ${OLD_VENV_DIR}.bak"
        break
    fi
done

# Setup ComfyUI if needed
if [ ! -d "$COMFYUI_DIR" ] || [ ! -d "$VENV_DIR" ]; then
    echo "First time setup: Copying baked ComfyUI to workspace..."

    if [ ! -d "$COMFYUI_DIR" ]; then
        cp -r /opt/comfyui-baked "$COMFYUI_DIR"
        echo "ComfyUI copied to workspace"
    fi

    if [ ! -d "$VENV_DIR" ]; then
        cd "$COMFYUI_DIR"
        python3.12 -m venv --system-site-packages "$VENV_DIR"
        source "$VENV_DIR/bin/activate"
        python -m ensurepip
        echo "Base packages (torch, numpy, etc.) available from system site-packages"
        echo "ComfyUI ready — all dependencies pre-installed in image"
    fi
else
    source "$VENV_DIR/bin/activate"
    echo "Using existing ComfyUI installation"
fi

# Create default comfyui_args.txt if it doesn't exist
if [ ! -f "$ARGS_FILE" ]; then
    echo "# Add your custom ComfyUI arguments here (one per line)" >"$ARGS_FILE"
    echo "Created empty ComfyUI arguments file at $ARGS_FILE"
fi

# Warm up pip so ComfyUI-Manager's 5s timeout check doesn't fail on cold start
python -m pip --version >/dev/null 2>&1

# Start ComfyUI — keep container alive if it crashes so SSH/Jupyter remain accessible
cd $COMFYUI_DIR
FIXED_ARGS="--listen 0.0.0.0 --port 8188"
if [ -s "$ARGS_FILE" ]; then
    CUSTOM_ARGS=$(grep -v '^#' "$ARGS_FILE" | tr '\n' ' ')
    if [ ! -z "$CUSTOM_ARGS" ]; then
        FIXED_ARGS="$FIXED_ARGS $CUSTOM_ARGS"
    fi
fi

echo "Starting ComfyUI with args: $FIXED_ARGS"
python main.py $FIXED_ARGS &
COMFY_PID=$!
trap "kill $COMFY_PID 2>/dev/null" SIGTERM SIGINT
wait $COMFY_PID || true

echo "============================================="
echo "  ComfyUI crashed — check the logs above."
echo "  SSH and JupyterLab are still available."
echo "  To restart after fixing:"
echo "    cd $COMFYUI_DIR && source .venv-cu130/bin/activate"
echo "    python main.py $FIXED_ARGS"
echo "============================================="

sleep infinity
```

- [ ] **Step 2: Commit**

```bash
git add services/comfyui/start.sh
git commit -m "refactor: update comfyui start.sh to use shared helpers and new paths"
```

---

### Task 5: Rewrite ai-toolkit Dockerfile to use base image

**Files:**
- Rewrite: `services/ai-toolkit/Dockerfile`

Replaces the current single-stage build (`services/ai-toolkit/Dockerfile:1-83`) with a `FROM base` image that only adds Node.js, clones the repo, installs deps, builds the UI, and bakes to `/opt/ai-toolkit-baked`.

- [ ] **Step 1: Rewrite `services/ai-toolkit/Dockerfile`**

```dockerfile
# ============================================================================
# AI Toolkit service image — inherits CUDA, PyTorch, Jupyter, FileBrowser from base
# ============================================================================
FROM base

# Install Node.js (needed for AI Toolkit UI)
RUN curl -sL https://deb.nodesource.com/setup_23.x -o /tmp/nodesource_setup.sh && \
  bash /tmp/nodesource_setup.sh && \
  apt-get update && \
  apt-get install -y nodejs && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* /tmp/nodesource_setup.sh

# Clone AI Toolkit repo (CACHEBUST invalidates cache to pull latest)
ARG CACHEBUST=1234
ARG GIT_COMMIT=main
WORKDIR /tmp/build
RUN echo "Cache bust: ${CACHEBUST}" && \
  git clone https://github.com/ostris/ai-toolkit.git && \
  cd ai-toolkit && \
  git checkout ${GIT_COMMIT}

WORKDIR /tmp/build/ai-toolkit

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt && \
  pip install setuptools==69.5.1 --no-cache-dir

# Build UI
WORKDIR /tmp/build/ai-toolkit/ui
RUN npm install && \
  npm run build && \
  npm run update_db

# Bake to known location for runtime copy
RUN cp -r /tmp/build/ai-toolkit /opt/ai-toolkit-baked

# Clean up build artifacts
RUN rm -rf /tmp/build

# Expose AI Toolkit UI port
EXPOSE 8675

# Copy start script
COPY services/ai-toolkit/start.sh /start.sh

WORKDIR /workspace

ENTRYPOINT ["/start.sh"]
```

- [ ] **Step 2: Commit**

```bash
git add services/ai-toolkit/Dockerfile
git commit -m "refactor: rewrite ai-toolkit Dockerfile to use shared base image"
```

---

### Task 6: Rewrite ai-toolkit start.sh

**Files:**
- Rewrite: `services/ai-toolkit/start.sh`

Replaces the current minimal script (`services/ai-toolkit/start.sh:1-68`) with the full pattern: source helpers, setup SSH/env/FileBrowser/Jupyter, copy baked app on first run, start app with crash recovery.

- [ ] **Step 1: Rewrite `services/ai-toolkit/start.sh`**

```bash
#!/bin/bash
set -e

# Source shared helper functions
source /start-helpers.sh

AI_TOOLKIT_DIR="/workspace/ai-toolkit"

# ---------------------------------------------------------------------------- #
#                               Main Program                                     #
# ---------------------------------------------------------------------------- #

# Setup environment
setup_ssh
export_env_vars
init_filebrowser
start_filebrowser
start_jupyter

# Setup AI Toolkit if needed
if [ ! -d "$AI_TOOLKIT_DIR" ]; then
    echo "First time setup: Copying baked AI Toolkit to workspace..."
    cp -r /opt/ai-toolkit-baked "$AI_TOOLKIT_DIR"
    echo "AI Toolkit copied to workspace"
else
    echo "Using existing AI Toolkit installation"
fi

# Start AI Toolkit UI — keep container alive if it crashes so SSH/Jupyter remain accessible
echo "Starting AI Toolkit UI..."
cd "$AI_TOOLKIT_DIR/ui"
npm run start &
APP_PID=$!
trap "kill $APP_PID 2>/dev/null" SIGTERM SIGINT
wait $APP_PID || true

echo "============================================="
echo "  AI Toolkit crashed — check the logs above."
echo "  SSH and JupyterLab are still available."
echo "  To restart after fixing:"
echo "    cd $AI_TOOLKIT_DIR/ui && npm run start"
echo "============================================="

sleep infinity
```

- [ ] **Step 2: Commit**

```bash
git add services/ai-toolkit/start.sh
git commit -m "refactor: rewrite ai-toolkit start.sh to use shared helpers and bake pattern"
```

---

### Task 7: Update docker-bake.hcl

**Files:**
- Modify: `docker-bake.hcl`

Add `base` target, add `ai-toolkit` target with `contexts`, update `comfyui` target to use `contexts` and remove args that are now in the base (CUDA, PyTorch, FileBrowser), update default group.

- [ ] **Step 1: Rewrite `docker-bake.hcl`**

Replace the entire file with:

```hcl
# CUDA version pins
variable "CUDA_VERSION_MAJOR" {
  default = "13"
}
variable "CUDA_VERSION_MINOR" {
  default = "0"
}
variable "CUDA_VERSION" {
  default = "${CUDA_VERSION_MAJOR}.${CUDA_VERSION_MINOR}"
}
variable "CUDA_VERSION_DASH" {
  default = "${CUDA_VERSION_MAJOR}-${CUDA_VERSION_MINOR}"
}

# PyTorch version pins
variable "TORCHAUDIO_VERSION" {
  default = "2.10.0"
}
variable "TORCHVISION_VERSION" {
  default = "0.25.0"
}
variable "TORCH_INDEX_SUFFIX" {
  default = "cu130"
}
variable "TORCH_VERSION" {
  default = "2.10.0"
}

# Application version pins
variable "COMFYUI_VERSION" {
  default = "v0.17.2"
}
variable "FILEBROWSER_SHA256" {
  default = "8cd8c3baecb086028111b912f252a6e3169737fa764b5c510139e81f9da87799"
}
variable "FILEBROWSER_VERSION" {
  default = "v2.59.0"
}

# Custom node hashes (run scripts/fetch-hashes.sh to update)
variable "CIVICOMFY_SHA" {
  default = "555e984bbcb0"
}
variable "KJNODES_SHA" {
  default = "6dfca48e00a5"
}
variable "MANAGER_SHA" {
  default = "c94236a61457"
}
variable "RUNPODDIRECT_SHA" {
  default = "4de8269b5181"
}

# Docker image tag
variable "TAG" {
  default = "cuda${CUDA_VERSION}"
}

# Build groups
group "default" {
  targets = ["comfyui", "ai-toolkit"]
}

# Shared base image target
target "base" {
  context    = "."
  dockerfile = "images/base/Dockerfile"
  platforms  = ["linux/amd64"]
  tags = [
    "andyhite/runpod-base:${TAG}",
    "andyhite/runpod-base:latest"
  ]
  args = {
    CUDA_VERSION_DASH   = CUDA_VERSION_DASH
    FILEBROWSER_SHA256  = FILEBROWSER_SHA256
    FILEBROWSER_VERSION = FILEBROWSER_VERSION
    TORCHAUDIO_VERSION  = TORCHAUDIO_VERSION
    TORCHVISION_VERSION = TORCHVISION_VERSION
    TORCH_INDEX_SUFFIX  = TORCH_INDEX_SUFFIX
    TORCH_VERSION       = TORCH_VERSION
  }
}

# ComfyUI service image
target "comfyui" {
  context    = "."
  contexts   = { base = "target:base" }
  dockerfile = "services/comfyui/Dockerfile"
  platforms  = ["linux/amd64"]
  tags = [
    "andyhite/runpod-comfyui:${TAG}",
    "andyhite/runpod-comfyui:latest"
  ]
  args = {
    CIVICOMFY_SHA       = CIVICOMFY_SHA
    COMFYUI_VERSION     = COMFYUI_VERSION
    KJNODES_SHA         = KJNODES_SHA
    MANAGER_SHA         = MANAGER_SHA
    RUNPODDIRECT_SHA    = RUNPODDIRECT_SHA
    TORCHAUDIO_VERSION  = TORCHAUDIO_VERSION
    TORCHVISION_VERSION = TORCHVISION_VERSION
    TORCH_VERSION       = TORCH_VERSION
  }
}

# AI Toolkit service image
target "ai-toolkit" {
  context    = "."
  contexts   = { base = "target:base" }
  dockerfile = "services/ai-toolkit/Dockerfile"
  platforms  = ["linux/amd64"]
  tags = [
    "andyhite/runpod-ai-toolkit:${TAG}",
    "andyhite/runpod-ai-toolkit:latest"
  ]
  args = {
    CACHEBUST  = ""
    GIT_COMMIT = "main"
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add docker-bake.hcl
git commit -m "refactor: add base and ai-toolkit targets, update comfyui to use base context"
```

---

### Task 8: Update Makefile for multi-service support

**Files:**
- Modify: `Makefile`

Update build commands to use `docker buildx bake $(SERVICE)`, derive `IMAGE_NAME` from `SERVICE`, update `FULL_IMAGE` to use `runpod-` prefix.

- [ ] **Step 1: Update Makefile**

Replace the Configuration section and Build Commands section. The changes are:

1. `IMAGE_NAME` becomes `runpod-$(SERVICE)` (line 8)
2. `build` target uses `docker buildx bake $(SERVICE)` (line 49)
3. `push` target uses `docker buildx bake $(SERVICE) --push` (line 52)
4. `push-fresh` target uses `docker buildx bake $(SERVICE) --push` (line 55)

Full file:

```makefile
# Load environment variables
include .env
export

# Configuration
SERVICE := comfyui
REGISTRY := andyhite
IMAGE_NAME := runpod-$(SERVICE)
IMAGE_TAG := latest
DSTACK_PID_FILE := .dstack.pid

# Derived
SERVICE_DIR := services/$(SERVICE)
FULL_IMAGE := $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)

# ============ Server Commands ============
.PHONY: server-start server-stop server-status

server-start:                   ## Start dstack server (background)
	@if [ -f $(DSTACK_PID_FILE) ] && kill -0 $$(cat $(DSTACK_PID_FILE)) 2>/dev/null; then \
		echo "dstack server already running (PID $$(cat $(DSTACK_PID_FILE)))"; \
	else \
		echo "Starting dstack server..."; \
		dstack server --token $(DSTACK_TOKEN) > .dstack.log 2>&1 & \
		echo $$! > $(DSTACK_PID_FILE); \
		sleep 2; \
		echo "dstack server started (PID $$(cat $(DSTACK_PID_FILE)))"; \
	fi

server-stop:                    ## Stop dstack server
	@if [ -f $(DSTACK_PID_FILE) ]; then \
		kill $$(cat $(DSTACK_PID_FILE)) 2>/dev/null && echo "dstack server stopped" || echo "Server not running"; \
		rm -f $(DSTACK_PID_FILE); \
	else \
		echo "No PID file found"; \
	fi

server-status:                  ## Check dstack server status
	@if [ -f $(DSTACK_PID_FILE) ] && kill -0 $$(cat $(DSTACK_PID_FILE)) 2>/dev/null; then \
		echo "dstack server running (PID $$(cat $(DSTACK_PID_FILE)))"; \
	else \
		echo "dstack server not running"; \
	fi

# ============ Build Commands ============
.PHONY: build push push-fresh

build:                          ## Build Docker image using bake
	docker buildx bake $(SERVICE)

push:                           ## Build and push to RunPod registry
	docker buildx bake $(SERVICE) --push

push-fresh:                     ## Build and push with cache-busting timestamp tag
	BUILD_ID=$$(date +%Y%m%d%H%M%S) docker buildx bake $(SERVICE) --push

# ============ Volume Commands ============
.PHONY: volume-init volume-status

volume-init:                    ## Initialize/verify volume exists
	dstack apply -f $(SERVICE_DIR)/volume.dstack.yml

volume-status:                  ## Check volume status
	dstack volume list

# ============ Service Commands ============
.PHONY: start stop status logs

start: push volume-init         ## Deploy service (builds, pushes, starts)
	PUBLIC_KEY=$$(cat $(PUBLIC_KEY_FILE)) \
	RUNPOD_REGISTRY_IMAGE=$(FULL_IMAGE) \
	dstack apply -f $(SERVICE_DIR)/service.dstack.yml

stop:                           ## Stop running service
	dstack stop $(SERVICE)

status:                         ## Show service status
	dstack ps

logs:                           ## Tail service logs
	dstack logs $(SERVICE) -f

# ============ Validation Commands ============
.PHONY: offers plan

offers:                         ## Show available GPU offers and pricing
	dstack offer --gpu RTX5090 --region $(DSTACK_REGION) --max-offers 10

plan:                           ## Show deployment plan (dry-run, no confirm)
	@echo "Service deployment plan:"
	@PUBLIC_KEY=$$(cat $(PUBLIC_KEY_FILE)) \
	RUNPOD_REGISTRY_IMAGE=$(FULL_IMAGE) \
	dstack apply -f $(SERVICE_DIR)/service.dstack.yml

# ============ Utilities ============
.PHONY: ssh clean help

ssh:                            ## SSH into running service
	dstack ssh $(SERVICE)

clean:                          ## Remove local Docker images
	docker rmi $(FULL_IMAGE) || true

help:                           ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
```

- [ ] **Step 2: Commit**

```bash
git add Makefile
git commit -m "refactor: update Makefile for multi-service bake targets"
```

---

### Task 9: Delete obsolete comfyui-5090 service

**Files:**
- Delete: `services/comfyui-5090/` (entire directory — already marked as deleted in git status)

The git status shows these files are already deleted from the working tree. This task just stages the deletions.

- [ ] **Step 1: Stage deletions**

```bash
git add services/comfyui-5090/
git commit -m "chore: remove obsolete comfyui-5090 service directory"
```

---

### Task 10: Verify build configuration

This is a manual validation step — not automated tests, since Docker builds require a Docker daemon with buildx.

- [ ] **Step 1: Validate bake config parses correctly**

```bash
docker buildx bake --print
```

Expected: JSON output showing three targets (base, comfyui, ai-toolkit) with correct args and contexts.

- [ ] **Step 2: Validate individual service targets**

```bash
docker buildx bake --print comfyui
docker buildx bake --print ai-toolkit
```

Expected: Each shows the service target with `base` in contexts.

- [ ] **Step 3: Commit all remaining changes**

If any files were missed, stage and commit them now.
