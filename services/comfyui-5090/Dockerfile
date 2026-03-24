# syntax=docker/dockerfile:1.4
# ============================================================================
# ComfyUI for RTX 5090 (Blackwell) on RunPod
# Uses RunPod base image with CUDA 12.8.1 (current driver support)
# Note: CUDA 13.0 not yet available on RunPod infrastructure
# ============================================================================

# ============================================================================
# Stage 1: Builder - Install PyTorch, SageAttention, and ComfyUI
# ============================================================================
FROM runpod/base:1.0.3-cuda1281-ubuntu2404 AS builder

# CUDA environment for building extensions
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64
ENV LIBRARY_PATH=/usr/local/cuda/lib64/stubs:${LIBRARY_PATH}

# Install PyTorch nightly (CUDA 12.8 build - matches RunPod driver support)
# After install, create constraints file to PREVENT any subsequent pip install from changing these
# This is critical for ABI compatibility with SageAttention and other compiled extensions
RUN --mount=type=cache,target=/root/.cache/pip \
    python3 -m pip install --pre \
    torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128 && \
    echo "# Torch version constraints - DO NOT MODIFY" > /etc/torch-constraints.txt && \
    pip freeze | grep -E '^torch==' >> /etc/torch-constraints.txt && \
    pip freeze | grep -E '^torchvision==' >> /etc/torch-constraints.txt && \
    pip freeze | grep -E '^torchaudio==' >> /etc/torch-constraints.txt && \
    echo "Created torch constraints:" && cat /etc/torch-constraints.txt

# Set constraint file for all subsequent pip installs
# This absolutely prevents torch/torchvision/torchaudio from being changed
ENV PIP_CONSTRAINT=/etc/torch-constraints.txt

# Install Triton and SageAttention for accelerated attention (Blackwell/RTX 5090 optimized)
# SageAttention 2.x and 3 (Blackwell) must be built from source
# PyPI only has up to 1.0.6; 2.2.0+ is only available via git
# TORCH_CUDA_ARCH_LIST set for Blackwell (sm_120) since no GPU available during build
# MAX_JOBS limits parallel compilation to avoid OOM in Docker
ENV TORCH_CUDA_ARCH_LIST="12.0"
ENV MAX_JOBS=1
RUN --mount=type=cache,target=/root/.cache/pip \
    python3 -m pip install triton wheel ninja packaging setuptools && \
    git clone --depth 1 https://github.com/thu-ml/SageAttention.git /tmp/SageAttention && \
    cd /tmp/SageAttention && \
    python3 -m pip install --no-build-isolation . && \
    cd /tmp/SageAttention/sageattention3_blackwell && \
    sed -i 's/cc_major, cc_minor = torch.cuda.get_device_capability()/cc_major, cc_minor = 12, 0  # Blackwell RTX 5090/' setup.py && \
    python3 -m pip install --no-build-isolation . && \
    rm -rf /tmp/SageAttention

# Clone ComfyUI
WORKDIR /tmp/build
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git

# Install ComfyUI requirements
# CRITICAL: Filter out torch/torchvision/torchaudio to preserve nightly builds
WORKDIR /tmp/build/ComfyUI
RUN --mount=type=cache,target=/root/.cache/pip \
    grep -v -E '^torch(vision|audio)?([^a-zA-Z]|$)' requirements.txt > /tmp/requirements_filtered.txt && \
    python3 -m pip install -r /tmp/requirements_filtered.txt && \
    python3 -m pip install GitPython opencv-python onnx soundfile scipy && \
    python3 -m pip uninstall -y pynvml 2>/dev/null || true && \
    python3 -m pip install nvidia-ml-py && \
    rm /tmp/requirements_filtered.txt

# Install ComfyUI-Manager for runtime custom node management
WORKDIR /tmp/build/ComfyUI/custom_nodes
RUN git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git && \
    if [ -f "ComfyUI-Manager/requirements.txt" ]; then \
    grep -v -E '^torch(vision|audio)?([^a-zA-Z]|$)' ComfyUI-Manager/requirements.txt > /tmp/manager_reqs.txt && \
    python3 -m pip install -r /tmp/manager_reqs.txt && \
    rm /tmp/manager_reqs.txt; \
    fi

# Verify torch versions match constraints and clean up deprecated packages
RUN echo "Verifying torch versions match constraints..." && \
    pip freeze | grep -E '^torch(vision|audio)?==' && \
    echo "Constraints file:" && cat /etc/torch-constraints.txt && \
    python3 -c "import torch; import torchaudio; print(f'torch: {torch.__version__}, torchaudio: {torchaudio.__version__}')" && \
    pip uninstall -y pynvml 2>/dev/null || true

# Clean up builder stage
RUN find /tmp/build -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true && \
    find /tmp/build -name "*.pyc" -delete 2>/dev/null || true

# ============================================================================
# Stage 2: Runtime - Clean image based on RunPod base
# ============================================================================
FROM runpod/base:1.0.3-cuda1281-ubuntu2404

ENV PYTHONUNBUFFERED=1
ENV IMAGEIO_FFMPEG_EXE=/usr/bin/ffmpeg
ENV COMFYUI_DIR=/app/ComfyUI

# CUDA optimizations for better memory allocation and large model support
# expandable_segments reduces fragmentation for large video tensors
# garbage_collection_threshold triggers cleanup at 70% for Wan 14B headroom
ENV PYTORCH_ALLOC_CONF=expandable_segments:True,garbage_collection_threshold:0.7

# Enable TF32 for faster matmul on Blackwell tensor cores
ENV TORCH_ALLOW_TF32_CUBLAS_OVERRIDE=1
ENV NVIDIA_TF32_OVERRIDE=1

# cuDNN optimizations
ENV CUDNN_V8_API_ENABLED=1
ENV TORCH_CUDNN_V8_API_ENABLED=1

# torch.compile cache for persistent compilation artifacts
ENV TORCHINDUCTOR_CACHE_DIR=/workspace/.torch_compile_cache
ENV TORCH_COMPILE_DEBUG=0

# ComfyUI-Manager security level (weak allows pip installs from manager)
ENV CM_SECURITY_LEVEL=weak

# Copy Python packages from builder stage
COPY --from=builder /usr/local/lib/python3.12/dist-packages /usr/local/lib/python3.12/dist-packages

# Copy torch constraints file and set env var to prevent version changes at runtime
COPY --from=builder /etc/torch-constraints.txt /etc/torch-constraints.txt
ENV PIP_CONSTRAINT=/etc/torch-constraints.txt

# Copy ComfyUI with built-in custom nodes from builder stage
COPY --from=builder /tmp/build/ComfyUI /app/ComfyUI

# Remove uv to force ComfyUI-Manager to use pip
RUN pip uninstall -y uv 2>/dev/null || true && \
    rm -f /usr/local/bin/uv /usr/local/bin/uvx

# Create workspace directories for persistent data
RUN mkdir -p /workspace/models /workspace/output /workspace/input /workspace/user /workspace/custom_nodes

WORKDIR /app/ComfyUI

# Expose ports: ComfyUI, SSH, Jupyter, FileBrowser
EXPOSE 8188 22 8888 8080

# Copy and set up start script
COPY start.sh /start.sh
RUN chmod +x /start.sh

ENTRYPOINT ["/start.sh"]
