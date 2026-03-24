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
