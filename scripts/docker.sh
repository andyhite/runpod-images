#!/bin/bash

# Build and manage Docker images for services
#
# Usage: ./docker.sh [SUBCOMMAND] [OPTIONS]
#
# Subcommands:
#   build    Build Docker images (default)
#   push     Build and push Docker images to registry
#   load     Build and load images into local Docker daemon
#   clean    Remove local Docker images
#
# Options:
#   --service=NAME Build/operate on specific service
#
# Examples:
#   ./docker.sh build               # Build all services
#   ./docker.sh push --service=invokeai  # Push specific service
#   ./docker.sh clean               # Clean all service images

source "./scripts/utils/core.sh"
source "./scripts/utils/service.sh"

# Parse arguments
SUBCOMMAND=""
SERVICE=""

while [[ $# -gt 0 ]]; do
    case $1 in
    build | push | load | clean)
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
    -*)
        error "Unknown option: $1"
        ;;
    *)
        if [ -z "$SUBCOMMAND" ]; then
            SUBCOMMAND="build" # Default subcommand
            # Check if this looks like a service name for backward compatibility
            if [ -d "services/$1" ]; then
                SERVICE="$1"
            fi
        fi
        shift
        ;;
    esac
done

# Default to build if no subcommand specified
[ -z "$SUBCOMMAND" ] && SUBCOMMAND="build"

# Validate service if provided
validate_service "$SERVICE"

# Execute subcommand
case "$SUBCOMMAND" in
build)
    if [ -n "$SERVICE" ]; then
        docker buildx bake "$SERVICE"
    else
        docker buildx bake
    fi
    ;;

push)
    if [ -n "$SERVICE" ]; then
        docker buildx bake "$SERVICE" --push
    else
        docker buildx bake --push
    fi
    ;;

load)
    if [ -n "$SERVICE" ]; then
        docker buildx bake "$SERVICE" --load
    else
        docker buildx bake --load
    fi
    ;;

clean)
    # Get version for a service (local function)
    get_service_version() {
        local service="$1"
        local service_var
        service_var=$(echo "$service" | tr '[:lower:]' '[:upper:]')_VERSION
        grep "^$service_var=" versions.env | cut -d'=' -f2 | tr -d '"'
    }

    # Function to clean images for a specific service
    clean_service_images() {
        local service="$1"
        local version
        version=$(get_service_version "$service")
        if [ -n "$version" ]; then
            docker rmi "andyhite/$service:latest" "andyhite/$service:$version" 2>/dev/null || true
        fi
    }

    for_each_service "$SERVICE" clean_service_images
    ;;

*)
    error "Unknown subcommand: $SUBCOMMAND. Available: build, push, load, clean"
    ;;
esac
