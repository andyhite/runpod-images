#!/bin/bash

# Manages service versions
#
# Usage: ./version.sh [SUBCOMMAND] [OPTIONS]
#
# Subcommands:
#   show     Show all image versions (default)
#   get      Show image version for specific service
#   set      Set image version for a service
#
# Options:
#   --service=NAME Service to operate on (required for get/set)
#   --version=VER  Version to set (required for set)
#
# Examples:
#   ./version.sh show                    # Show all versions
#   ./version.sh get --service=invokeai  # Get specific version
#   ./version.sh set --service=invokeai --version=v6.6.0  # Set version

source "./scripts/utils/core.sh"
source "./scripts/utils/service.sh"

# Parse arguments
SUBCOMMAND=""
SERVICE=""
VERSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
    show | get | set)
        SUBCOMMAND="$1"
        shift
        ;;
    --service=*)
        SERVICE="${1#*=}"
        shift
        ;;
    --service)
        SERVICE="$2"
        shift 2
        ;;
    --version=*)
        VERSION="${1#*=}"
        shift
        ;;
    --version)
        VERSION="$2"
        shift 2
        ;;
    -*)
        error "Unknown option: $1"
        ;;
    *)
        if [ -z "$SUBCOMMAND" ]; then
            SUBCOMMAND="show" # Default subcommand
        fi
        shift
        ;;
    esac
done

# Default to show if no subcommand specified
[ -z "$SUBCOMMAND" ] && SUBCOMMAND="show"

# Get version for a service
get_service_version() {
    local service="$1"
    local service_var
    service_var=$(echo "$service" | tr '[:lower:]' '[:upper:]')_VERSION
    grep "^$service_var=" versions.env | cut -d'=' -f2 | tr -d '"'
}

# Set version for a service
set_service_version() {
    local service="$1"
    local version="$2"
    local service_var
    service_var=$(echo "$service" | tr '[:lower:]' '[:upper:]')_VERSION

    if grep -q "^$service_var=" versions.env; then
        # Update existing version
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i .bak "s/^$service_var=.*/$service_var=\"$version\"/" versions.env && rm versions.env.bak
        else
            # Linux
            sed -i "s/^$service_var=.*/$service_var=\"$version\"/" versions.env
        fi
    else
        # Add new version
        echo "$service_var=\"$version\"" >>versions.env
    fi
}

# Execute subcommand
case "$SUBCOMMAND" in
show)
    echo "📦 Service Image Versions"
    echo "─────────────────────────"
    if grep -E '^[A-Z_]+_VERSION=' versions.env >/dev/null 2>&1; then
        while read -r line; do
            service=$(echo "$line" | cut -d'_' -f1 | tr '[:upper:]' '[:lower:]')
            version=$(echo "$line" | cut -d'=' -f2 | tr -d '"')
            echo "📦 $service: $version"
        done < <(grep -E '^[A-Z_]+_VERSION=' versions.env)
    else
        echo "⚠️  No service versions found"
    fi
    ;;

get)
    [ -z "$SERVICE" ] && error "Service is required for get. Use --service=SERVICE_NAME"
    validate_service "$SERVICE"
    version=$(get_service_version "$SERVICE")
    echo "📦 $SERVICE version: ${version:-❌ not found}"
    ;;

set)
    [ -z "$SERVICE" ] && error "Service is required for set. Use --service=SERVICE_NAME"
    [ -z "$VERSION" ] && error "Version is required for set. Use --version=VERSION"
    validate_service "$SERVICE"
    set_service_version "$SERVICE" "$VERSION"
    echo "✅ Updated $SERVICE to version $VERSION"
    ;;

*)
    error "Unknown subcommand: $SUBCOMMAND. Available: show, get, set"
    ;;
esac
