#!/bin/bash
set -e

# Source shared helper functions
source /start-helpers.sh

COMFYUI_DIR="/workspace/comfyui"
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

# Setup ComfyUI if needed
if [ ! -d "$COMFYUI_DIR" ]; then
    echo "First time setup: Copying baked ComfyUI to workspace..."
    cp -r /opt/comfyui-baked "$COMFYUI_DIR"
    echo "ComfyUI copied to workspace"
else
    echo "Using existing ComfyUI installation"
fi

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
echo "    cd $COMFYUI_DIR && python main.py $FIXED_ARGS"
echo "============================================="

sleep infinity
