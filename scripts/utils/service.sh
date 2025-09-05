#!/bin/bash

# Service utilities
# Functions for service discovery, validation, and iteration
#
# Usage: source ./scripts/utils/service.sh
#
# Functions provided:
#   get_available_services()   - List available services for error messages
#   validate_service()         - Validate service name against versions.env
#   for_each_service()         - Execute function for all or specific services

# Get list of available services (used in validation error messages)
get_available_services() {
    find services/ -maxdepth 1 -type d -exec basename {} \; | grep -v '^services$' | tr '\n' ' '
}

# Validate service exists (if service is provided)
validate_service() {
    local service="$1"
    if [ -n "$service" ]; then
        local service_var
        service_var=$(echo "$service" | tr '[:lower:]' '[:upper:]')_VERSION
        if ! grep -q "^$service_var=" versions.env; then
            echo "Error: Service '$service' not found in versions.env" >&2
            echo "Available services: $(get_available_services)" >&2
            exit 1
        fi
    fi
}

# Execute function for all services or specific service
for_each_service() {
    local service="$1"
    local func="$2"

    if [ -n "$service" ]; then
        "$func" "$service"
    else
        for service_dir in services/*/; do
            if [ -d "$service_dir" ]; then
                local current_service
                current_service=$(basename "$service_dir")
                "$func" "$current_service"
            fi
        done
    fi
}
