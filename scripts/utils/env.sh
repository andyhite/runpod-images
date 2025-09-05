#!/bin/bash

# Environment setup utilities
# Functions for setting up environment variables and API tokens
#
# Usage: source ./scripts/utils/env.sh
#
# Functions provided:
#   setup_remote_api_tokens()  - Setup INVOKEAI_REMOTE_API_TOKENS from HF_TOKEN and CIVITAI_TOKEN
#   setup_ssh_key()            - Setup PUBLIC_KEY from PUBLIC_KEY_FILE

# Setup remote API tokens for InvokeAI
# Exports INVOKEAI_REMOTE_API_TOKENS from HF_TOKEN and CIVITAI_TOKEN environment variables
#
# Environment Variables:
#   HF_TOKEN      - Hugging Face token (optional)
#   CIVITAI_TOKEN - CivitAI token (optional)
#
# Exports:
#   INVOKEAI_REMOTE_API_TOKENS - JSON array of token configurations
setup_remote_api_tokens() {
    local tokens='[]'

    # Add Hugging Face token if available
    if [ -n "$HF_TOKEN" ]; then
        tokens=$(echo "$tokens" | jq --arg token "$HF_TOKEN" '. += [{"url_regex": "huggingface.co", "token": $token}]')
    fi

    # Add CivitAI token if available
    if [ -n "$CIVITAI_TOKEN" ]; then
        tokens=$(echo "$tokens" | jq --arg token "$CIVITAI_TOKEN" '. += [{"url_regex": "civitai.com", "token": $token}]')
    fi

    # Export the compact JSON
    INVOKEAI_REMOTE_API_TOKENS=$(echo "$tokens" | jq -c .)
    export INVOKEAI_REMOTE_API_TOKENS
}

# Setup SSH public key for remote access
# Exports PUBLIC_KEY from PUBLIC_KEY_FILE path if the file exists
#
# Environment Variables:
#   PUBLIC_KEY_FILE - Path to SSH public key file (optional)
#   PUBLIC_KEY      - SSH public key content (will be set if not provided)
#
# Exports:
#   PUBLIC_KEY - SSH public key content or empty string
setup_ssh_key() {
    if [ -n "$PUBLIC_KEY_FILE" ]; then
        local expanded_path
        expanded_path=$(eval echo "$PUBLIC_KEY_FILE")
        if [ -f "$expanded_path" ]; then
            PUBLIC_KEY=$(cat "$expanded_path" 2>/dev/null || echo "")
        else
            PUBLIC_KEY=""
        fi
    else
        PUBLIC_KEY="${PUBLIC_KEY:-}"
    fi

    export PUBLIC_KEY
}
