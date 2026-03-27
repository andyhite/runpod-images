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
variable "RCLONE_SHA256" {
  default = "70278c22b98c7d02aed01828b70053904dbce4c8a1a15d7781d836c6fdb036ea"
}
variable "RCLONE_VERSION" {
  default = "v1.73.3"
}
variable "OLLAMA_VERSION" {
  default = "v0.18.3"
}
variable "OLLAMA_SHA256" {
  default = "7b3fb22f2e01a17f03ec0ac88a0b070ee2d7481030e735337ac8c02b84b5e66e"
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
  targets = ["comfyui", "ai-toolkit", "ollama"]
}

# Universal foundation (SSH, FileBrowser, rclone — no CUDA/PyTorch)
target "base-core" {
  context    = "."
  dockerfile = "images/base-core/Dockerfile"
  platforms  = ["linux/amd64"]
  tags = [
    "andyhite/runpod-base-core:latest"
  ]
  args = {
    FILEBROWSER_SHA256  = FILEBROWSER_SHA256
    FILEBROWSER_VERSION = FILEBROWSER_VERSION
    RCLONE_SHA256       = RCLONE_SHA256
    RCLONE_VERSION      = RCLONE_VERSION
  }
}

# ML stack (CUDA, PyTorch, Jupyter) — inherits from base-core
target "base-cuda" {
  context    = "."
  contexts   = { base-core = "target:base-core" }
  dockerfile = "images/base-cuda/Dockerfile"
  platforms  = ["linux/amd64"]
  tags = [
    "andyhite/runpod-base-cuda:${TAG}",
    "andyhite/runpod-base-cuda:latest"
  ]
  args = {
    CUDA_VERSION_DASH   = CUDA_VERSION_DASH
    TORCHAUDIO_VERSION  = TORCHAUDIO_VERSION
    TORCHVISION_VERSION = TORCHVISION_VERSION
    TORCH_INDEX_SUFFIX  = TORCH_INDEX_SUFFIX
    TORCH_VERSION       = TORCH_VERSION
  }
}

# ComfyUI service image
target "comfyui" {
  context    = "."
  contexts   = { base = "target:base-cuda" }
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
  contexts   = { base = "target:base-cuda" }
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

# Ollama service image — inherits from base-core (no CUDA/PyTorch)
target "ollama" {
  context    = "."
  contexts   = { base-core = "target:base-core" }
  dockerfile = "images/ollama/Dockerfile"
  platforms  = ["linux/amd64"]
  tags = [
    "andyhite/runpod-ollama:${OLLAMA_VERSION}",
    "andyhite/runpod-ollama:latest"
  ]
  args = {
    OLLAMA_SHA256  = OLLAMA_SHA256
    OLLAMA_VERSION = OLLAMA_VERSION
  }
}
