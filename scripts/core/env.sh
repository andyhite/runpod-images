#!/bin/bash

generate_remote_api_tokens() {
    local tokens='[]'

    if [ -n "$HF_TOKEN" ]; then
        tokens=$(echo "$tokens" | jq --arg token "$HF_TOKEN" '. += [{"url_regex": "huggingface.co", "token": $token}]')
    fi

    if [ -n "$CIVITAI_TOKEN" ]; then
        tokens=$(echo "$tokens" | jq --arg token "$CIVITAI_TOKEN" '. += [{"url_regex": "civitai.com", "token": $token}]')
    fi

    echo "$tokens" | jq -c .
}

setup_ssh_key() {
    if [ -n "$PUBLIC_KEY_FILE" ]; then
        local expanded_path
        expanded_path=$(eval echo "$PUBLIC_KEY_FILE")
        if [ -f "$expanded_path" ]; then
            cat "$expanded_path" 2>/dev/null || echo ""
        fi
    else
        echo "${PUBLIC_KEY:-}"
    fi
}
