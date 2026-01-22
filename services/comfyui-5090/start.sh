#!/bin/bash
set -e

export COMFYUI_DIR="/app/ComfyUI"
export WORKSPACE_DIR="/workspace"
export FILEBROWSER_CONFIG="/root/.config/filebrowser/config.json"
export DB_FILE="/workspace/filebrowser.db"

# ---------------------------------------------------------------------------- #
#                          Function Definitions                                #
# ---------------------------------------------------------------------------- #

# Setup SSH with optional key or random password
setup_ssh() {
    mkdir -p ~/.ssh

    # Generate host keys if they don't exist
    for type in rsa dsa ecdsa ed25519; do
        if [ ! -f "/etc/ssh/ssh_host_${type}_key" ]; then
            ssh-keygen -t ${type} -f "/etc/ssh/ssh_host_${type}_key" -q -N ''
            echo "${type^^} key fingerprint:"
            ssh-keygen -lf "/etc/ssh/ssh_host_${type}_key.pub"
        fi
    done

    # If PUBLIC_KEY is provided, use it
    if [[ $PUBLIC_KEY ]]; then
        echo "$PUBLIC_KEY" >>~/.ssh/authorized_keys
        chmod 700 -R ~/.ssh
    else
        # Generate random password if no public key
        RANDOM_PASS=$(openssl rand -base64 12)
        echo "root:${RANDOM_PASS}" | chpasswd
        echo "Generated random SSH password for root: ${RANDOM_PASS}"
    fi

    # Configure SSH to preserve environment variables
    echo "PermitUserEnvironment yes" >>/etc/ssh/sshd_config

    # Start SSH service
    /usr/sbin/sshd
}

# Export environment variables
export_env_vars() {
    echo "Exporting environment variables..."

    ENV_FILE="/etc/environment"
    PAM_ENV_FILE="/etc/security/pam_env.conf"
    SSH_ENV_DIR="/root/.ssh/environment"

    cp "$ENV_FILE" "${ENV_FILE}.bak" 2>/dev/null || true
    cp "$PAM_ENV_FILE" "${PAM_ENV_FILE}.bak" 2>/dev/null || true

    true >"$ENV_FILE"
    true >"$PAM_ENV_FILE"
    mkdir -p /root/.ssh
    true >"$SSH_ENV_DIR"

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

# Start Jupyter Lab server
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
        --ServerApp.allow_origin=* &>/workspace/jupyter.log &
    echo "Jupyter Lab started"
}

# Setup workspace directories
setup_workspace() {
    echo "Setting up workspace directories..."

    # Create model directories (matching extra_model_paths.yaml)
    mkdir -p "$WORKSPACE_DIR/models/checkpoints"
    mkdir -p "$WORKSPACE_DIR/models/clip"
    mkdir -p "$WORKSPACE_DIR/models/clip_vision"
    mkdir -p "$WORKSPACE_DIR/models/configs"
    mkdir -p "$WORKSPACE_DIR/models/controlnet"
    mkdir -p "$WORKSPACE_DIR/models/diffusers"
    mkdir -p "$WORKSPACE_DIR/models/diffusion_models"
    mkdir -p "$WORKSPACE_DIR/models/embeddings"
    mkdir -p "$WORKSPACE_DIR/models/gligen"
    mkdir -p "$WORKSPACE_DIR/models/hypernetworks"
    mkdir -p "$WORKSPACE_DIR/models/loras"
    mkdir -p "$WORKSPACE_DIR/models/style_models"
    mkdir -p "$WORKSPACE_DIR/models/unet"
    mkdir -p "$WORKSPACE_DIR/models/upscale_models"
    mkdir -p "$WORKSPACE_DIR/models/vae"
    mkdir -p "$WORKSPACE_DIR/models/vae_approx"

    # Create other workspace directories
    mkdir -p "$WORKSPACE_DIR/output"
    mkdir -p "$WORKSPACE_DIR/input"
    mkdir -p "$WORKSPACE_DIR/user/default"
    mkdir -p "$WORKSPACE_DIR/custom_nodes"
}

# Symlink ComfyUI directories to workspace for persistence
setup_symlinks() {
    echo "Setting up symlinks to workspace..."

    # Symlink models directory
    if [ ! -L "$COMFYUI_DIR/models" ]; then
        rm -rf "$COMFYUI_DIR/models"
        ln -sf "$WORKSPACE_DIR/models" "$COMFYUI_DIR/models"
        echo "Symlinked models -> $WORKSPACE_DIR/models"
    fi

    # Symlink output directory
    if [ ! -L "$COMFYUI_DIR/output" ]; then
        rm -rf "$COMFYUI_DIR/output"
        ln -sf "$WORKSPACE_DIR/output" "$COMFYUI_DIR/output"
        echo "Symlinked output -> $WORKSPACE_DIR/output"
    fi

    # Symlink input directory
    if [ ! -L "$COMFYUI_DIR/input" ]; then
        rm -rf "$COMFYUI_DIR/input"
        ln -sf "$WORKSPACE_DIR/input" "$COMFYUI_DIR/input"
        echo "Symlinked input -> $WORKSPACE_DIR/input"
    fi

    # Symlink user directory
    if [ ! -L "$COMFYUI_DIR/user" ]; then
        rm -rf "$COMFYUI_DIR/user"
        ln -sf "$WORKSPACE_DIR/user" "$COMFYUI_DIR/user"
        echo "Symlinked user -> $WORKSPACE_DIR/user"
    fi

    # Symlink custom_nodes directory
    if [ ! -L "$COMFYUI_DIR/custom_nodes" ]; then
        # Sync built-in nodes to workspace without overwriting existing files
        echo "Syncing built-in custom nodes to workspace..."
        rsync -a --ignore-existing "$COMFYUI_DIR/custom_nodes/" "$WORKSPACE_DIR/custom_nodes/"
        rm -rf "$COMFYUI_DIR/custom_nodes"
        ln -sf "$WORKSPACE_DIR/custom_nodes" "$COMFYUI_DIR/custom_nodes"
        echo "Symlinked custom_nodes -> $WORKSPACE_DIR/custom_nodes"
    fi
}

# Update ComfyUI
update_comfyui() {
    echo "Updating ComfyUI..."
    cd "$COMFYUI_DIR"
    git pull || echo "Warning: git pull failed, continuing with existing version"

    # Update built-in custom nodes
    for node_dir in "$COMFYUI_DIR/custom_nodes"/*/; do
        if [ -d "$node_dir/.git" ]; then
            node_name=$(basename "$node_dir")
            echo "Updating custom node: $node_name"
            cd "$node_dir"
            git pull || echo "Warning: Failed to update $node_name"
        fi
    done

    cd "$COMFYUI_DIR"
}

# ---------------------------------------------------------------------------- #
#                               Main Program                                   #
# ---------------------------------------------------------------------------- #

# Setup environment
setup_ssh
export_env_vars

# Initialize FileBrowser if not already done
if [ ! -f "$DB_FILE" ]; then
    echo "Initializing FileBrowser..."
    filebrowser -d "$DB_FILE" config init
    filebrowser -d "$DB_FILE" config set --address 0.0.0.0
    filebrowser -d "$DB_FILE" config set --port 8080
    filebrowser -d "$DB_FILE" config set --root /workspace
    filebrowser -d "$DB_FILE" config set --auth.method=json
    filebrowser -d "$DB_FILE" users add admin adminadmin12 --perm.admin
else
    echo "Using existing FileBrowser configuration..."
fi

# Start FileBrowser
echo "Starting FileBrowser on port 8080..."
nohup filebrowser -d "$DB_FILE" &>/workspace/filebrowser.log &

start_jupyter

# Setup workspace, symlinks, and update ComfyUI
setup_workspace
setup_symlinks
update_comfyui

# Create default comfyui_args.txt if it doesn't exist
ARGS_FILE="$WORKSPACE_DIR/comfyui_args.txt"
if [ ! -f "$ARGS_FILE" ]; then
    cat > "$ARGS_FILE" << 'EOF'
# ComfyUI launch arguments (one per line)
# Edit these to customize your ComfyUI instance
# Changes take effect on next container restart

# Network settings
--listen 0.0.0.0
--port 8188

# Performance optimizations for RTX 5090
--use-sage-attention
--highvram
--fast
EOF
    echo "Created ComfyUI arguments file at $ARGS_FILE"
fi

# Start ComfyUI with arguments from file
cd "$COMFYUI_DIR"

ARGS=$(grep -v '^#' "$ARGS_FILE" | grep -v '^$' | tr '\n' ' ')
echo "Starting ComfyUI with arguments: $ARGS"
python3 main.py $ARGS 2>&1 | tee /workspace/comfyui.log
