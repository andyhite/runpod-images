#!/bin/bash

# dstack server utilities
# Functions for managing dstack server lifecycle
#
# Usage: source ./scripts/utils/dstack.sh
#
# Functions provided:
#   check_server_running()     - Check if dstack server is responding
#   ensure_server()            - Start dstack server if not running

# Check if dstack server is running
check_server_running() {
    curl -s http://localhost:3000/api/server/config >/dev/null 2>&1
}

# Ensure dstack server is running (start if needed)
ensure_server() {
    if ! check_server_running; then
        echo "Starting dstack server in background..."
        nohup dstack server >~/.dstack/server.log 2>&1 &
        echo $! >~/.dstack/server.pid
        echo "Waiting for server to start..."
        sleep 5
        if ! check_server_running; then
            echo "Server failed to start. Check ~/.dstack/server.log for details" >&2
            exit 1
        fi
        echo "✅ dstack server started successfully"
    fi
}
