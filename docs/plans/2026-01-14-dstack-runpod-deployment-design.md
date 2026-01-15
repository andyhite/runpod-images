# dstack RunPod Deployment Design

## Overview

Configuration and orchestration tooling to build and deploy ComfyUI to RunPod using dstack.

## Decisions

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Docker Registry | RunPod | Simplest path for RunPod deployments |
| GPU | RTX 5090 primary, L40S fallback | 5090 fastest for Wan 2.2 T2V, L40S fallback for availability |
| Storage | Existing `comfy-ui` volume, 200GB | Reuse existing volume in EU-NO-1 |
| Region | EU-NO-1 (configurable via env) | Must match volume location; best 5090 availability |
| Pricing | Spot with on-demand fallback | Balance cost savings and reliability |
| Orchestration | Makefile | Universal, no extra dependencies |
| Build | Docker Bake | Scalable multi-service builds |

## Project Structure

```
runpod/
├── .dstack/
│   └── profiles.yml              # RunPod backend authentication
├── services/
│   └── comfyui-5090/
│       ├── Dockerfile            # (existing)
│       ├── start.sh              # (existing)
│       ├── service.dstack.yml    # dstack task definition
│       └── volume.dstack.yml     # persistent volume reference
├── .env                          # (existing) environment variables
├── .env.example                  # Template for required env vars
├── docker-bake.hcl               # Docker buildx bake configuration
├── Makefile                      # Orchestration commands
└── README.md                     # Usage documentation
```

## Configuration Files

### `.dstack/profiles.yml`

```yaml
profiles:
  - name: runpod
    backends:
      - type: runpod
        creds:
          type: api_key
          api_key: ${RUNPOD_API_KEY}
```

### `services/comfyui-5090/volume.dstack.yml`

```yaml
type: volume
name: comfy-ui
backend: runpod
region: ${DSTACK_REGION}
size: 200GB
```

### `services/comfyui-5090/service.dstack.yml`

```yaml
type: task
name: comfyui-5090

image: ${RUNPOD_REGISTRY_IMAGE}

env:
  HF_TOKEN: ${HF_TOKEN}
  CIVITAI_TOKEN: ${CIVITAI_TOKEN}
  PUBLIC_KEY: ${PUBLIC_KEY}

resources:
  gpu:
    name: [RTX5090, L40S]
  disk: 50GB

spot_policy: auto

regions: [${DSTACK_REGION}]

volumes:
  - name: comfy-ui
    path: /workspace/runpod-slim

ports:
  - 8188  # ComfyUI
  - 22    # SSH
  - 8888  # Jupyter
  - 8080  # FileBrowser
```

### `docker-bake.hcl`

```hcl
variable "REGISTRY" {
  default = "runpod"
}

variable "IMAGE_TAG" {
  default = "latest"
}

group "default" {
  targets = ["comfyui-5090"]
}

target "comfyui-5090" {
  context    = "services/comfyui-5090"
  dockerfile = "Dockerfile"
  tags       = ["${REGISTRY}/comfyui-5090:${IMAGE_TAG}"]
  platforms  = ["linux/amd64"]
}
```

### `Makefile`

```makefile
# Load environment variables
include .env
export

# Configuration
SERVICE := comfyui-5090
REGISTRY := runpod
IMAGE_NAME := comfyui-5090
IMAGE_TAG := latest

# Derived
SERVICE_DIR := services/$(SERVICE)
FULL_IMAGE := $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)

# ============ Build Commands ============
.PHONY: build push

build:                          ## Build Docker image using bake
	docker buildx bake

push:                           ## Build and push to RunPod registry
	docker buildx bake --push

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
```

### `.env.example`

```bash
# RunPod API credentials
RUNPOD_API_KEY=your_runpod_api_key

# dstack server token (optional, for server mode)
DSTACK_TOKEN=your_dstack_token

# Model download tokens
HF_TOKEN=your_huggingface_token
CIVITAI_TOKEN=your_civitai_token

# SSH access
PUBLIC_KEY_FILE=/path/to/your/ssh/public_key.pub

# Region (must match volume location)
DSTACK_REGION=EU-NO-1
```

## Environment Variables

| Variable | Used By | Purpose |
|----------|---------|---------|
| `RUNPOD_API_KEY` | dstack profiles.yml | Authenticates dstack with RunPod backend |
| `DSTACK_TOKEN` | dstack (optional) | Server mode authentication |
| `HF_TOKEN` | Container runtime | Download models from Hugging Face |
| `CIVITAI_TOKEN` | Container runtime | Download models from CivitAI |
| `PUBLIC_KEY_FILE` | dstack task | Inject SSH public key for remote access |
| `DSTACK_REGION` | dstack configs | Region for volume and service (must match) |

## Usage

```bash
# Setup (one-time)
cp .env.example .env
# Edit .env with your credentials

# Deploy
make start    # Build, push, deploy

# Operations
make ssh      # Connect to instance
make logs     # View logs
make status   # Check status
make stop     # Shut down

# Maintenance
make clean    # Remove local images
make help     # Show all commands
```

## Constraints

- **Region lock**: Service region must match volume region. If you change `DSTACK_REGION`, ensure a volume exists in that region.
- **Volume name**: Using existing `comfy-ui` volume in EU-NO-1.
