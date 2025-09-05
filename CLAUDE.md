# Claude Code Project Context

This project provides Docker images for running AI services on RunPod cloud computing platform with automated dstack deployment.

## Prerequisites

### Task Installation

This project uses [Task](https://taskfile.dev/) as the build automation tool. Install it using uv:

```bash
uv tool install go-task-bin
```

After installation, verify it's working:
```bash
task --version
```

## Project Structure

- `versions.env` - Base image version environment variables for all services
- `docker-bake.hcl` - Docker Buildx bake configuration for building images
- `Taskfile.yml` - Build automation with consolidated targets and version management using Task runner
- `services/` - Service directories (automatically discovered)
  - `invokeai/` - InvokeAI service configuration
    - `Dockerfile` - Custom Docker image based on InvokeAI CUDA image
    - `invokeai.yaml` - InvokeAI configuration file
    - `start.sh` - Entry point script with SSH setup and environment configuration
    - `dstack.yml` - dstack deployment configuration
- `docs/` - Documentation
  - `DSTACK.md` - Deployment guide
- `example.env` - Environment variables template
- `templates/` - Configuration templates
  - `dstack-config.template.yml` - dstack server configuration template
- `scripts/` - Command-line tools for project management
  - `command.sh` - Command dispatcher that delegates to core functions
  - `core/` - Core functionality modules
    - `env.sh` - Environment variable setup functions
    - `image.sh` - Docker image operations (build, push, load, clean, version management)
    - `server.sh` - dstack server management (start, stop, status, ensure, logs, token extraction)
    - `service.sh` - Service operations (discovery, validation, deployment, status, logs)

## Key Commands

All commands can be used either through Task targets or directly as scripts with subcommands.

### Direct Script Usage

```bash
# Version management
./scripts/command.sh get_image_version invokeai           # Get specific version
./scripts/command.sh set_image_version invokeai=v6.6.0    # Set version

# Docker operations  
./scripts/command.sh build_image invokeai                 # Build specific service
./scripts/command.sh push_image invokeai                  # Push to registry
./scripts/command.sh load_image invokeai                  # Load locally
./scripts/command.sh clean_image invokeai                 # Clean images

# Deployment
./scripts/command.sh start_service invokeai               # Deploy specific service
./scripts/command.sh get_service_status invokeai          # Show service status
./scripts/command.sh stop_service invokeai                # Stop specific deployment
./scripts/command.sh get_service_logs invokeai            # Show logs

# Server management
./scripts/command.sh start_server                         # Start server
./scripts/command.sh check_server_status                  # Check status
./scripts/command.sh stop_server                          # Stop server
./scripts/command.sh get_server_logs                      # Show logs
./scripts/command.sh ensure_server                        # Ensure running
```

### Version Management

```bash
task versions                                    # Show all base image versions
task invokeai:version                           # Show specific service's base image version
task invokeai:version:v6.6.0                   # Set base image version to use
```

The project uses `versions.env` to define base image versions for each service:

```env
INVOKEAI_VERSION=v6.5.1
```

This means the InvokeAI image will be built from `ghcr.io/invoke-ai/invokeai:v6.5.1-cuda`.

### Build Images

```bash
task invokeai:build                       # Build specific service using current base image version
task invokeai:push                        # Build and push specific service
task invokeai:load                        # Build and load specific service into local Docker daemon
```

### Cleanup

```bash
task invokeai:clean                       # Remove images for specific service
```

### Deployment

```bash
task setup                                # Interactive setup (API keys, SSH keys, etc.)
task server:start                         # Start dstack server
task invokeai:start                       # Deploy specific service
task invokeai:status                      # Show deployment status
task invokeai:stop                        # Stop specific service
task invokeai:logs                        # Show logs for specific service
```

### Manual Docker Build

```bash
docker buildx bake                        # Build all services (default group)
docker buildx bake invokeai               # Build specific service directly
```

## Current Configuration

### InvokeAI

- **Base Image**: `ghcr.io/invoke-ai/invokeai:${VERSION}-cuda`
- **Target Platform**: `linux/amd64`
- **Image Tags**: `andyhite/invokeai:latest` and `andyhite/invokeai:${VERSION}`

## Features

- **Interactive Setup**: Automated configuration with prompts for API keys and SSH keys
- **Consolidated Targets**: Single targets that work for all services or specific services
- **Dynamic Service Discovery**: Services are automatically discovered from `services/` directory
- **dstack Integration**: Automated deployment and management on RunPod
- **SSH Access**: Secure shell access with public key authentication
- **Web Interfaces**: AI services accessible via web (port 9090 for InvokeAI)
- **Persistent Storage**: Workspace directories for models, outputs, and configurations
- **Environment Integration**: Hugging Face tokens, CivitAI tokens, and other API integrations

## Adding New Services

1. Create a new directory under `services/` (e.g., `services/comfyui/`)
2. Add the service's base image version to `versions.env`
3. Create a new target in `docker-bake.hcl` and add it to the default group
4. Add `dstack.yml` configuration for deployment

**Note**: Services are automatically discovered from the `services/` directory, so no manual list updates are needed in the Taskfile.
