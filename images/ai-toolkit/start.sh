#!/bin/bash
set -e

# Source shared helper functions
source /start-helpers.sh

AI_TOOLKIT_DIR="/workspace/ai-toolkit"

# ---------------------------------------------------------------------------- #
#                               Main Program                                     #
# ---------------------------------------------------------------------------- #

# Configure S3 sync (must be before export_env_vars so SYNC_* vars are exported)
SYNC_SERVICE=ai-toolkit
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

# Install/update dependencies (constrain PyTorch packages to prevent overwriting CUDA wheels)
echo "Installing/updating AI Toolkit dependencies..."
PIP_CONSTRAINT=/etc/pip-torch-constraints.txt pip install --no-cache-dir -r "$AI_TOOLKIT_DIR/requirements.txt" 2>&1 | tail -1

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
