#!/bin/bash

get_server_logs() {
    if [ -f ~/.dstack/server.log ]; then
        tail -20 ~/.dstack/server.log
    else
        return 1
    fi
}

start_server() {
    dstack server
}

stop_server() {
    if [ -f ~/.dstack/server.pid ]; then
        kill "$(cat ~/.dstack/server.pid)" 2>/dev/null || true
        rm -f ~/.dstack/server.pid
        return 0
    else
        return 1
    fi
}

check_server_status() {
    curl -s http://localhost:3000/api/server/config >/dev/null 2>&1
}

ensure_server() {
    if check_server_status; then
        return 0
    else
        nohup dstack server >~/.dstack/server.log 2>&1 &
        echo $! >~/.dstack/server.pid
        sleep 5
        if ! check_server_status; then
            return 1
        fi
        # Extract and save the token from logs
        extract_and_save_token
        return 0
    fi
}

extract_and_save_token() {
    # Wait a bit for logs to be written
    sleep 2
    
    # Extract token from server logs
    local token
    token=$(grep "The admin token is" ~/.dstack/server.log 2>/dev/null | tail -1 | awk '{print $6}')
    
    if [ -n "$token" ]; then
        # Update .env file with the token
        if [ -f .env ]; then
            # Remove existing DSTACK_TOKEN line if it exists
            if grep -q "^DSTACK_TOKEN=" .env; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    # macOS
                    sed -i .bak "s/^DSTACK_TOKEN=.*/DSTACK_TOKEN=\"$token\"/" .env && rm .env.bak
                else
                    # Linux
                    sed -i "s/^DSTACK_TOKEN=.*/DSTACK_TOKEN=\"$token\"/" .env
                fi
            else
                # Add new token line
                echo "DSTACK_TOKEN=\"$token\"" >> .env
            fi
        else
            # Create .env file with token
            echo "DSTACK_TOKEN=\"$token\"" > .env
        fi
    fi
}
