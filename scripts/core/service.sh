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

start_service() {
    local service="$1"
    dstack apply -f "services/$service/$service.dstack.yml"
}

stop_service() {
    local service="$1"
    dstack stop "$service" 2>/dev/null || true
}

get_service_logs() {
    local service="$1"
    dstack logs "$service"
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
