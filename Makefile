.DEFAULT_GOAL := help

# Tools available for building
TOOLS := invokeai
TOOL ?= invokeai

# Source versions from .env file
include versions.env
export

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
	@echo ""
	@echo "Available tools: $(TOOLS)"
	@echo ""
	@echo "Usage examples:"
	@echo "  make build TOOL=invokeai                       # Build using base image version from versions.env"
	@echo "  make push TOOL=invokeai                        # Build and push using base image version"
	@echo "  make set-version TOOL=invokeai VERSION=v6.6.0  # Set base image version"
	@echo "  make versions                                  # Show all base image versions"

versions: ## Show all base image versions from manifest
	@echo "Current base image versions:"
	@grep -E '^[A-Z_]+_VERSION=' versions.env | sed 's/_VERSION=/ = /' | sed 's/^/  /'

version: ## Show base image version for specific tool (use TOOL=toolname)
	@tool_var=$$(echo $(TOOL) | tr a-z A-Z)_VERSION; \
	version=$$(grep "^$$tool_var=" versions.env | cut -d'=' -f2 2>/dev/null || echo "not found"); \
	echo "$(TOOL): $$version"

set-version: ## Set base image version for a tool (use TOOL=toolname VERSION=vX.Y.Z)
ifndef VERSION
	@echo "Error: VERSION is required. Usage: make set-version TOOL=invokeai VERSION=v6.6.0"
	@exit 1
endif
	@tool_var=$$(echo $(TOOL) | tr a-z A-Z)_VERSION; \
	if grep -q "^$$tool_var=" versions.env; then \
		sed -i.bak "s/^$$tool_var=.*/$$tool_var=$(VERSION)/" versions.env && rm versions.env.bak; \
	else \
		echo "$$tool_var=$(VERSION)" >> versions.env; \
	fi; \
	echo "Set $(TOOL) base image version to $(VERSION)"

validate-tool: ## Internal: validate that TOOL is supported
	@tool_var=$$(echo $(TOOL) | tr a-z A-Z)_VERSION; \
	if ! grep -q "^$$tool_var=" versions.env; then \
		echo "Error: Tool '$(TOOL)' not found in versions.env"; \
		echo "Available tools: $(TOOLS)"; \
		exit 1; \
	fi

build: validate-tool ## Build Docker images locally for specified tool
	docker buildx bake $(TOOL)

push: validate-tool ## Build and push Docker images to registry for specified tool
	docker buildx bake $(TOOL) --push

load: validate-tool ## Build and load images into local Docker daemon for specified tool
	docker buildx bake $(TOOL) --load

build-all: ## Build Docker images locally for all tools
	docker buildx bake

push-all: ## Build and push Docker images to registry for all tools
	docker buildx bake --push

load-all: ## Build and load images into local Docker daemon for all tools
	docker buildx bake --load

clean: validate-tool ## Remove local Docker images for specific tool
	@tool_var=$$(echo $(TOOL) | tr a-z A-Z)_VERSION; \
	VERSION=$$(grep "^$$tool_var=" versions.env | cut -d'=' -f2); \
	docker rmi andyhite/$(TOOL):latest andyhite/$(TOOL):$$VERSION 2>/dev/null || true

clean-all: ## Remove all local Docker images for all tools
	@for tool in $(TOOLS); do \
		tool_var=$$(echo $$tool | tr a-z A-Z)_VERSION; \
		VERSION=$$(grep "^$$tool_var=" versions.env | cut -d'=' -f2 2>/dev/null || echo ""); \
		if [ -n "$$VERSION" ]; then \
			docker rmi andyhite/$$tool:latest andyhite/$$tool:$$VERSION 2>/dev/null || true; \
		fi \
	done

.PHONY: help versions version set-version validate-tool build push load build-all push-all load-all clean clean-all
