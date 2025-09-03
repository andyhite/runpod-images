# Claude Code Project Context

This project provides Docker images for running AI tools on RunPod cloud computing platform.

## Project Structure

- `versions.env` - Base image version environment variables for all tools
- `docker-bake.hcl` - Docker Buildx bake configuration for building images
- `Makefile` - Build automation with make targets and version management
- `invokeai/` - InvokeAI Docker image configuration
  - `Dockerfile` - Custom Docker image based on InvokeAI CUDA image
  - `invokeai.yaml` - InvokeAI configuration file
  - `start.sh` - Entry point script with SSH setup and environment configuration

## Key Commands

### Version Management

```bash
make versions                              # Show all base image versions
make version TOOL=invokeai                # Show specific tool's base image version
make set-version TOOL=invokeai VERSION=v6.6.0  # Set base image version to use
```

The project uses `versions.env` to define base image versions for each tool:

```env
INVOKEAI_VERSION=v6.5.1
```

This means the InvokeAI image will be built from `ghcr.io/invoke-ai/invokeai:v6.5.1-cuda`.

### Build Images

```bash
make build TOOL=invokeai                  # Build specific tool using current base image version
make push TOOL=invokeai                   # Build and push specific tool
make load TOOL=invokeai                   # Build and load specific tool into local Docker daemon

make build-all                            # Build all tools
make push-all                             # Build and push all tools  
make load-all                             # Build and load all tools into local Docker daemon
```

### Cleanup

```bash
make clean TOOL=invokeai                  # Remove images for specific tool
make clean-all                            # Remove all images for all tools
```

### Manual Docker Build

```bash
docker buildx bake                        # Build all tools (default group)
docker buildx bake invokeai               # Build specific tool directly
```

## Current Configuration

### InvokeAI

- **Base Image**: `ghcr.io/invoke-ai/invokeai:${VERSION}-cuda`
- **Target Platform**: `linux/amd64`
- **Image Tags**: `andyhite/invokeai:latest` and `andyhite/invokeai:${VERSION}`

## Features

- SSH access with public key authentication
- InvokeAI web interface on port 9090
- RunPod environment variable integration
- Persistent workspace directories for models, outputs, etc.

## Adding New Tools

1. Create a new directory for the tool (e.g., `newtool/`)
2. Add the tool's base image version to `versions.env`
3. Add the tool to the `TOOLS` list in `Makefile`
4. Create a new target in `docker-bake.hcl` and add it to the default group
