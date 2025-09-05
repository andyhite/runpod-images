# Claude Code Project Context

This project provides Docker images for running AI services on RunPod cloud computing platform with automated dstack deployment.

## Project Structure

- `versions.env` - Base image version environment variables for all services
- `docker-bake.hcl` - Docker Buildx bake configuration for building images
- `Makefile` - Build automation with consolidated targets and version management
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
- `scripts/` - Consolidated command-line tools with subcommand architecture
  - `setup.sh` - Interactive project setup with prompts for API keys and SSH configuration
  - `version.sh` - Version management with subcommands:
    - `show` (default) - Show all image versions
    - `get --service=NAME` - Show version for specific service  
    - `set --service=NAME --version=VER` - Set version for service
  - `docker.sh` - Docker operations with subcommands:
    - `build` (default) - Build Docker images
    - `push`, `load`, `clean` - Push to registry, load locally, remove images
    - `--service=NAME` option for specific service operations
  - `deploy.sh` - Deployment management with subcommands:
    - `(default)` - Deploy services
    - `status` - Show deployment status
    - `stop` - Stop deployments
    - `logs --service=NAME` - Show deployment logs
    - `--service=NAME` option for specific service operations
  - `server.sh` - dstack server management with subcommands:
    - `start` (default) - Start server in foreground
    - `stop`, `status`, `logs`, `ensure` - Server lifecycle operations
  - `utils/` - Helper utilities organized by functionality
    - `core.sh` - Standard error handling functions
    - `service.sh` - Service discovery, validation, and iteration functions
    - `dstack.sh` - dstack server management functions
    - `env.sh` - Environment variable setup functions

## Key Commands

All commands can be used either through Make targets or directly as scripts with subcommands.

### Direct Script Usage

```bash
# Version management
./scripts/version.sh show                                 # Show all versions
./scripts/version.sh get --service=invokeai               # Get specific version
./scripts/version.sh set --service=invokeai --version=v6.6.0  # Set version

# Docker operations
./scripts/docker.sh build                                 # Build all services
./scripts/docker.sh build --service=invokeai              # Build specific service
./scripts/docker.sh push --service=invokeai               # Push to registry

# Deployment
./scripts/deploy.sh                                       # Deploy all services
./scripts/deploy.sh --service=invokeai                    # Deploy specific service
./scripts/deploy.sh status                                # Show status
./scripts/deploy.sh logs --service=invokeai               # Show logs

# Server management
./scripts/server.sh start                                 # Start server
./scripts/server.sh status                                # Check status
./scripts/server.sh stop                                  # Stop server
```

### Version Management

```bash
make versions                                    # Show all base image versions
make version SERVICE=invokeai                   # Show specific service's base image version
make set-version SERVICE=invokeai VERSION=v6.6.0  # Set base image version to use
```

The project uses `versions.env` to define base image versions for each service:

```env
INVOKEAI_VERSION=v6.5.1
```

This means the InvokeAI image will be built from `ghcr.io/invoke-ai/invokeai:v6.5.1-cuda`.

### Build Images

```bash
make build SERVICE=invokeai               # Build specific service using current base image version
make push SERVICE=invokeai                # Build and push specific service
make load SERVICE=invokeai                # Build and load specific service into local Docker daemon

make build                                # Build all services (default behavior)
make push                                 # Build and push all services  
make load                                 # Build and load all services into local Docker daemon
```

### Cleanup

```bash
make clean SERVICE=invokeai               # Remove images for specific service
make clean                                # Remove all images for all services
```

### Deployment

```bash
make setup                                # Interactive setup (API keys, SSH keys, etc.)
dstack server                             # Start dstack server
make deploy SERVICE=invokeai              # Deploy specific service
make deploy                               # Deploy all services
make deploy-status                        # Show deployment status
make deploy-stop SERVICE=invokeai         # Stop specific service
make deploy-stop                          # Stop all services
make deploy-logs SERVICE=invokeai         # Show logs for specific service
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

**Note**: Services are automatically discovered from the `services/` directory, so no manual list updates are needed in the Makefile.
