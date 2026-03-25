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

    printenv | grep -E '^RUNPOD_|^PATH=|^_=|^CUDA|^LD_LIBRARY_PATH|^PYTHONPATH|^RCLONE_|^S3_|^SYNC_' | while read -r line; do
        name=$(echo "$line" | cut -d= -f1)
        value=$(echo "$line" | cut -d= -f2-)

        echo "$name=\"$value\"" >>"$ENV_FILE"
        echo "$name DEFAULT=\"$value\"" >>"$PAM_ENV_FILE"
        echo "$name=\"$value\"" >>"$SSH_ENV_DIR"
        echo "export $name=\"$value\"" >>/etc/rp_environment
    done

    grep -q '/etc/rp_environment' ~/.bashrc 2>/dev/null || echo 'source /etc/rp_environment' >>~/.bashrc
    grep -q '/etc/rp_environment' /etc/bash.bashrc 2>/dev/null || echo 'source /etc/rp_environment' >>/etc/bash.bashrc

    chmod 644 "$ENV_FILE" "$PAM_ENV_FILE"
    chmod 600 "$SSH_ENV_DIR"
}

# Initialize FileBrowser config and user if not already done
init_filebrowser() {
    local db_file="/workspace/filebrowser.db"

    if [ ! -f "$db_file" ]; then
        echo "Initializing FileBrowser..."
        filebrowser config init --database "$db_file"
        filebrowser config set --database "$db_file" --address 0.0.0.0
        filebrowser config set --database "$db_file" --port 8080
        filebrowser config set --database "$db_file" --root /workspace
        filebrowser config set --database "$db_file" --auth.method=json
        filebrowser users add admin adminadmin12 --perm.admin --database "$db_file"
    else
        echo "Using existing FileBrowser configuration..."
    fi
}

# Start FileBrowser in background
start_filebrowser() {
    echo "Starting FileBrowser on port 8080..."
    nohup filebrowser --database /workspace/filebrowser.db &>/filebrowser.log &
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

# ---- S3 Workspace Sync ----

# Configure S3 sync if credentials are present.
# Callers must set SYNC_SERVICE before calling (e.g., SYNC_SERVICE=comfyui).
# Syncs /workspace/$SYNC_SERVICE ↔ s3://$S3_BUCKET/$SYNC_SERVICE
configure_sync() {
    if [[ -z "${S3_ACCESS_KEY_ID:-}" ]] || [[ -z "${S3_BUCKET:-}" ]]; then
        SYNC_ENABLED=false
        echo "S3 sync disabled (S3_ACCESS_KEY_ID or S3_BUCKET not set)"
        return
    fi

    if [[ -z "${SYNC_SERVICE:-}" ]]; then
        SYNC_ENABLED=false
        echo "S3 sync disabled (SYNC_SERVICE not set)"
        return
    fi

    # Map user-facing env vars to rclone's native RCLONE_ convention
    export RCLONE_S3_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
    export RCLONE_S3_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY:-}"

    SYNC_ENABLED=true
    SYNC_LOCAL="/workspace/${SYNC_SERVICE}"
    SYNC_REMOTE=":${RCLONE_REMOTE_TYPE:-s3}:${S3_BUCKET}/${SYNC_SERVICE}"
    SYNC_INTERVAL="${SYNC_INTERVAL:-600}"
    echo "S3 sync enabled: ${SYNC_LOCAL} ↔ ${SYNC_REMOTE} (interval: ${SYNC_INTERVAL}s)"
}

# Download workspace from S3 (uses rclone copy — never deletes local files)
sync_download() {
    if [[ "$SYNC_ENABLED" != "true" ]]; then return; fi

    echo "Downloading workspace from S3..."
    rclone copy "$SYNC_REMOTE" "$SYNC_LOCAL" \
        --transfers=16 \
        --checkers=32 \
        --s3-no-check-bucket \
        --fast-list \
        --stats=30s \
        --stats-one-line \
        || echo "WARNING: S3 download failed (see errors above). Continuing with local workspace."
}

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

    flock $flock_flag /tmp/sync.lock rclone sync "$SYNC_LOCAL" "$SYNC_REMOTE" \
        --transfers=16 \
        --checkers=32 \
        --s3-no-check-bucket \
        --fast-list \
        --stats=30s \
        --stats-one-line \
        || echo "WARNING: S3 upload failed or skipped (lock held). Will retry next cycle."
}

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
