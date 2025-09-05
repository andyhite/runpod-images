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
- 🛠️ **Build Automation** - Task runner with organized targets for common operations

## Quick Start

Choose your deployment method:

### Option 1: Automated Deployment (Recommended)

Use dstack for automated provisioning and management:

```bash
# Interactive setup (prompts for API key and SSH key path)
task setup

# Start dstack server (in background)
task server:start &

# Deploy services
task invokeai:start    # Deploy specific service
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
task versions

# Build specific service
task invokeai:build

# Build and push to registry
task invokeai:push
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
├── scripts/                  # All functionality as shell scripts (Task is thin wrapper)
│   ├── command.sh            # Command dispatcher for core functions
│   └── core/                 # Core functionality modules
│       ├── env.sh            # Environment variable setup functions
│       ├── image.sh          # Docker image operations
│       ├── server.sh         # dstack server management functions
│       └── service.sh        # Service discovery, validation, and deployment
└── Taskfile.yml              # Build and deployment automation
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
- Task runner for build automation
- uv (modern Python package manager)

Install Task using uv:

```bash
uv tool install go-task-bin
```

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

Use Task to manage versions:

```bash
# Show current versions
task versions

# Update a service version  
task invokeai:version:v6.6.0

# Show specific service version
task invokeai:version
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
task comfyui:version:v1.3.0                    # Set version
task comfyui:build                             # Build just comfyui
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
