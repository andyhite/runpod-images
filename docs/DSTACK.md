# dstack Deployment Guide

Complete guide for deploying AI services on RunPod using dstack for automated provisioning and management.

## Prerequisites

1. **RunPod Account**: Get your API key from [RunPod Console](https://www.runpod.io/console/user/settings)
2. **uv**: Modern Python package manager for fast installations
3. **SSH Key**: For remote access to containers

Install uv if you don't have it:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

## Setup Process

### Step 1: Interactive Setup

```bash
# Complete setup with interactive prompts
make setup
```

This will:

1. Prompt you for your RunPod API key
2. Ask for your Hugging Face token (optional, for accessing gated models)
3. Ask for your CivitAI token (optional, for downloading models from CivitAI)
4. Ask for your SSH public key file path (optional, defaults to `~/.ssh/id_rsa.pub`)
5. Verify the SSH key file exists and warn if not found
6. Generate the `.env` file automatically with proper formatting
7. Install dstack if missing
8. Configure dstack for RunPod deployment

**Example interactive session:**

```text
🚀 Running complete project setup...
📝 Creating .env file with your configuration...
Enter your RunPod API key: rp_12345abcdef...
Enter your Hugging Face token (optional, press Enter to skip): hf_abc123...
Enter your CivitAI token (optional, press Enter to skip): 
Enter path to your SSH public key file (default: ~/.ssh/id_rsa.pub):
✅ SSH key found at ~/.ssh/id_rsa.pub
✅ .env file created successfully
🔧 dstack not found, installing...
✅ dstack installed
✅ Setup complete! You can now run: dstack server
```

Alternatively, you can manually create the `.env` file:

```bash
# Manual approach
cp example.env .env
# Edit .env to add your settings
```

### Step 2: Start dstack Server

```bash
# Start server (runs in foreground)
dstack server

# Or run in background
dstack server &
```

## Deployment Operations

### Deploy Services

```bash
# Deploy specific service
make deploy SERVICE=invokeai

# Deploy all available services
make deploy

# Direct dstack command
cd services/invokeai && dstack apply -f dstack.yml
```

### Monitor and Manage

```bash
# Check deployment status
make deploy-status

# View logs
make deploy-logs SERVICE=invokeai

# Stop deployments
make deploy-stop SERVICE=invokeai
make deploy-stop
```

## Accessing Your Deployments

After successful deployment, dstack provides access URLs:

```text
Service is running at:
  - InvokeAI Web Interface: https://gateway.dstack.ai/proxy/12345/9090/
  - SSH Access: ssh root@gateway.dstack.ai -p 12345
```

### Web Interface

- Access the AI service through your browser
- All traffic is encrypted via HTTPS through dstack's secure gateway

### SSH Access

- Requires `PUBLIC_KEY_FILE` to be set to path of SSH public key file
- Useful for debugging, file management, and advanced configuration

## Configuration

### Resource Requirements

Default configuration (edit `services/*/dstack.yml` to customize):

- **GPU**: L40S with 48GB VRAM (optimized for image generation)
- **CPU**: 8+ cores
- **RAM**: 32GB+
- **Storage**: 100GB+ for models and outputs

### Environment Variables

| Variable                     | Purpose                                           | Required       |
| ---------------------------- | ------------------------------------------------- | -------------- |
| `RUNPOD_API_KEY`             | RunPod API authentication                         | Yes            |
| `HF_TOKEN`                   | Hugging Face API token for accessing gated models | Optional       |
| `CIVITAI_TOKEN`              | CivitAI API token for downloading models          | Optional       |
| `PUBLIC_KEY_FILE`            | Path to SSH public key file for remote access     | Optional       |
| `INVOKEAI_REMOTE_API_TOKENS` | JSON array of API tokens for external services    | Auto-generated |

### Persistent Storage

Volume mounts for data persistence:

- `/workspace` - Main workspace for models, outputs, and data
- `/workspace/models` - AI models storage (cached downloads persist across restarts)

## Troubleshooting

### Common Issues

| Problem               | Solution                                                                  |
| --------------------- | ------------------------------------------------------------------------- |
| API Key Error         | Verify `RUNPOD_API_KEY` is set and valid                                  |
| Resource Unavailable  | Try different GPU types or regions in `dstack.yml`                        |
| SSH Connection Failed | Ensure `PUBLIC_KEY_FILE` points to valid SSH public key during deployment |
| Deployment Stuck      | Check dstack server logs and RunPod console                               |

### Debugging Commands

```bash
# Check deployment status
dstack ps

# View live logs
dstack logs invokeai -f

# SSH access (if configured)
ssh root@<dstack-gateway-url> -p <port>
```

## Best Practices

### Cost Management

- Always stop deployments when not in use: `make deploy-stop`
- Monitor usage through RunPod console
- Use appropriate GPU types for your workload (edit `services/*/dstack.yml`)

### Security

- Keep `RUNPOD_API_KEY` secure and never commit to version control
- Use SSH keys for secure access instead of passwords
- All web traffic is automatically encrypted via HTTPS through dstack gateway

### Performance

- L40S GPUs are optimized for image generation workloads
- Persistent storage in `/workspace` speeds up model loading
- Consider multi-GPU setups for high-throughput scenarios
