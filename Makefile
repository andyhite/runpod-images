.DEFAULT_GOAL := help

#================================================================================
# Configuration
#================================================================================

# Source versions from versions.env file
include versions.env
export

# Source environment variables from .env file (if it exists)
-include .env
export

#================================================================================
# Help and Information
#================================================================================

help: ## Help: Show this help message
	@echo "RunPod AI Services - Build and Deployment"
	@echo ""
	@echo "Setup targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## Setup: .*$$' Makefile | sort | awk 'BEGIN {FS = ":.*?## Setup: "}; {printf "  %-20s %s\n", $$1, $$2}'
	@echo ""
	@echo "Version targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## Version: .*$$' Makefile | sort | awk 'BEGIN {FS = ":.*?## Version: "}; {printf "  %-20s %s\n", $$1, $$2}'
	@echo ""
	@echo "Build targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## Build: .*$$' Makefile | sort | awk 'BEGIN {FS = ":.*?## Build: "}; {printf "  %-20s %s\n", $$1, $$2}'
	@echo ""
	@echo "Deploy targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## Deploy: .*$$' Makefile | sort | awk 'BEGIN {FS = ":.*?## Deploy: "}; {printf "  %-20s %s\n", $$1, $$2}'
	@echo ""
	@echo "Available services: $(shell find services/ -maxdepth 1 -type d -exec basename {} \; | grep -v '^services$$' | tr '\n' ' ')"
	@echo ""
	@echo "Usage examples:"
	@echo "  make setup                                        # Complete project setup"
	@echo "  make build SERVICE=invokeai                       # Build service locally"
	@echo "  make push SERVICE=invokeai                        # Build and push to registry"
	@echo "  make deploy SERVICE=invokeai                      # Deploy with dstack"
	@echo "  make set-version SERVICE=invokeai VERSION=v6.6.0  # Update image version"

#================================================================================
# Setup
#================================================================================

setup: ## Setup: Complete project setup (installs dependencies and configures dstack)
	@./scripts/setup.sh

#================================================================================
# Version Management
#================================================================================

versions: ## Version: Show all image versions
	@./scripts/version.sh show

version: ## Version: Show image version for specific service (requires SERVICE=name)
	@./scripts/version.sh get --service=$(SERVICE)

set-version: ## Version: Set image version for a service (requires SERVICE=name VERSION=vX.Y.Z)
	@./scripts/version.sh set --service=$(SERVICE) --version=$(VERSION)

#================================================================================
# Docker Build Targets
#================================================================================

build: ## Build: Build Docker images locally (all services or SERVICE=name for specific)
	@./scripts/docker.sh build $(if $(SERVICE),--service=$(SERVICE))

push: ## Build: Build and push Docker images to registry (all services or SERVICE=name for specific)
	@./scripts/docker.sh push $(if $(SERVICE),--service=$(SERVICE))

load: ## Build: Build and load images into local Docker daemon (all services or SERVICE=name for specific)
	@./scripts/docker.sh load $(if $(SERVICE),--service=$(SERVICE))

clean: ## Build: Remove local Docker images (all services or SERVICE=name for specific)
	@./scripts/docker.sh clean $(if $(SERVICE),--service=$(SERVICE))

#================================================================================
# Deployment
#================================================================================

deploy: ## Deploy: Deploy services with dstack (all services or SERVICE=name for specific)
	@./scripts/deploy.sh $(if $(SERVICE),--service=$(SERVICE))

deploy-status: ## Deploy: Show status of all dstack deployments
	@./scripts/deploy.sh status

deploy-stop: ## Deploy: Stop service deployments (all services or SERVICE=name for specific)
	@./scripts/deploy.sh stop $(if $(SERVICE),--service=$(SERVICE))

deploy-logs: ## Deploy: Show logs for service deployment (requires SERVICE=name)
	@./scripts/deploy.sh logs --service=$(SERVICE)

#================================================================================
# Server Management
#================================================================================

server: ## Deploy: Start dstack server in foreground
	@./scripts/server.sh start

server-stop: ## Deploy: Stop background dstack server
	@./scripts/server.sh stop

server-status: ## Deploy: Check dstack server status
	@./scripts/server.sh status

server-logs: ## Deploy: Show dstack server logs
	@./scripts/server.sh logs

#================================================================================
# Make Configuration
#================================================================================

.PHONY: help setup versions version set-version build push load clean deploy deploy-status deploy-stop deploy-logs server server-stop server-status server-logs
