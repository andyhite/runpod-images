# Load environment variables
include .env
export

# Configuration
SERVICE := comfyui
REGISTRY := andyhite
IMAGE_NAME := runpod-$(SERVICE)
IMAGE_TAG := latest

# Derived
FULL_IMAGE := $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)

# ============ Build Commands ============
.PHONY: build push push-fresh

build:                          ## Build Docker image using bake
	docker buildx bake $(SERVICE)

push:                           ## Build and push to registry
	docker buildx bake $(SERVICE) --push

push-fresh:                     ## Build and push with cache-busting timestamp tag
	BUILD_ID=$$(date +%Y%m%d%H%M%S) docker buildx bake $(SERVICE) --push

# ============ Utilities ============
.PHONY: clean help

clean:                          ## Remove local Docker images
	docker rmi $(FULL_IMAGE) || true

help:                           ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
