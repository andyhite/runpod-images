# S3 Workspace Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add rclone-based S3 workspace sync to RunPod containers so pods can start in any region without being locked to a storage volume.

**Architecture:** Four sync functions added to the shared `start-helpers.sh` (configure, download, upload, periodic). Each service's `start.sh` calls them at the right lifecycle points. rclone installed in the base Docker image. SIGTERM trap performs final upload before exit.

**Tech Stack:** rclone v1.73.3, bash, Docker (multi-stage), docker-bake.hcl (BuildKit)

**Spec:** `docs/superpowers/specs/2026-03-25-s3-workspace-sync-design.md`

---

### Task 1: Install rclone in base Dockerfile

**Files:**
- Modify: `docker-bake.hcl:36-41` (add version variables)
- Modify: `docker-bake.hcl:76-84` (add args to base target)
- Modify: `images/base/Dockerfile:74-76` (add ARGs)
- Modify: `images/base/Dockerfile:123-127` (add install step after FileBrowser)

- [ ] **Step 1: Add rclone version variables to `docker-bake.hcl`**

After the `FILEBROWSER_VERSION` variable block (line 41), add:

```hcl
variable "RCLONE_SHA256" {
  default = "70278c22b98c7d02aed01828b70053904dbce4c8a1a15d7781d836c6fdb036ea"
}
variable "RCLONE_VERSION" {
  default = "v1.73.3"
}
```

- [ ] **Step 2: Pass rclone args to the base target in `docker-bake.hcl`**

In the `base` target's `args` block (around line 77), add these two entries alongside the existing args:

```hcl
    RCLONE_SHA256       = RCLONE_SHA256
    RCLONE_VERSION      = RCLONE_VERSION
```

- [ ] **Step 3: Add ARG declarations to base Dockerfile**

In `images/base/Dockerfile`, after the `FILEBROWSER_SHA256` ARG (line 76), add:

```dockerfile
ARG RCLONE_VERSION
ARG RCLONE_SHA256
```

- [ ] **Step 4: Add rclone install step to base Dockerfile**

In `images/base/Dockerfile`, after the FileBrowser install block (after line 127), add:

First, add `unzip` to the existing `apt-get install` block in the runtime stage (around line 81), alongside the other packages. This avoids a redundant `apt-get update` in the rclone layer. Add it after `procps`:

```
  procps \
  unzip \
  openssl \
```

Then add the rclone install block after the FileBrowser install (after line 127):

```dockerfile
# Install rclone (pinned version with checksum)
RUN curl -fSL "https://downloads.rclone.org/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-linux-amd64.zip" -o /tmp/rclone.zip && \
  echo "${RCLONE_SHA256}  /tmp/rclone.zip" | sha256sum -c - && \
  unzip -j /tmp/rclone.zip "*/rclone" -d /usr/local/bin && \
  chmod +x /usr/local/bin/rclone && \
  rm /tmp/rclone.zip
```

Note: `unzip` is installed in the main apt-get block. The `-j` flag extracts just the binary without directory structure.

- [ ] **Step 5: Verify the Dockerfile parses correctly**

Run: `docker buildx bake --print base 2>&1 | head -20`

Expected: JSON output showing the base target with `RCLONE_VERSION` and `RCLONE_SHA256` in the args.

- [ ] **Step 6: Commit**

```bash
git add docker-bake.hcl images/base/Dockerfile
git commit -m "feat: add rclone to base image for S3 workspace sync"
```

---

### Task 2: Add sync functions to `start-helpers.sh`

**Files:**
- Modify: `images/base/start-helpers.sh` (add 4 new functions at end of file)

- [ ] **Step 1: Add `configure_sync()` function**

Append to `images/base/start-helpers.sh`:

```bash
# ---- S3 Workspace Sync ----

# Configure S3 sync if credentials are present
configure_sync() {
    if [[ -z "${RCLONE_S3_ACCESS_KEY_ID:-}" ]] || [[ -z "${SYNC_BUCKET:-}" ]]; then
        SYNC_ENABLED=false
        echo "S3 sync disabled (RCLONE_S3_ACCESS_KEY_ID or SYNC_BUCKET not set)"
        return
    fi

    SYNC_ENABLED=true
    SYNC_REMOTE=":${RCLONE_REMOTE_TYPE:-s3}:${SYNC_BUCKET}"
    SYNC_INTERVAL="${SYNC_INTERVAL:-600}"
    echo "S3 sync enabled: ${SYNC_REMOTE} (interval: ${SYNC_INTERVAL}s)"
}
```

- [ ] **Step 2: Add `sync_download()` function**

Append to `images/base/start-helpers.sh`:

```bash
# Download workspace from S3 (uses rclone copy — never deletes local files)
sync_download() {
    if [[ "$SYNC_ENABLED" != "true" ]]; then return; fi

    echo "Downloading workspace from S3..."
    rclone copy "$SYNC_REMOTE" /workspace \
        --transfers=16 \
        --checkers=32 \
        --s3-no-check-bucket \
        --fast-list \
        --stats=30s \
        --stats-one-line \
        || echo "WARNING: S3 download failed (see errors above). Continuing with local workspace."
}
```

- [ ] **Step 3: Add `sync_upload()` function**

Append to `images/base/start-helpers.sh`:

```bash
# Upload workspace to S3 (uses rclone sync — mirrors local state, including deletions)
# Pass "wait" as first argument to block until lock is available (used by shutdown handler).
# Default is non-blocking: skip if another sync holds the lock (used by periodic sync).
sync_upload() {
    if [[ "$SYNC_ENABLED" != "true" ]]; then return; fi

    local flock_flag="-n"
    if [[ "${1:-}" == "wait" ]]; then
        flock_flag=""
        echo "Waiting for any in-progress sync to finish, then uploading workspace to S3..."
    else
        echo "Uploading workspace to S3..."
    fi

    flock $flock_flag /tmp/sync.lock rclone sync /workspace "$SYNC_REMOTE" \
        --transfers=16 \
        --checkers=32 \
        --s3-no-check-bucket \
        --fast-list \
        --stats=30s \
        --stats-one-line \
        || echo "WARNING: S3 upload failed or skipped (lock held). Will retry next cycle."
}
```

Note: `flock -n` (non-blocking) is used by the periodic sync loop — if a previous sync is still running, it skips. The shutdown handler calls `sync_upload wait` which uses blocking `flock` (no `-n`), ensuring the final sync always completes even if a periodic sync is in progress.

- [ ] **Step 4: Add `start_periodic_sync()` function**

Append to `images/base/start-helpers.sh`:

```bash
# Start periodic background sync loop
start_periodic_sync() {
    if [[ "$SYNC_ENABLED" != "true" ]]; then return; fi

    echo "Starting periodic S3 sync (every ${SYNC_INTERVAL}s)..."
    (
        while true; do
            sleep "$SYNC_INTERVAL"
            sync_upload
        done
    ) &
    SYNC_PID=$!
}
```

- [ ] **Step 5: Commit**

```bash
git add images/base/start-helpers.sh
git commit -m "feat: add S3 sync functions to start-helpers.sh"
```

---

### Task 3: Update `export_env_vars()` to include sync variables

**Files:**
- Modify: `images/base/start-helpers.sh:42` (update grep pattern)

- [ ] **Step 1: Update the printenv filter pattern**

In `images/base/start-helpers.sh`, line 42, change:

```bash
    printenv | grep -E '^RUNPOD_|^PATH=|^_=|^CUDA|^LD_LIBRARY_PATH|^PYTHONPATH' | while read -r line; do
```

to:

```bash
    printenv | grep -E '^RUNPOD_|^PATH=|^_=|^CUDA|^LD_LIBRARY_PATH|^PYTHONPATH|^RCLONE_|^SYNC_' | while read -r line; do
```

- [ ] **Step 2: Commit**

```bash
git add images/base/start-helpers.sh
git commit -m "feat: export RCLONE_* and SYNC_* env vars to SSH sessions"
```

---

### Task 4: Update ComfyUI start script

**Files:**
- Modify: `images/comfyui/start.sh` (full rewrite of startup flow and signal handling)

- [ ] **Step 1: Rewrite `images/comfyui/start.sh`**

Replace the entire file with:

```bash
#!/bin/bash
set -e

# Source shared helper functions
source /start-helpers.sh

COMFYUI_DIR="/workspace/comfyui"
ARGS_FILE="$COMFYUI_DIR/comfyui_args.txt"

# ---------------------------------------------------------------------------- #
#                               Main Program                                     #
# ---------------------------------------------------------------------------- #

# Configure S3 sync (must be before export_env_vars so SYNC_* vars are exported)
configure_sync

# Setup environment
setup_ssh
export_env_vars
init_filebrowser
start_filebrowser
start_jupyter

# Setup ComfyUI if needed
if [ ! -d "$COMFYUI_DIR" ]; then
    echo "First time setup: Copying baked ComfyUI to workspace..."
    cp -r /opt/comfyui-baked "$COMFYUI_DIR"
    echo "ComfyUI copied to workspace"
else
    echo "Using existing ComfyUI installation"
fi

# Download workspace from S3 (overlays on top of baked copy)
sync_download

# Install/update dependencies
echo "Installing/updating ComfyUI dependencies..."
pip install --no-cache-dir -r "$COMFYUI_DIR/requirements.txt" 2>&1 | tail -1
for req in "$COMFYUI_DIR"/custom_nodes/*/requirements.txt; do
    if [ -f "$req" ]; then
        pip install --no-cache-dir -r "$req" 2>&1 | tail -1
    fi
done

# Create default comfyui_args.txt if it doesn't exist
if [ ! -f "$ARGS_FILE" ]; then
    echo "# Add your custom ComfyUI arguments here (one per line)" >"$ARGS_FILE"
    echo "Created empty ComfyUI arguments file at $ARGS_FILE"
fi

# Warm up pip so ComfyUI-Manager's 5s timeout check doesn't fail on cold start
python -m pip --version >/dev/null 2>&1

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

# Start ComfyUI
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
APP_PID=$!

# Start periodic S3 sync
start_periodic_sync

# Wait for app — if it exits (crash), fall through to keep-alive
wait $APP_PID || true

echo "============================================="
echo "  ComfyUI crashed — check the logs above."
echo "  SSH and JupyterLab are still available."
echo "  To restart after fixing:"
echo "    cd $COMFYUI_DIR && python main.py $FIXED_ARGS"
echo "============================================="

# Block forever while allowing traps to fire
while true; do sleep 86400 & wait $!; done
```

- [ ] **Step 2: Commit**

```bash
git add images/comfyui/start.sh
git commit -m "feat: integrate S3 sync into ComfyUI start script"
```

---

### Task 5: Update AI Toolkit start script

**Files:**
- Modify: `images/ai-toolkit/start.sh` (full rewrite of startup flow and signal handling)

- [ ] **Step 1: Rewrite `images/ai-toolkit/start.sh`**

Replace the entire file with:

```bash
#!/bin/bash
set -e

# Source shared helper functions
source /start-helpers.sh

AI_TOOLKIT_DIR="/workspace/ai-toolkit"

# ---------------------------------------------------------------------------- #
#                               Main Program                                     #
# ---------------------------------------------------------------------------- #

# Configure S3 sync (must be before export_env_vars so SYNC_* vars are exported)
configure_sync

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

# Download workspace from S3 (overlays on top of baked copy)
sync_download

# Install/update dependencies
echo "Installing/updating AI Toolkit dependencies..."
pip install --no-cache-dir -r "$AI_TOOLKIT_DIR/requirements.txt" 2>&1 | tail -1

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

# Start AI Toolkit UI
echo "Starting AI Toolkit UI..."
cd "$AI_TOOLKIT_DIR/ui"
npm run start &
APP_PID=$!

# Start periodic S3 sync
start_periodic_sync

# Wait for app — if it exits (crash), fall through to keep-alive
wait $APP_PID || true

echo "============================================="
echo "  AI Toolkit crashed — check the logs above."
echo "  SSH and JupyterLab are still available."
echo "  To restart after fixing:"
echo "    cd $AI_TOOLKIT_DIR/ui && npm run start"
echo "============================================="

# Block forever while allowing traps to fire
while true; do sleep 86400 & wait $!; done
```

- [ ] **Step 2: Commit**

```bash
git add images/ai-toolkit/start.sh
git commit -m "feat: integrate S3 sync into AI Toolkit start script"
```

---

### Task 6: Update `.env.example`

**Files:**
- Modify: `.env.example` (add sync-related variables)

- [ ] **Step 1: Add sync variables to `.env.example`**

Append to `.env.example`:

```bash

# S3 workspace sync (optional — enables syncing /workspace to/from S3)
# Set these to activate sync. Supports any S3-compatible provider (AWS, R2, B2, etc.)
# RCLONE_S3_ACCESS_KEY_ID=your_access_key
# RCLONE_S3_SECRET_ACCESS_KEY=your_secret_key
# SYNC_BUCKET=your-bucket/optional/path
# RCLONE_S3_REGION=us-east-1
# RCLONE_S3_PROVIDER=AWS
# RCLONE_REMOTE_TYPE=s3  # rclone remote type (default: s3)
# RCLONE_S3_ENDPOINT=  # Custom endpoint for non-AWS providers (e.g., https://acct.r2.cloudflarestorage.com)
# SYNC_INTERVAL=600  # Seconds between periodic syncs (default: 600)
```

- [ ] **Step 2: Commit**

```bash
git add .env.example
git commit -m "docs: add S3 sync variables to .env.example"
```

---

### Task 7: Build verification

- [ ] **Step 1: Verify docker-bake.hcl parses correctly**

Run: `docker buildx bake --print 2>&1 | head -40`

Expected: JSON output with all targets, rclone args visible in base target.

- [ ] **Step 2: Build the base image to verify rclone installs**

Run: `docker buildx bake base --load 2>&1 | tail -20`

Expected: Build completes. Checksum verification passes.

- [ ] **Step 3: Verify rclone is installed in the image**

Run: `docker run --rm andyhite/runpod-base:latest rclone version`

Expected: Output shows `rclone v1.73.3`.

- [ ] **Step 4: Build a service image to verify start script syntax**

Run: `docker buildx bake comfyui --load 2>&1 | tail -10`

Expected: Build completes without errors.

- [ ] **Step 5: Verify start script syntax is valid**

Run: `docker run --rm andyhite/runpod-comfyui:latest bash -n /start-helpers.sh && echo "helpers OK" && docker run --rm andyhite/runpod-comfyui:latest bash -n /start.sh && echo "start OK"`

Expected: Both print OK (no syntax errors).
