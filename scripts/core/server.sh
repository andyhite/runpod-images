#!/bin/bash

get_server_logs() {
    echo -e "\033[1;34mRetrieving dstack server logs...\033[0m"
    if [ -f ~/.dstack/server.log ]; then
        tail -20 ~/.dstack/server.log
        return 0
    else
        echo -e "\033[1;31m✗ Failed to retrieve server logs\033[0m"
        return 1
    fi
}

start_server() {
    echo -e "\033[1;34mStarting dstack server...\033[0m"
    dstack server
}

stop_server() {
    echo -e "\033[1;34mStopping dstack server...\033[0m"
    if [ -f ~/.dstack/server.pid ]; then
        kill "$(cat ~/.dstack/server.pid)" 2>/dev/null || true
        rm -f ~/.dstack/server.pid
        echo -e "\033[1;32m✓ Successfully stopped dstack server\033[0m"
        return 0
    else
        echo -e "\033[1;33m⚠ Server was not running or failed to stop\033[0m"
        return 1
    fi
}

check_server_status() {
    curl -s http://localhost:3000/api/server/config >/dev/null 2>&1
}

get_server_status() {
    echo -e "\033[1;34mChecking dstack server status...\033[0m"
    if check_server_status; then
        echo -e "\033[1;32m✓ dstack server is running\033[0m"
        return 0
    else
        echo -e "\033[1;31m✗ dstack server is not running\033[0m"
        return 1
    fi
}

ensure_server() {
    if check_server_status; then
        return 0
    else
        echo -e "\033[1;34m🚀 Starting dstack server in background...\033[0m"
        nohup dstack server >~/.dstack/server.log 2>&1 &
        echo $! >~/.dstack/server.pid
        sleep 5
        if ! check_server_status; then
            echo -e "\033[1;31m✗ Failed to start dstack server\033[0m"
            return 1
        fi
        echo -e "\033[1;32m✓ dstack server started successfully\033[0m"
        extract_and_save_token
        return 0
    fi
}

extract_and_save_token() {
    sleep 2

    echo -e "\033[1;34m🔑 Extracting admin token...\033[0m"

    local token
    token=$(grep "The admin token is" ~/.dstack/server.log 2>/dev/null | tail -1 | awk '{print $6}')

    if [ -n "$token" ]; then
        echo -e "\033[1;32m✓ Token extracted successfully\033[0m"
        if [ -f .env ]; then
            if grep -q "^DSTACK_TOKEN=" .env; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    # macOS
                    sed -i .bak "s/^DSTACK_TOKEN=.*/DSTACK_TOKEN=\"$token\"/" .env && rm .env.bak
                else
                    # Linux
                    sed -i "s/^DSTACK_TOKEN=.*/DSTACK_TOKEN=\"$token\"/" .env
                fi
            else
                echo "DSTACK_TOKEN=\"$token\"" >>.env
            fi
        else
            echo "DSTACK_TOKEN=\"$token\"" >.env
        fi
        echo -e "\033[1;32m✓ Token saved to .env file\033[0m"
    else
        echo -e "\033[1;33m⚠ Could not extract token from server logs\033[0m"
    fi
}
