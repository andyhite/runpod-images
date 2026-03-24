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
variable "AI_TOOLKIT_VERSION" {
  default = "main"
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
  targets = ["comfyui", "ai-toolkit"]
}

# Shared base image target
target "base" {
  context    = "."
  dockerfile = "images/base/Dockerfile"
  platforms  = ["linux/amd64"]
  tags = [
    "andyhite/runpod-base:${TAG}",
    "andyhite/runpod-base:latest"
  ]
  args = {
    CUDA_VERSION_DASH   = CUDA_VERSION_DASH
    FILEBROWSER_SHA256  = FILEBROWSER_SHA256
    FILEBROWSER_VERSION = FILEBROWSER_VERSION
    TORCHAUDIO_VERSION  = TORCHAUDIO_VERSION
    TORCHVISION_VERSION = TORCHVISION_VERSION
    TORCH_INDEX_SUFFIX  = TORCH_INDEX_SUFFIX
    TORCH_VERSION       = TORCH_VERSION
  }
}

# ComfyUI service image
target "comfyui" {
  context    = "."
  contexts   = { base = "target:base" }
  dockerfile = "images/comfyui/Dockerfile"
  platforms  = ["linux/amd64"]
  tags = [
    "andyhite/runpod-comfyui:${TAG}",
    "andyhite/runpod-comfyui:latest"
  ]
  args = {
    CIVICOMFY_SHA       = CIVICOMFY_SHA
    COMFYUI_VERSION     = COMFYUI_VERSION
    KJNODES_SHA         = KJNODES_SHA
    MANAGER_SHA         = MANAGER_SHA
    RUNPODDIRECT_SHA    = RUNPODDIRECT_SHA
    TORCHAUDIO_VERSION  = TORCHAUDIO_VERSION
    TORCHVISION_VERSION = TORCHVISION_VERSION
    TORCH_VERSION       = TORCH_VERSION
  }
}

# AI Toolkit service image
target "ai-toolkit" {
  context    = "."
  contexts   = { base = "target:base" }
  dockerfile = "images/ai-toolkit/Dockerfile"
  platforms  = ["linux/amd64"]
  tags = [
    "andyhite/runpod-ai-toolkit:${TAG}",
    "andyhite/runpod-ai-toolkit:latest"
  ]
  args = {
    AI_TOOLKIT_VERSION = AI_TOOLKIT_VERSION
    CACHEBUST          = ""
  }
}
