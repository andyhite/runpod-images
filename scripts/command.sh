#!/bin/bash

source "./scripts/core/env.sh"
source "./scripts/core/image.sh"
source "./scripts/core/server.sh"
source "./scripts/core/service.sh"

FUNCTION="$1"
shift

if declare -F "$FUNCTION" >/dev/null; then
    "$FUNCTION" "$@"
else
    echo "Error: Function '$FUNCTION' not found"
    exit 1
fi
