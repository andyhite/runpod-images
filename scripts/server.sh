#!/bin/bash

# Manages the dstack server
#
# Usage: ./server.sh [SUBCOMMAND]
#
# Subcommands:
#   start    Start dstack server in foreground (default)
#   stop     Stop background dstack server
#   status   Check dstack server status
#   logs     Show dstack server logs
#   ensure   Ensure server is running (start if needed)
#
# Examples:
#   ./server.sh start               # Start server in foreground
#   ./server.sh status              # Check if server is running
#   ./server.sh stop                # Stop background server

source "./scripts/utils/core.sh"
source "./scripts/utils/dstack.sh"

# Parse subcommand
SUBCOMMAND="${1:-start}" # Default to start

case "$SUBCOMMAND" in
start)
    echo "🚀 Starting dstack server in foreground..."
    echo "   Press Ctrl+C to stop the server"
    echo
    dstack server
    ;;

stop)
    echo "🛑 Stopping dstack server..."
    if [ -f ~/.dstack/server.pid ]; then
        kill "$(cat ~/.dstack/server.pid)" 2>/dev/null || true
        rm -f ~/.dstack/server.pid
        echo "✅ dstack server stopped"
    else
        echo "⚠️  No background dstack server found"
    fi
    ;;

status)
    echo "🔍 Checking dstack server status..."
    if check_server_running; then
        echo "✅ dstack server is running and responding"
        echo "   • API endpoint: http://localhost:3000"
    else
        echo "❌ dstack server is not responding"
        if [ -f ~/.dstack/server.pid ]; then
            echo "   • PID file exists: $(cat ~/.dstack/server.pid)"
            echo "   • Check logs: ./scripts/server.sh logs"
        else
            echo "   • No PID file found"
        fi
    fi
    ;;

logs)
    echo "📋 dstack Server Logs"
    echo "────────────────────"
    if [ -f ~/.dstack/server.log ]; then
        tail -20 ~/.dstack/server.log
    else
        echo "⚠️  No server logs found at ~/.dstack/server.log"
    fi
    ;;

ensure)
    echo "🔧 Ensuring dstack server is running..."
    ensure_server
    ;;

*)
    error "Unknown subcommand: $SUBCOMMAND. Available: start, stop, status, logs, ensure"
    ;;
esac
