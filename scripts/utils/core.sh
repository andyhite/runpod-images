#!/bin/bash

# Core utilities
# Standard functions for error handling
#
# Usage: source ./scripts/utils/core.sh
#
# Functions provided:
#   error()                    - Standard error reporting with exit

# Standard error function
error() {
    echo "Error: $1" >&2
    exit 1
}
