#!/bin/bash

# Deploy and manage services with dstack
#
# Usage: ./deploy.sh [SUBCOMMAND] [OPTIONS]
#
# Subcommands:
#   (none)         Deploy services (default)
#   status         Show deployment status
#   stop           Stop deployments
#   logs           Show deployment logs
#
# Options:
#   --service=NAME Operate on specific service (where applicable)
#
# Examples:
#   ./deploy.sh                     # Deploy all services
#   ./deploy.sh --service=invokeai  # Deploy specific service
#   ./deploy.sh status              # Show deployment status
#   ./deploy.sh logs --service=invokeai  # Show logs for service

source "./scripts/utils/core.sh"
source "./scripts/utils/service.sh"
source "./scripts/utils/dstack.sh"
source "./scripts/utils/env.sh"

# Parse arguments
SUBCOMMAND=""
SERVICE=""

while [[ $# -gt 0 ]]; do
    case $1 in
    status | stop | logs)
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
            SUBCOMMAND="deploy" # Default subcommand
            # Check if this looks like a service name for backward compatibility
            if [ -d "services/$1" ]; then
                SERVICE="$1"
            fi
        fi
        shift
        ;;
    esac
done

# Default to deploy if no subcommand specified
[ -z "$SUBCOMMAND" ] && SUBCOMMAND="deploy"

# Validate service if provided
validate_service "$SERVICE"

# Execute subcommand
case "$SUBCOMMAND" in
deploy)
    # Setup environment
    setup_ssh_key
    setup_remote_api_tokens

    # Function to deploy a specific service
    deploy_service() {
        local service="$1"
        echo "Deploying $service with dstack..."
        cd "services/$service" && dstack apply -f "$service.dstack.yml" && cd ../..
    }

    ensure_server
    for_each_service "$SERVICE" deploy_service
    ;;

status)
    ensure_server
    dstack ps
    ;;

stop)
    # Function to stop a specific service
    stop_service() {
        local service="$1"
        echo "Stopping $service deployment..."
        dstack stop "$service" 2>/dev/null || true
    }

    ensure_server
    for_each_service "$SERVICE" stop_service
    ;;

logs)
    [ -z "$SERVICE" ] && error "Service is required for logs. Use --service=SERVICE_NAME"
    ensure_server
    dstack logs "$SERVICE"
    ;;

*)
    error "Unknown subcommand: $SUBCOMMAND"
    ;;
esac
