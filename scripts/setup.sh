#!/bin/bash

# Configure environment and dstack for RunPod deployment
#
# Usage: ./setup.sh
#
# This script will:
#   1. Create .env file with RunPod API key, HF token, CivitAI token, and SSH key path
#   2. Setup dstack configuration for RunPod deployment
#   3. Install dstack if not already available
#
# Examples:
#   ./setup.sh                      # Run interactive setup

bold=$(tput bold)
normal=$(tput sgr0)

echo "🚀 ${bold}RunPod AI Services Setup${normal}"
echo "════════════════════════════════════════"
echo

echo "📝 ${bold}Environment Configuration${normal}"
echo "────────────────────────────────────────"

# Check for .env file and create or update it
if [ -f .env ]; then
    source .env 2>/dev/null || true
fi

# Collect missing inputs
if [ -z "$RUNPOD_API_KEY" ]; then
    echo "🔑 ${bold}RunPod API Key (required)${normal}"
    read -rp "  └─ Enter your RunPod API key: " runpod_key
else
    runpod_key="$RUNPOD_API_KEY"
    echo "🔑 ${bold}RunPod API Key:${normal} found existing"
fi

if [ -z "$HF_TOKEN" ]; then
    echo "🤗 ${bold}Hugging Face Token${normal} (optional)"
    read -rp "  └─ Enter token or press Enter to skip: " hf_token
else
    hf_token="$HF_TOKEN"
    echo "🤗 ${bold}Hugging Face Token:${normal} found existing"
fi

if [ -z "$CIVITAI_TOKEN" ]; then
    echo "🎨 ${bold}CivitAI Token${normal} (optional)"
    read -rp "  └─ Enter token or press Enter to skip: " civitai_token
else
    civitai_token="$CIVITAI_TOKEN"
    echo "🎨 ${bold}CivitAI Token:${normal} found existing"
fi

if [ -z "$PUBLIC_KEY_FILE" ]; then
    echo "🔐 ${bold}SSH Public Key${normal} (optional)"
    read -rp "  └─ Path to SSH key [~/.ssh/id_rsa.pub]: " ssh_key_path
    ssh_key_path=${ssh_key_path:-~/.ssh/id_rsa.pub}
else
    ssh_key_path="$PUBLIC_KEY_FILE"
fi

if [ -f "$(eval echo "$ssh_key_path")" ]; then
    echo "🔐 ${bold}SSH Key Status:${normal} found at $ssh_key_path"
else
    echo "🔐 ${bold}SSH Key Status:${normal} not found - SSH access disabled"
fi

# Generate .env file (create new or recreate existing)
{
    echo "# RunPod AI Services Environment Variables"
    echo "# Generated on $(date)"
    echo ""

    echo "# RunPod API Key (required for dstack deployment)"
    echo "# Get yours from: https://www.runpod.io/console/user/settings"
    echo "RUNPOD_API_KEY=$runpod_key"
    echo ""

    echo "# Hugging Face Token (optional, for accessing gated models)"
    echo "# Get yours from: https://huggingface.co/settings/tokens"
    if [ -n "$hf_token" ]; then
        echo "HF_TOKEN=$hf_token"
    else
        echo "# HF_TOKEN=hf_token_here  # Uncomment and add token if needed"
    fi
    echo ""

    echo "# CivitAI Token (optional, for downloading models from CivitAI)"
    echo "# Get yours from: https://civitai.com/user/account"
    if [ -n "$civitai_token" ]; then
        echo "CIVITAI_TOKEN=$civitai_token"
    else
        echo "# CIVITAI_TOKEN=civitai_token_here  # Uncomment and add token if needed"
    fi
    echo ""

    echo "# SSH Public Key file path for remote access (optional)"
    echo "# Leave blank to skip SSH access configuration"
    if [ -f "$(eval echo "$ssh_key_path")" ]; then
        echo "PUBLIC_KEY_FILE=$ssh_key_path"
    else
        echo "# PUBLIC_KEY_FILE=$ssh_key_path  # File not found, uncomment when available"
    fi
    echo ""

    echo "# Additional environment variables can be added here as needed"
} >.env

echo
echo "⚙️  ${bold}dstack Configuration${normal}"
echo "────────────────────────────────────────"

# Source the .env file to get RUNPOD_API_KEY
if [ -f .env ]; then
    source .env
fi

# Validate required environment variable
if [ -z "$RUNPOD_API_KEY" ]; then
    echo "❌ ${bold}Error:${normal} RUNPOD_API_KEY environment variable is required" >&2
    exit 1
fi

# Check if dstack is installed
if ! command -v dstack >/dev/null 2>&1; then
    echo "📦 dstack not found, installing..."

    if ! command -v uv >/dev/null 2>&1; then
        echo "❌ ${bold}Error:${normal} uv not found. Install uv first:"
        echo "   curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
        exit 1
    fi

    echo "  └─ Installing dstack with uv..."
    uv tool install 'dstack[all]' --upgrade
    echo "✅ ${bold}dstack installation complete${normal}"
else
    echo "✅ ${bold}dstack found:${normal} $(which dstack)"
fi

# Setup dstack configuration
mkdir -p ~/.dstack/server

# Only update config if it doesn't exist or the template is newer
if [ ! -f ~/.dstack/server/config.yml ] || [ templates/dstack-config.template.yml -nt ~/.dstack/server/config.yml ]; then
    sed "s/\${RUNPOD_API_KEY}/$RUNPOD_API_KEY/g" templates/dstack-config.template.yml >~/.dstack/server/config.yml
    echo "✅ ${bold}Configuration updated:${normal} ~/.dstack/server/config.yml"
else
    echo "✅ ${bold}Configuration up-to-date:${normal} ~/.dstack/server/config.yml"
fi

echo
echo "🎉 Setup complete! Next steps:"
echo "   • Start the dstack server: ${bold}make server${normal}"
echo "   • Deploy a service: ${bold}make deploy SERVICE=invokeai${normal}"
