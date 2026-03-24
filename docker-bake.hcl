# CUDA version pins
variable "CUDA_VERSION_MAJOR" {
  default = "13"
}
variable "CUDA_VERSION_MINOR" {
  default = "0"
}
variable "CUDA_VERSION" {
  default = "${CUDA_VERSION_MAJOR}.${CUDA_VERSION_MINOR}"
}
variable "CUDA_VERSION_DASH" {
  default = "${CUDA_VERSION_MAJOR}-${CUDA_VERSION_MINOR}"
}

# PyTorch version pins
variable "TORCHAUDIO_VERSION" {
  default = "2.10.0"
}
variable "TORCHVISION_VERSION" {
  default = "0.25.0"
}
variable "TORCH_INDEX_SUFFIX" {
  default = "cu130"
}
variable "TORCH_VERSION" {
  default = "2.10.0"
}

# Application version pins
variable "COMFYUI_VERSION" {
  default = "v0.17.2"
}
variable "FILEBROWSER_SHA256" {
  default = "8cd8c3baecb086028111b912f252a6e3169737fa764b5c510139e81f9da87799"
}
variable "FILEBROWSER_VERSION" {
  default = "v2.59.0"
}

# Custom node hashes (run scripts/fetch-hashes.sh to update)
variable "CIVICOMFY_SHA" {
  default = "555e984bbcb0"
}
variable "KJNODES_SHA" {
  default = "6dfca48e00a5"
}
variable "MANAGER_SHA" {
  default = "c94236a61457"
}
variable "RUNPODDIRECT_SHA" {
  default = "4de8269b5181"
}

# Docker image tag
variable "TAG" {
  default = "cuda${CUDA_VERSION}"
}

# Build groups
group "default" {
  targets = ["comfyui"]
}

# Build target
target "comfyui" {
  context    = "."
  dockerfile = "./services/comfyui/Dockerfile"
  platforms  = ["linux/amd64"]
  tags = [
    "andyhite/runpod-comfyui:${TAG}",
    "andyhite/runpod-comfyui:latest"
  ]
  args = {
    CIVICOMFY_SHA       = CIVICOMFY_SHA
    COMFYUI_VERSION     = COMFYUI_VERSION
    CUDA_VERSION_DASH   = CUDA_VERSION_DASH
    FILEBROWSER_SHA256  = FILEBROWSER_SHA256
    FILEBROWSER_VERSION = FILEBROWSER_VERSION
    KJNODES_SHA         = KJNODES_SHA
    MANAGER_SHA         = MANAGER_SHA
    RUNPODDIRECT_SHA    = RUNPODDIRECT_SHA
    TORCHAUDIO_VERSION  = TORCHAUDIO_VERSION
    TORCHVISION_VERSION = TORCHVISION_VERSION
    TORCH_INDEX_SUFFIX  = TORCH_INDEX_SUFFIX
    TORCH_VERSION       = TORCH_VERSION
  }
}
