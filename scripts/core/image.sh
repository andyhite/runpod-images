#!/bin/bash

source "./scripts/core/service.sh"

build_image() {
    local service="$1"
    if [ -n "$service" ]; then
        docker buildx bake "$service"
    else
        docker buildx bake
    fi
}

push_image() {
    local service="$1"
    if [ -n "$service" ]; then
        docker buildx bake "$service" --push
    else
        docker buildx bake --push
    fi
}

load_image() {
    local service="$1"
    if [ -n "$service" ]; then
        docker buildx bake "$service" --load
    else
        docker buildx bake --load
    fi
}

clean_image() {
    local service="$1"
    local version
    version=$(get_image_version "$service")
    if [ -n "$version" ]; then
        docker rmi "andyhite/$service:latest" "andyhite/$service:$version" 2>/dev/null || true
    fi
}

get_image_version() {
    local service="$1"
    local service_var
    service_var=$(get_service_var "$service" "VERSION")
    grep "^$service_var=" versions.env | cut -d'=' -f2 | tr -d '"'
}

set_image_version() {
    local service="${1%%=*}"
    local version="${1#*=}"
    local service_var
    service_var=$(get_service_var "$service" "VERSION")

    if grep -q "^$service_var=" versions.env; then
        # Update existing version
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i .bak "s/^$service_var=.*/$service_var=\"$version\"/" versions.env && rm versions.env.bak
        else
            # Linux
            sed -i "s/^$service_var=.*/$service_var=\"$version\"/" versions.env
        fi
    else
        # Add new version
        echo "$service_var=\"$version\"" >>versions.env
    fi
}
