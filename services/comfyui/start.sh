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
