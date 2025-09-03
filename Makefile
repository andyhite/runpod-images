.DEFAULT_GOAL := help

#================================================================================
# Configuration
#================================================================================

# Available services (dynamically discovered from services/ directory)
SERVICES := $(notdir $(wildcard services/*))

# Source versions from versions.env file
include versions.env
export

# Source environment variables from .env file (if it exists)
-include .env
export

# Helper function to set PUBLIC_KEY from PUBLIC_KEY_FILE if needed
define setup_ssh_key
$(if $(PUBLIC_KEY_FILE), \
	$(if $(wildcard $(shell echo $(PUBLIC_KEY_FILE))), \
		$(eval PUBLIC_KEY := $(shell cat $(shell echo $(PUBLIC_KEY_FILE)) 2>/dev/null || echo "")), \
		$(eval PUBLIC_KEY := "") \
	), \
	$(eval PUBLIC_KEY ?= "") \
)
endef

# Helper function to build INVOKEAI_REMOTE_API_TOKENS JSON from HF_TOKEN and CIVITAI_TOKEN
define setup_remote_api_tokens
$(eval TEMP_JSON := [])
$(if $(HF_TOKEN),$(eval TEMP_JSON := $(shell echo '$(TEMP_JSON)' | jq '. += [{"url_regex": "huggingface.co", "token": "$(HF_TOKEN)"}]')))
$(if $(CIVITAI_TOKEN),$(eval TEMP_JSON := $(shell echo '$(TEMP_JSON)' | jq '. += [{"url_regex": "civitai.com", "token": "$(CIVITAI_TOKEN)"}]')))
$(eval INVOKEAI_REMOTE_API_TOKENS := $(shell echo '$(TEMP_JSON)' | jq -c .))
endef

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
	@echo "Available services: $(SERVICES)"
	@echo ""
	@echo "Usage examples:"
	@echo "  make setup                                        # Complete project setup"
	@echo "  make build SERVICE=invokeai                       # Build service locally"
	@echo "  make push SERVICE=invokeai                        # Build and push to registry"
	@echo "  make deploy SERVICE=invokeai                      # Deploy with dstack"
	@echo "  make set-version SERVICE=invokeai VERSION=v6.6.0  # Update image version"

#================================================================================
# Internal Validation
#================================================================================

validate-service: ## Internal: validate that SERVICE is supported (if provided)
	@if [ -n "$(SERVICE)" ]; then \
		service_var=$$(echo $(SERVICE) | tr a-z A-Z)_VERSION; \
		if ! grep -q "^$$service_var=" versions.env; then \
			echo "Error: Service '$(SERVICE)' not found in versions.env"; \
			echo "Available services: $(SERVICES)"; \
			exit 1; \
		fi; \
	fi

#================================================================================
# Version Management
#================================================================================

versions: ## Version: Show all image versions
	@echo "Current image versions:"
	@grep -E '^[A-Z_]+_VERSION=' versions.env | sed 's/_VERSION=/ = /' | sed 's/^/  /'

version: ## Version: Show image version for specific service (requires SERVICE=name)
	@if [ -z "$(SERVICE)" ]; then \
		echo "Error: SERVICE is required. Usage: make version SERVICE=<service_name>"; \
		echo "Available services: $(SERVICES)"; \
		exit 1; \
	fi
	@service_var=$$(echo $(SERVICE) | tr a-z A-Z)_VERSION; \
	version=$$(grep "^$$service_var=" versions.env | cut -d'=' -f2 2>/dev/null || echo "not found"); \
	echo "$(SERVICE): $$version"

set-version: ## Version: Set image version for a service (requires SERVICE=name VERSION=vX.Y.Z)
	@if [ -z "$(SERVICE)" ]; then \
		echo "Error: SERVICE is required. Usage: make set-version SERVICE=<service_name> VERSION=vX.Y.Z"; \
		echo "Available services: $(SERVICES)"; \
		exit 1; \
	fi
ifndef VERSION
	@echo "Error: VERSION is required. Usage: make set-version SERVICE=$(SERVICE) VERSION=vX.Y.Z"
	@exit 1
endif
	@service_var=$$(echo $(SERVICE) | tr a-z A-Z)_VERSION; \
	if grep -q "^$$service_var=" versions.env; then \
		sed -i.bak "s/^$$service_var=.*/$$service_var=$(VERSION)/" versions.env && rm versions.env.bak; \
	else \
		echo "$$service_var=$(VERSION)" >> versions.env; \
	fi; \
	echo "Set $(SERVICE) image version to $(VERSION)"

#================================================================================
# Docker Build Targets
#================================================================================

build: validate-service ## Build: Build Docker images locally (all services or SERVICE=name for specific)
	@if [ -n "$(SERVICE)" ]; then \
		docker buildx bake $(SERVICE); \
	else \
		docker buildx bake; \
	fi

push: validate-service ## Build: Build and push Docker images to registry (all services or SERVICE=name for specific)
	@if [ -n "$(SERVICE)" ]; then \
		docker buildx bake $(SERVICE) --push; \
	else \
		docker buildx bake --push; \
	fi

load: validate-service ## Build: Build and load images into local Docker daemon (all services or SERVICE=name for specific)
	@if [ -n "$(SERVICE)" ]; then \
		docker buildx bake $(SERVICE) --load; \
	else \
		docker buildx bake --load; \
	fi


#================================================================================
# Docker Cleanup
#================================================================================

clean: validate-service ## Build: Remove local Docker images (all services or SERVICE=name for specific)
	@if [ -n "$(SERVICE)" ]; then \
		service_var=$$(echo $(SERVICE) | tr a-z A-Z)_VERSION; \
		VERSION=$$(grep "^$$service_var=" versions.env | cut -d'=' -f2); \
		docker rmi andyhite/$(SERVICE):latest andyhite/$(SERVICE):$$VERSION 2>/dev/null || true; \
	else \
		for service in $(SERVICES); do \
			service_var=$$(echo $$service | tr a-z A-Z)_VERSION; \
			VERSION=$$(grep "^$$service_var=" versions.env | cut -d'=' -f2 2>/dev/null || echo ""); \
			if [ -n "$$VERSION" ]; then \
				docker rmi andyhite/$$service:latest andyhite/$$service:$$VERSION 2>/dev/null || true; \
			fi; \
		done; \
	fi


#================================================================================
# Setup
#================================================================================

setup: ## Setup: Complete project setup (installs dependencies and configures dstack)
	@echo "🚀 Running complete project setup..."
	@echo
	@if [ ! -f .env ]; then \
		echo "📝 Creating .env file with your configuration..."; \
		echo "# RunPod AI Services Environment Variables" > .env; \
		echo "# Generated by make setup on $$(date)" >> .env; \
		echo "" >> .env; \
		echo "# RunPod API Key (required for dstack deployment)" >> .env; \
		echo "# Get yours from: https://www.runpod.io/console/user/settings" >> .env; \
		read -p "Enter your RunPod API key: " runpod_key; \
		echo "RUNPOD_API_KEY=$$runpod_key" >> .env; \
		echo "" >> .env; \
		echo "# Hugging Face Token (optional, for accessing gated models)" >> .env; \
		echo "# Get yours from: https://huggingface.co/settings/tokens" >> .env; \
		read -p "Enter your Hugging Face token (optional, press Enter to skip): " hf_token; \
		if [ -n "$$hf_token" ]; then \
			echo "HF_TOKEN=$$hf_token" >> .env; \
		else \
			echo "# HF_TOKEN=hf_token_here  # Uncomment and add token if needed" >> .env; \
		fi; \
		echo "" >> .env; \
		echo "# CivitAI Token (optional, for downloading models from CivitAI)" >> .env; \
		echo "# Get yours from: https://civitai.com/user/account" >> .env; \
		read -p "Enter your CivitAI token (optional, press Enter to skip): " civitai_token; \
		if [ -n "$$civitai_token" ]; then \
			echo "CIVITAI_TOKEN=$$civitai_token" >> .env; \
		else \
			echo "# CIVITAI_TOKEN=civitai_token_here  # Uncomment and add token if needed" >> .env; \
		fi; \
		echo "" >> .env; \
		echo "# SSH Public Key file path for remote access (optional)" >> .env; \
		echo "# Leave blank to skip SSH access configuration" >> .env; \
		read -p "Enter path to your SSH public key file (default: ~/.ssh/id_rsa.pub): " ssh_key_path; \
		ssh_key_path=$${ssh_key_path:-~/.ssh/id_rsa.pub}; \
		if [ -f "$$(eval echo $$ssh_key_path)" ]; then \
			echo "PUBLIC_KEY_FILE=$$ssh_key_path" >> .env; \
			echo "✅ SSH key found at $$ssh_key_path"; \
		else \
			echo "# PUBLIC_KEY_FILE=$$ssh_key_path  # File not found, uncomment when available" >> .env; \
			echo "⚠️  SSH key not found at $$ssh_key_path - SSH access will be disabled"; \
		fi; \
		echo "" >> .env; \
		echo "# Additional environment variables can be added here as needed" >> .env; \
		echo "✅ .env file created successfully"; \
	else \
		echo "📄 .env file already exists, skipping configuration"; \
	fi
	@echo
	@$(MAKE) deploy-setup
	@echo "✅ Setup complete! You can now run: dstack server"

#================================================================================
# dstack Deployment
#================================================================================

install-deps: ## Internal: Install dstack and other Python dependencies with uv
	@echo "Installing dstack..."
	@if ! command -v uv >/dev/null 2>&1; then \
		echo "❌ Error: uv not found."; \
		echo "   Install uv first: curl -LsSf https://astral.sh/uv/install.sh | sh"; \
		echo "   Then restart your shell or run: source ~/.bashrc"; \
		exit 1; \
	fi
	@uv tool install 'dstack[all]' --upgrade
	@echo "✅ dstack installed"

check-dstack: ## Internal: Check if dstack is installed, install if missing
	@if ! command -v dstack >/dev/null 2>&1; then \
		echo "🔧 dstack not found, installing..."; \
		$(MAKE) install-deps; \
	fi

deploy-setup: check-dstack ## Internal: Setup dstack configuration for RunPod
	@if [ -z "$$RUNPOD_API_KEY" ]; then \
		echo "❌ Error: RUNPOD_API_KEY environment variable is required"; \
		echo "   Get your API key from: https://www.runpod.io/console/user/settings"; \
		exit 1; \
	fi; \
	mkdir -p ~/.dstack/server; \
	cp dstack-config.template.yml ~/.dstack/server/config.yml; \
	echo "✅ Configuration copied to ~/.dstack/server/config.yml"; \
	echo "✅ dstack setup complete"

deploy: check-dstack ## Deploy: Deploy services with dstack (all services or SERVICE=name for specific)
	@$(call setup_ssh_key)
	@$(call setup_remote_api_tokens)
	@if [ -n "$(SERVICE)" ]; then \
		echo "Deploying $(SERVICE) with dstack..."; \
		cd services/$(SERVICE) && dstack apply -f dstack.yml; \
	else \
		for service in $(SERVICES); do \
			echo "Deploying $$service..."; \
			cd services/$$service && dstack apply -f dstack.yml && cd ../..; \
		done; \
	fi

deploy-status: check-dstack ## Deploy: Show status of all dstack deployments
	@dstack ps

deploy-stop: check-dstack ## Deploy: Stop service deployments (all services or SERVICE=name for specific)
	@if [ -n "$(SERVICE)" ]; then \
		echo "Stopping $(SERVICE) deployment..."; \
		dstack stop $(SERVICE) 2>/dev/null || true; \
	else \
		for service in $(SERVICES); do \
			echo "Stopping $$service deployment..."; \
			dstack stop $$service 2>/dev/null || true; \
		done; \
	fi


deploy-logs: check-dstack ## Deploy: Show logs for service deployment (requires SERVICE=name)
	@if [ -z "$(SERVICE)" ]; then \
		echo "Error: SERVICE is required for logs. Usage: make deploy-logs SERVICE=<service_name>"; \
		echo "Available services: $(SERVICES)"; \
		exit 1; \
	fi
	@dstack logs $(SERVICE)

#================================================================================
# Make Configuration
#================================================================================

.PHONY: help versions version set-version validate-service build push load build-all push-all load-all clean clean-all setup install-deps check-dstack deploy-setup deploy deploy-all deploy-status deploy-stop deploy-stop-all deploy-logs
