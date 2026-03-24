# Load environment variables
include .env
export

# Configuration
SERVICE := comfyui
REGISTRY := andyhite
IMAGE_NAME := comfyui
IMAGE_TAG := latest
DSTACK_PID_FILE := .dstack.pid

# Derived
SERVICE_DIR := services/$(SERVICE)
FULL_IMAGE := $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)

# ============ Server Commands ============
.PHONY: server-start server-stop server-status

server-start:                   ## Start dstack server (background)
	@if [ -f $(DSTACK_PID_FILE) ] && kill -0 $$(cat $(DSTACK_PID_FILE)) 2>/dev/null; then \
		echo "dstack server already running (PID $$(cat $(DSTACK_PID_FILE)))"; \
	else \
		echo "Starting dstack server..."; \
		dstack server --token $(DSTACK_TOKEN) > .dstack.log 2>&1 & \
		echo $$! > $(DSTACK_PID_FILE); \
		sleep 2; \
		echo "dstack server started (PID $$(cat $(DSTACK_PID_FILE)))"; \
	fi

server-stop:                    ## Stop dstack server
	@if [ -f $(DSTACK_PID_FILE) ]; then \
		kill $$(cat $(DSTACK_PID_FILE)) 2>/dev/null && echo "dstack server stopped" || echo "Server not running"; \
		rm -f $(DSTACK_PID_FILE); \
	else \
		echo "No PID file found"; \
	fi

server-status:                  ## Check dstack server status
	@if [ -f $(DSTACK_PID_FILE) ] && kill -0 $$(cat $(DSTACK_PID_FILE)) 2>/dev/null; then \
		echo "dstack server running (PID $$(cat $(DSTACK_PID_FILE)))"; \
	else \
		echo "dstack server not running"; \
	fi

# ============ Build Commands ============
.PHONY: build push push-fresh

build:                          ## Build Docker image using bake
	docker buildx bake

push:                           ## Build and push to RunPod registry
	docker buildx bake --push

push-fresh:                     ## Build and push with cache-busting timestamp tag
	BUILD_ID=$$(date +%Y%m%d%H%M%S) docker buildx bake --push

# ============ Volume Commands ============
.PHONY: volume-init volume-status

volume-init:                    ## Initialize/verify volume exists
	dstack apply -f $(SERVICE_DIR)/volume.dstack.yml

volume-status:                  ## Check volume status
	dstack volume list

# ============ Service Commands ============
.PHONY: start stop status logs

start: push volume-init         ## Deploy service (builds, pushes, starts)
	PUBLIC_KEY=$$(cat $(PUBLIC_KEY_FILE)) \
	RUNPOD_REGISTRY_IMAGE=$(FULL_IMAGE) \
	dstack apply -f $(SERVICE_DIR)/service.dstack.yml

stop:                           ## Stop running service
	dstack stop $(SERVICE)

status:                         ## Show service status
	dstack ps

logs:                           ## Tail service logs
	dstack logs $(SERVICE) -f

# ============ Validation Commands ============
.PHONY: offers plan

offers:                         ## Show available GPU offers and pricing
	dstack offer --gpu RTX5090 --region $(DSTACK_REGION) --max-offers 10

plan:                           ## Show deployment plan (dry-run, no confirm)
	@echo "Service deployment plan:"
	@PUBLIC_KEY=$$(cat $(PUBLIC_KEY_FILE)) \
	RUNPOD_REGISTRY_IMAGE=$(FULL_IMAGE) \
	dstack apply -f $(SERVICE_DIR)/service.dstack.yml

# ============ Utilities ============
.PHONY: ssh clean help

ssh:                            ## SSH into running service
	dstack ssh $(SERVICE)

clean:                          ## Remove local Docker images
	docker rmi $(FULL_IMAGE) || true

help:                           ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
