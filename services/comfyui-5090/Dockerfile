# syntax=docker/dockerfile:1.4
# ============================================================================
# Stage 1: Base - Python, CUDA, PyTorch, SageAttention (slow, rarely changes)
# ============================================================================
# Build separately with: docker build --target base -t comfyui-base:latest .
# Then use as cache: docker build --build-arg BASE_IMAGE=comfyui-base:latest .
# ============================================================================
FROM ubuntu:22.04 AS base

ENV DEBIAN_FRONTEND=noninteractive

# Install minimal dependencies needed for building
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common \
    gpg-agent \
    git \
    wget \
    curl \
    ca-certificates \
    && add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.13 \
    python3.13-venv \
    python3.13-dev \
    build-essential \
    && wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    cuda-minimal-build-13-0 \
    libcublas-dev-13-0 \
    libcusolver-dev-13-0 \
    libcusparse-dev-13-0 \
    ninja-build \
    && rm cuda-keyring_1.1-1_all.deb

# Install pip for Python 3.13 and upgrade it
RUN --mount=type=cache,target=/root/.cache/pip \
    curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3.13 get-pip.py && \
    python3.13 -m pip install --upgrade pip && \
    rm get-pip.py

# Set CUDA environment for building
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64
ENV LIBRARY_PATH=/usr/local/cuda/lib64/stubs:${LIBRARY_PATH}

# Install PyTorch (stable CUDA 13.0 build for optimized FP8/FP4 quantization)
RUN --mount=type=cache,target=/root/.cache/pip \
    python3.13 -m pip install \
    torch==2.9.1 torchvision==0.24.1 torchaudio==2.9.1 --index-url https://download.pytorch.org/whl/cu130

# Install Triton and SageAttention for accelerated attention (Blackwell/RTX 5090 optimized)
# SageAttention 2.x and 3 (Blackwell) must be built from source
# --no-build-isolation required so build can access installed torch
# TORCH_CUDA_ARCH_LIST set for Blackwell (12.0) since no GPU available during build
# MAX_JOBS limits parallel compilation to avoid OOM in Docker
ENV TORCH_CUDA_ARCH_LIST="12.0"
ENV MAX_JOBS=1
RUN --mount=type=cache,target=/root/.cache/pip \
    python3.13 -m pip install triton wheel ninja packaging setuptools && \
    git clone https://github.com/thu-ml/SageAttention.git /tmp/SageAttention && \
    cd /tmp/SageAttention && \
    python3.13 -m pip install --no-build-isolation . && \
    cd /tmp/SageAttention/sageattention3_blackwell && \
    sed -i 's/cc_major, cc_minor = torch.cuda.get_device_capability()/cc_major, cc_minor = 12, 0  # Blackwell RTX 5090/' setup.py && \
    python3.13 -m pip install --no-build-isolation . && \
    rm -rf /tmp/SageAttention

# Install FlashAttention-3 (Blackwell-optimized attention for video generation)
# Provides alternative high-performance attention that some video models prefer
RUN --mount=type=cache,target=/root/.cache/pip \
    python3.13 -m pip install flash-attn --no-build-isolation

# ============================================================================
# Stage 2: Builder - ComfyUI core (changes more frequently)
# ============================================================================
FROM base AS builder

# Clone ComfyUI (shallow clone for smaller image, still allows updates)
WORKDIR /tmp/build
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git

# Install ComfyUI requirements
WORKDIR /tmp/build/ComfyUI
RUN --mount=type=cache,target=/root/.cache/pip \
    python3.13 -m pip install -r requirements.txt && \
    python3.13 -m pip install GitPython opencv-python

# Install ComfyUI-Manager for runtime custom node management
WORKDIR /tmp/build/ComfyUI/custom_nodes
RUN git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git && \
    if [ -f "ComfyUI-Manager/requirements.txt" ]; then \
    python3.13 -m pip install -r ComfyUI-Manager/requirements.txt; \
    fi

# Clean up builder stage to reduce size when copying (keep .git for updates)
RUN find /tmp/build -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true && \
    find /tmp/build -name "*.pyc" -delete 2>/dev/null || true && \
    find /tmp/build -name "*.pyo" -delete 2>/dev/null || true

# ============================================================================
# Stage 3: Runtime - Clean image with pre-installed packages
# ============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV IMAGEIO_FFMPEG_EXE=/usr/bin/ffmpeg

# CUDA optimizations for better memory allocation and large model support
ENV CUDA_MALLOC_ASYNC=1
# expandable_segments reduces fragmentation for large video tensors
# garbage_collection_threshold triggers cleanup at 80% VRAM usage
ENV PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True,garbage_collection_threshold:0.8

# Enable TF32 for faster matmul on Blackwell tensor cores
ENV TORCH_ALLOW_TF32_CUBLAS_OVERRIDE=1
ENV NVIDIA_TF32_OVERRIDE=1

# cuDNN optimizations
ENV CUDNN_V8_API_ENABLED=1
ENV TORCH_CUDNN_V8_API_ENABLED=1

# torch.compile cache for persistent compilation artifacts
ENV TORCHINDUCTOR_CACHE_DIR=/workspace/.torch_compile_cache
ENV TORCH_COMPILE_DEBUG=0

# Update and install runtime dependencies, CUDA 13.0, and common tools
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    software-properties-common \
    gpg-agent \
    && add-apt-repository ppa:deadsnakes/ppa && \
    add-apt-repository ppa:cybermax-dexter/ffmpeg-nvenc && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    python3.13 \
    python3.13-venv \
    python3.13-dev \
    build-essential \
    wget \
    gnupg \
    xz-utils \
    openssh-client \
    openssh-server \
    nano \
    curl \
    htop \
    tmux \
    ca-certificates \
    less \
    net-tools \
    iputils-ping \
    procps \
    rsync \
    golang \
    make \
    && wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends cuda-minimal-build-13-0 \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm cuda-keyring_1.1-1_all.deb

# Copy Python packages from builder stage (only dist-packages to reduce size)
COPY --from=builder /usr/local/lib/python3.13/dist-packages /usr/local/lib/python3.13/dist-packages
# Copy pip and other Python executables
COPY --from=builder /usr/local/bin/pip* /usr/local/bin/
COPY --from=builder /usr/local/bin/wheel /usr/local/bin/

# Copy ComfyUI with built-in custom nodes from builder stage
COPY --from=builder /tmp/build/ComfyUI /app/ComfyUI

# Remove uv to force ComfyUI-Manager to use pip (uv doesn't respect --system-site-packages properly)
RUN pip uninstall -y uv 2>/dev/null || true && \
    rm -f /usr/local/bin/uv /usr/local/bin/uvx

# Install FileBrowser
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

# Set CUDA environment variables
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64

# Install Jupyter with Python kernel
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install jupyter

# Final cleanup to reduce image size
RUN rm -rf /tmp/* && \
    find /usr/local/lib/python3.13 -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true && \
    find /usr/local/lib/python3.13 -name "*.pyc" -delete 2>/dev/null || true

# Configure SSH for root login
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    mkdir -p /run/sshd

# Create workspace directories for persistent data
RUN mkdir -p /workspace/models /workspace/output /workspace/input /workspace/user /workspace/custom_nodes
WORKDIR /app/ComfyUI

# Expose ports
EXPOSE 8188 22 8888 8080

# Copy and set up start script
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Set Python 3.13 as default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 1 && \
    update-alternatives --set python3 /usr/bin/python3.13

ENTRYPOINT ["/start.sh"]
