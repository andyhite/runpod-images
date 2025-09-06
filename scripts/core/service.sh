#!/bin/bash

get_service_var() {
    local service="$1"
    local var_name="$2"
    local service_prefix
    service_prefix=$(echo "$service" | tr '[:lower:]' '[:upper:]')
    echo "${service_prefix}_${var_name}"
}

get_available_services() {
    find services/ -maxdepth 1 -type d -exec basename {} \; | grep -v '^services$' | tr '\n' ' '
}

validate_service() {
    local service="$1"
    if [ -n "$service" ]; then
        local service_var
        service_var=$(get_service_var "$service" "VERSION")
        if ! grep -q "^$service_var=" versions.env; then
            return 1
        else
            return 0
        fi
    else
        return 1
    fi
}

deploy_service_volume() {
    local service="$1"
    local volume_config="services/$service/volume.dstack.yml"

    if [ -f "$volume_config" ]; then
        echo -e "\033[1;34m📦 Found volume configuration for $service, deploying volume...\033[0m"
        if dstack apply -f "$volume_config" -y; then
            echo -e "\033[1;32m✅ Volume deployed successfully\033[0m"
            return 0
        else
            echo -e "\033[1;31m❌ Failed to deploy volume\033[0m"
            return 1
        fi
    else
        echo -e "\033[1;36m📦 No volume configuration found for $service\033[0m"
        return 0
    fi
}

start_service() {
    local service="$1"

    # Deploy the service
    echo -e "\033[1;36m🚀 Deploying $service service...\033[0m"
    if dstack apply -f "services/$service/$service.dstack.yml"; then
        echo -e "\033[1;32m✓ Successfully deployed $service service\033[0m"
        return 0
    else
        echo -e "\033[1;31m✗ Failed to deploy $service service\033[0m"
        return 1
    fi
}

stop_service() {
    local service="$1"

    echo -e "\033[1;34mStopping $service service deployment...\033[0m"
    if dstack stop "$service" 2>/dev/null; then
        echo -e "\033[1;32m✓ Successfully stopped $service service\033[0m"
        return 0
    else
        echo -e "\033[1;31m✗ Failed to stop $service service\033[0m"
        return 1
    fi
}

get_service_logs() {
    local service="$1"

    echo -e "\033[1;34mRetrieving logs for $service service...\033[0m"
    if dstack logs "$service"; then
        return 0
    else
        echo -e "\033[1;31m✗ Failed to retrieve logs for $service service\033[0m"
        return 1
    fi
}

get_service_status() {
    local service="$1"
    # Load token from .env file
    local token=""
    if [ -f .env ] && grep -q "^DSTACK_TOKEN=" .env; then
        token=$(grep "^DSTACK_TOKEN=" .env | cut -d'=' -f2 | tr -d '"')
    fi

    # Try API first if we have a token
    if [ -n "$token" ]; then
        local api_response
        if api_response=$(curl -s -X POST \
            "http://localhost:3000/api/project/main/runs/get" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -d "{\"run_name\": \"$service\"}" 2>/dev/null) && [ -n "$api_response" ]; then
            # Check if response contains an error
            local error
            error=$(echo "$api_response" | jq -r '.error // empty' 2>/dev/null)
            if [ -z "$error" ]; then
                # Extract status from API response
                local status
                status=$(echo "$api_response" | jq -r '.status // empty' 2>/dev/null)

                if [ -n "$status" ] && [ "$status" != "null" ] && [ "$status" != "" ]; then
                    echo "$status"
                    return 0
                fi
            fi
        fi
    fi

    # Fallback to CLI parsing if API fails or no token
    local status_line
    status_line=$(dstack ps | grep "$service" 2>/dev/null)
    if [ -n "$status_line" ]; then
        echo "$status_line" | awk '{print $3}'
    else
        echo "not_deployed"
        return 1
    fi
}

show_service_status() {
    local service="$1"
    local status
    status=$(get_service_status "$service" || echo "not_deployed")

    case "$status" in
    "running" | "Running" | "RUNNING")
        echo -e "\033[1;32m✓ $service: Running\033[0m"
        ;;
    "pending" | "Pending" | "PENDING")
        echo -e "\033[1;33m⏳ $service: Pending\033[0m"
        ;;
    "failed" | "Failed" | "FAILED" | "error" | "Error" | "ERROR")
        echo -e "\033[1;31m✗ $service: Failed\033[0m"
        ;;
    "aborted" | "Aborted" | "ABORTED")
        echo -e "\033[1;31m⏹ $service: Aborted\033[0m"
        ;;
    "terminated" | "Terminated" | "TERMINATED")
        echo -e "\033[1;31m⏹ $service: Terminated\033[0m"
        ;;
    "done" | "Done" | "DONE")
        echo -e "\033[1;32m✅ $service: Done\033[0m"
        ;;
    "stopped" | "Stopped" | "STOPPED")
        echo -e "\033[1;37m⏸ $service: Stopped\033[0m"
        ;;
    "exited" | "Exited" | "EXITED")
        echo -e "\033[1;31m⏹ $service: Exited\033[0m"
        ;;
    "not_deployed")
        echo -e "\033[1;33m⚠ $service: Not deployed\033[0m"
        ;;
    "api_unavailable")
        echo -e "\033[1;31m🔌 $service: API unavailable (server not running?)\033[0m"
        ;;
    *)
        echo -e "\033[1;36m? $service: $status\033[0m"
        ;;
    esac
}
