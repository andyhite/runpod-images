# RunPod AI Services

Modular Docker images and deployment configurations for running AI services on RunPod cloud computing platform.

## Overview

This project provides a streamlined way to build, deploy, and manage AI services on RunPod. Each service is containerized with optimized configurations and can be deployed using either manual RunPod deployment or automated dstack orchestration. Currently supports InvokeAI with more services planned.

## Features

- 🚀 **Multiple Deployment Options** - Manual RunPod deployment or automated dstack orchestration
- 🏗️ **Modular Architecture** - Each service in its own directory with all configuration files
- 🔐 **SSH Access** - Secure shell access with public key authentication
- 💾 **Persistent Storage** - Configured workspace directories for models, outputs, and configurations
- 📦 **Version Management** - Centralized base image version tracking and updates
- 🛠️ **Build Automation** - Makefile with organized targets for common operations

## Quick Start

Choose your deployment method:

### Option 1: Automated Deployment (Recommended)

Use dstack for automated provisioning and management:

```bash
# Interactive setup (prompts for API key and SSH key path)
make setup

# Start dstack server (in background)
dstack server &

# Deploy services
make deploy SERVICE=invokeai    # Deploy specific service
make deploy                     # Deploy all services
```

See [docs/DSTACK.md](docs/DSTACK.md) for detailed deployment instructions.

### Option 2: Manual RunPod Deployment

Use pre-built images directly on RunPod:

1. **Container Image**: `andyhite/invokeai:latest`
2. **Environment**: Set `PUBLIC_KEY` for SSH access
3. **Ports**: Expose 9090 (web) and 22 (SSH)
4. **Access**: Web interface at `http://<pod-ip>:9090`

### Option 3: Build Locally

Build and customize images yourself:

```bash
# Show available services and versions
make versions

# Build specific service
make build SERVICE=invokeai

# Build and push to registry
make push SERVICE=invokeai

# Build all services
make build
```

## Available Services

| Service  | Description                    | Base Image                                   | Default Version | Docker Hub          |
| -------- | ------------------------------ | -------------------------------------------- | --------------- | ------------------- |
| invokeai | Stable Diffusion web interface | `ghcr.io/invoke-ai/invokeai:${VERSION}-cuda` | v6.5.1          | `andyhite/invokeai` |

More services will be added in future updates.

## Directory Structure

### Project Layout

```text
runpod/
├── services/                   # Service directories
│   └── invokeai/              # InvokeAI service
│       ├── Dockerfile         # Docker image definition
│       ├── invokeai.yaml      # Tool configuration
│       ├── start.sh           # Entry point script
│       └── dstack.yml         # dstack deployment config
├── docs/                      # Documentation
│   └── DSTACK.md             # Deployment documentation
├── example.env                # Environment variables template
├── versions.env               # Service version management
├── docker-bake.hcl           # Docker build configuration
├── templates/                 # Configuration templates
│   └── dstack-config.template.yml # dstack server configuration template
├── scripts/                  # All functionality as shell scripts (Makefile is thin wrapper)
│   ├── setup.sh              # Interactive project setup
│   ├── version.sh            # Version management with subcommands
│   ├── docker.sh             # Docker operations with subcommands
│   ├── deploy.sh             # Deployment management with subcommands
│   ├── server.sh             # Server management with subcommands
│   └── utils/                # Supporting utilities
│       ├── core.sh           # Standard error handling functions
│       ├── service.sh        # Service discovery, validation, and iteration
│       ├── dstack.sh         # dstack server management functions
│       └── env.sh            # Environment variable setup functions
└── Makefile                  # Build and deployment automation
```

### Container Layout (InvokeAI)

```text
/invokeai/           # InvokeAI installation
/workspace/          # Persistent workspace
├── models/          # AI models and cache
├── outputs/         # Generated images
├── databases/       # Application databases
├── configs/         # Legacy configurations
├── nodes/          # Custom nodes
└── style_presets/  # Style presets
```

## Development

### Prerequisites

- Docker with Buildx support
- Make (optional, for simplified commands)
- uv (modern Python package manager)

Install uv if you don't have it:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

**Note**: dstack will be automatically installed when needed

### Version Management

Base image versions are centrally managed in `versions.env`:

```env
INVOKEAI_VERSION=v6.5.1
```

Use the Makefile to update versions:

```bash
# Show current versions
make versions

# Update a service version
make set-version SERVICE=invokeai VERSION=v6.6.0

# Show specific service version
make version SERVICE=invokeai
```

### Adding New Services

1. Create a directory for the service under `services/` (e.g., `services/comfyui/`)
2. Add Dockerfile, configuration, startup scripts, and `dstack.yml`
3. Add the service's base image version to `versions.env`
4. Add target in `docker-bake.hcl` and add it to the default group

Example for adding a new service called "comfyui":

```bash
# 1. Create directory structure
mkdir -p services/comfyui
# Add services/comfyui/Dockerfile, services/comfyui/start.sh, services/comfyui/dstack.yml, etc.

# 2. Add to versions.env
echo 'COMFYUI_VERSION=v1.2.3' >> versions.env

# 3. Add target in docker-bake.hcl and to default group
# target "comfyui" { context = "./services/comfyui" ... }
# group "default" { targets = ["invokeai", "comfyui"] }

# 4. Use the new service
make set-version SERVICE=comfyui VERSION=v1.3.0
make build SERVICE=comfyui                     # Build just comfyui
make build                                     # Build all services including comfyui
```

### Build Process

The project uses Docker Buildx with HCL configuration (`docker-bake.hcl`) for advanced build features:

```bash
# View build configuration
docker buildx bake --print

# Build for multiple platforms (if configured)
docker buildx bake --platform linux/amd64,linux/arm64
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is open source and available under the MIT License.

## Support

For issues and questions:

- Create an issue in this repository
- Check the [InvokeAI documentation](https://invoke-ai.github.io/InvokeAI/)
- Visit the [RunPod documentation](https://docs.runpod.io/)
