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

# Install/update dependencies
echo "Installing/updating AI Toolkit dependencies..."
pip install --no-cache-dir -r "$AI_TOOLKIT_DIR/requirements.txt" 2>&1 | tail -1

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
