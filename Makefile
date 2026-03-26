# Load environment variables
include .env
export

# Configuration — override SERVICE to target a single image (e.g., make build SERVICE=ai-toolkit)
SERVICE :=
REGISTRY := andyhite
IMAGE_TAG := latest

# ============ Build Commands ============
.PHONY: build push push-fresh build-all push-all push-fresh-all

build:                          ## Build image(s) — all by default, or set SERVICE=<name>
ifdef SERVICE
	docker buildx bake $(SERVICE)
else
	docker buildx bake
endif

push:                           ## Build and push image(s) to registry
ifdef SERVICE
	docker buildx bake $(SERVICE) --push
else
	docker buildx bake --push
endif

push-fresh:                     ## Build and push with cache-busting timestamp tag
ifdef SERVICE
	BUILD_ID=$$(date +%Y%m%d%H%M%S) docker buildx bake $(SERVICE) --push
else
	BUILD_ID=$$(date +%Y%m%d%H%M%S) docker buildx bake --push
endif

# ============ Local Tools ============
.PHONY: webui webui-stop

WEBUI_PORT := 6969

webui:                          ## Start Open WebUI connected to RunPod Ollama (requires POD_ID=<id>)
ifndef POD_ID
	$(error POD_ID is required, e.g., make webui POD_ID=9tyi30x1efy9f8)
endif
	docker run -d -p $(WEBUI_PORT):8080 \
		-e OLLAMA_BASE_URL=https://$(POD_ID)-11434.proxy.runpod.net \
		-v open-webui:/app/backend/data \
		--name open-webui \
		--restart always \
		ghcr.io/open-webui/open-webui:main
	@echo "Open WebUI running at http://localhost:$(WEBUI_PORT)"

webui-stop:                     ## Stop and remove Open WebUI container
	docker stop open-webui && docker rm open-webui

# ============ Utilities ============
.PHONY: clean help

clean:                          ## Remove local Docker images for a service (requires SERVICE=<name>)
ifndef SERVICE
	$(error SERVICE is required for clean, e.g., make clean SERVICE=comfyui)
endif
	docker rmi $(REGISTRY)/runpod-$(SERVICE):$(IMAGE_TAG) || true

help:                           ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
