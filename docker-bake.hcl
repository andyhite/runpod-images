variable "REGISTRY" {
  default = "runpod"
}

variable "IMAGE_TAG" {
  default = "latest"
}

group "default" {
  targets = ["comfyui-5090"]
}

target "comfyui-5090" {
  context    = "services/comfyui-5090"
  dockerfile = "Dockerfile"
  tags       = ["${REGISTRY}/comfyui-5090:${IMAGE_TAG}"]
  platforms  = ["linux/amd64"]
}
