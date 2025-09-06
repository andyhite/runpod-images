#!/bin/bash

source "./scripts/core/service.sh"

build_image() {
    local service="$1"
    if [ -n "$service" ]; then
        echo -e "\033[1;34mBuilding Docker image for $service...\033[0m"
        if docker buildx bake "$service"; then
            echo -e "\033[1;32m✓ Successfully built $service image\033[0m"
        else
            echo -e "\033[1;31m✗ Failed to build $service image\033[0m"
            return 1
        fi
    else
        echo -e "\033[1;34mBuilding all Docker images...\033[0m"
        if docker buildx bake; then
            echo -e "\033[1;32m✓ Successfully built all images\033[0m"
        else
            echo -e "\033[1;31m✗ Failed to build images\033[0m"
            return 1
        fi
    fi
}

push_image() {
    local service="$1"
    if [ -n "$service" ]; then
        echo -e "\033[1;34mBuilding and pushing Docker image for $service...\033[0m"
        if docker buildx bake "$service" --push; then
            echo -e "\033[1;32m✓ Successfully built and pushed $service image\033[0m"
        else
            echo -e "\033[1;31m✗ Failed to build and push $service image\033[0m"
            return 1
        fi
    else
        echo -e "\033[1;34mBuilding and pushing all Docker images...\033[0m"
        if docker buildx bake --push; then
            echo -e "\033[1;32m✓ Successfully built and pushed all images\033[0m"
        else
            echo -e "\033[1;31m✗ Failed to build and push images\033[0m"
            return 1
        fi
    fi
}

load_image() {
    local service="$1"
    if [ -n "$service" ]; then
        echo -e "\033[1;34mBuilding and loading Docker image for $service...\033[0m"
        if docker buildx bake "$service" --load; then
            echo -e "\033[1;32m✓ Successfully built and loaded $service image\033[0m"
        else
            echo -e "\033[1;31m✗ Failed to build and load $service image\033[0m"
            return 1
        fi
    else
        echo -e "\033[1;34mBuilding and loading all Docker images...\033[0m"
        if docker buildx bake --load; then
            echo -e "\033[1;32m✓ Successfully built and loaded all images\033[0m"
        else
            echo -e "\033[1;31m✗ Failed to build and load images\033[0m"
            return 1
        fi
    fi
}

clean_image() {
    local service="$1"
    local version
    version=$(get_image_version "$service")

    echo -e "\033[1;34mRemoving Docker images for $service...\033[0m"

    if [ -n "$version" ]; then
        if docker rmi "andyhite/$service:latest" "andyhite/$service:$version" 2>/dev/null; then
            echo -e "\033[1;32m✓ Successfully removed $service images\033[0m"
        else
            echo -e "\033[1;33m⚠ Some $service images may not have existed or failed to remove\033[0m"
        fi
    else
        echo -e "\033[1;31m✗ Failed to get version for $service\033[0m"
        return 1
    fi
}

get_image_version() {
    local service="$1"
    local service_var
    service_var=$(get_service_var "$service" "VERSION")
    local version
    version=$(grep "^$service_var=" versions.env | cut -d'=' -f2 | tr -d '"')

    if [ -n "$version" ]; then
        echo "$version"
        return 0
    else
        return 1
    fi
}

show_image_version() {
    local service="$1"
    local version
    version=$(get_image_version "$service")

    if [ $? -eq 0 ] && [ -n "$version" ]; then
        echo -e "\033[1;32m$service: $version\033[0m"
        return 0
    else
        echo -e "\033[1;31m✗ Failed to get version for $service\033[0m"
        return 1
    fi
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
            if sed -i .bak "s/^$service_var=.*/$service_var=\"$version\"/" versions.env && rm versions.env.bak; then
                echo -e "\033[1;32m✓ Successfully set $service version to $version\033[0m"
            else
                echo -e "\033[1;31m✗ Failed to set $service version\033[0m"
                return 1
            fi
        else
            # Linux
            if sed -i "s/^$service_var=.*/$service_var=\"$version\"/" versions.env; then
                echo -e "\033[1;32m✓ Successfully set $service version to $version\033[0m"
            else
                echo -e "\033[1;31m✗ Failed to set $service version\033[0m"
                return 1
            fi
        fi
    else
        # Add new version
        if echo "$service_var=\"$version\"" >>versions.env; then
            echo -e "\033[1;32m✓ Successfully set $service version to $version\033[0m"
        else
            echo -e "\033[1;31m✗ Failed to set $service version\033[0m"
            return 1
        fi
    fi
}
