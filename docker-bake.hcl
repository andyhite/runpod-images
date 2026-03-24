variable "REGISTRY" {
  default = "andyhite"
}

variable "IMAGE_TAG" {
  default = "latest"
}

// Cache-busting build ID (pass BUILD_ID=xyz to override)
// Example: BUILD_ID=$(date +%Y%m%d%H%M%S) docker buildx bake --push
variable "BUILD_ID" {
  default = ""
}

group "default" {
  targets = ["comfyui-5090"]
}

target "comfyui-5090" {
  context    = "services/comfyui-5090"
  dockerfile = "Dockerfile"
  tags       = concat(
    ["${REGISTRY}/comfyui-5090:${IMAGE_TAG}"],
    BUILD_ID != "" ? ["${REGISTRY}/comfyui-5090:${BUILD_ID}"] : []
  )
  platforms  = ["linux/amd64"]
}
