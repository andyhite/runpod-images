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

# Start Open WebUI
echo "Starting Open WebUI on port 6969..."
OLLAMA_BASE_URL=http://localhost:11434 nohup open-webui serve --port 6969 --host 0.0.0.0 &>/open-webui.log &

# Start periodic S3 sync
start_periodic_sync

# Wait for app — if it exits (crash), fall through to keep-alive
wait $APP_PID || true

echo "============================================="
echo "  Ollama crashed — check the logs above."
echo "  SSH, FileBrowser, and Open WebUI are still"
echo "  available. To restart: ollama serve"
echo "============================================="

# Block forever while allowing traps to fire
while true; do sleep 86400 & wait $!; done
