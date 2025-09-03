# RunPod AI Tools Docker Images

Custom Docker images for running AI tools on RunPod cloud computing platform with SSH access and optimized configuration.

## Overview

This project provides Docker images based on official AI tool CUDA images, customized for RunPod deployment with additional features like SSH access and environment variable integration. Currently supports InvokeAI with more tools planned.

## Features

- 🚀 **AI Tool Web Interfaces** - Access tools through web browser (InvokeAI on port 9090)
- 🔐 **SSH Access** - Secure shell access with public key authentication
- 🌐 **RunPod Integration** - Optimized for RunPod cloud computing platform
- 💾 **Persistent Storage** - Configured workspace directories for models, outputs, and configurations
- 🐳 **Multi-platform Support** - Built for linux/amd64 architecture
- 📦 **Version Management** - Easy base image version tracking and updates

## Quick Start

### Using Pre-built Images

The images are available on Docker Hub:

- `andyhite/invokeai:latest` - Latest version
- `andyhite/invokeai:v6.5.1` - Specific version

### Building Locally

```bash
# Show available tools and base image versions
make versions

# Build single tool
make set-version TOOL=invokeai VERSION=v6.6.0  # Set base image version
make build TOOL=invokeai                       # Build specific tool
make push TOOL=invokeai                        # Build and push specific tool

# Build all tools
make build-all                                 # Build all tools locally
make push-all                                  # Build and push all tools
```

## Configuration

### Environment Variables

- `PUBLIC_KEY` - Your SSH public key for secure access
- `INVOKEAI_ROOT` - InvokeAI root directory (default: `/invokeai`)
- `HF_HOME` - Hugging Face cache directory
- `MPLCONFIGDIR` - Matplotlib configuration directory

### InvokeAI Configuration

The image includes a pre-configured `invokeai.yaml` with optimized settings for RunPod:

- Host: `127.0.0.1`
- Port: `9090`
- Workspace directories mapped to `/workspace/*`
- Patchmatch enabled for better performance

## Usage on RunPod

1. **Deploy Container**: Use `andyhite/invokeai:latest` as your container image
2. **Set Environment**: Add your `PUBLIC_KEY` environment variable
3. **Configure Ports**: Expose HTTP port 9090 for web interface and TCP port 22 for SSH
4. **Access**:
   - Web interface: `http://<pod-ip>:9090`
   - SSH: `ssh root@<pod-ip>` (if PUBLIC_KEY is set)

## Directory Structure

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

### Requirements

- Docker with Buildx support
- Make (optional, for simplified commands)

### Version Management

Base image versions are managed in `versions.env`:

```env
INVOKEAI_VERSION=v6.5.1
```

This specifies which upstream base image version to build from (e.g., `ghcr.io/invoke-ai/invokeai:v6.5.1-cuda`).

Use `make set-version TOOL=toolname VERSION=vX.Y.Z` to update base image versions.

### Available Tools

| Tool     | Description                    | Base Image                                   | Default Version |
| -------- | ------------------------------ | -------------------------------------------- | --------------- |
| invokeai | Stable Diffusion web interface | `ghcr.io/invoke-ai/invokeai:${VERSION}-cuda` | v6.5.1          |

More tools will be added in future updates.

### Adding New Tools

1. Create a directory for the tool (e.g., `newtool/`)
2. Add Dockerfile, configuration, and startup scripts
3. Add the tool's base image version to `versions.env`
4. Update `TOOLS` list in `Makefile`
5. Add target in `docker-bake.hcl` and add it to the default group

Example for adding a new tool called "comfyui":

```bash
# 1. Create directory structure
mkdir comfyui
# Add comfyui/Dockerfile, comfyui/start.sh, etc.

# 2. Add to versions.env
echo 'COMFYUI_VERSION=v1.2.3' >> versions.env

# 3. Update TOOLS in Makefile
# TOOLS := invokeai comfyui

# 4. Add target in docker-bake.hcl and to default group
# target "comfyui" { ... }
# group "default" { targets = ["invokeai", "comfyui"] }

# 5. Use the new tool
make set-version TOOL=comfyui VERSION=v1.3.0
make build TOOL=comfyui                        # Build just comfyui
make build-all                                 # Build all tools including comfyui
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
