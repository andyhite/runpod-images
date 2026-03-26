# ============================================================================
# Stage 1: Builder - Install CUDA, PyTorch, and shared Python packages
# ============================================================================
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# ---- Version pins (set in docker-bake.hcl) ----
ARG CUDA_VERSION_DASH=13-0
ARG TORCH_INDEX_SUFFIX=cu130
ARG TORCH_VERSION
ARG TORCHVISION_VERSION
ARG TORCHAUDIO_VERSION

# Install minimal dependencies needed for building
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  wget \
  curl \
  git \
  ca-certificates \
  python3.12 \
  python3.12-venv \
  python3.12-dev \
  build-essential \
  && wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
  && dpkg -i cuda-keyring_1.1-1_all.deb \
  && apt-get update \
  && apt-get install -y --no-install-recommends cuda-minimal-build-${CUDA_VERSION_DASH} libcusparse-dev-${CUDA_VERSION_DASH} \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && rm cuda-keyring_1.1-1_all.deb \
  && rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED

# Install pip and pip-tools for lock file generation
RUN curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
  python3.12 get-pip.py && \
  python3.12 -m pip install --no-cache-dir "pip-tools>=7.0" && \
  rm get-pip.py

# Set CUDA environment for building
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64

# Install PyTorch (pinned version)
RUN python3.12 -m pip install --no-cache-dir \
  torch==${TORCH_VERSION} torchvision==${TORCHVISION_VERSION} torchaudio==${TORCHAUDIO_VERSION} \
  --index-url https://download.pytorch.org/whl/${TORCH_INDEX_SUFFIX}

# Install Jupyter and shared Python packages, generate lock file
WORKDIR /tmp/build
RUN echo "jupyter" > requirements.in && \
  echo "jupyter-resource-usage" >> requirements.in && \
  echo "jupyterlab-nvdashboard" >> requirements.in && \
  echo "torch==${TORCH_VERSION}" >> constraints.txt && \
  echo "torchvision==${TORCHVISION_VERSION}" >> constraints.txt && \
  echo "torchaudio==${TORCHAUDIO_VERSION}" >> constraints.txt && \
  PIP_CONSTRAINT=constraints.txt pip-compile --generate-hashes --output-file=requirements.lock --strip-extras --allow-unsafe requirements.in && \
  python3.12 -m pip install --no-cache-dir --ignore-installed --require-hashes -r requirements.lock

# ============================================================================
# Stage 2: Runtime - Add CUDA/PyTorch/Jupyter on top of base-core
# ============================================================================
FROM base-core

ENV IMAGEIO_FFMPEG_EXE=/usr/bin/ffmpeg
ENV TORCH_CUDA_ARCH_LIST="8.0 8.6 8.9 9.0 10.0 12.0"

# ---- CUDA variant (re-declared for runtime stage) ----
ARG CUDA_VERSION_DASH=13-0

# Install CUDA runtime packages
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb && \
  dpkg -i cuda-keyring_1.1-1_all.deb && \
  apt-get update && \
  apt-get install -y --no-install-recommends cuda-minimal-build-${CUDA_VERSION_DASH} && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  rm cuda-keyring_1.1-1_all.deb

# Copy Python packages and Jupyter data from builder stage
COPY --from=builder /usr/local/lib/python3.12 /usr/local/lib/python3.12
COPY --from=builder /usr/local/share/jupyter /usr/local/share/jupyter

# Copy specific executables from builder (avoid overwriting filebrowser/rclone from base-core)
RUN --mount=from=builder,src=/usr/local/bin,dst=/tmp/builder-bin \
  cp /tmp/builder-bin/pip* /usr/local/bin/ && \
  cp /tmp/builder-bin/pip-compile /usr/local/bin/ && \
  cp /tmp/builder-bin/pip-sync /usr/local/bin/ && \
  cp /tmp/builder-bin/jupyter* /usr/local/bin/ && \
  cp /tmp/builder-bin/ipython* /usr/local/bin/ 2>/dev/null || true

# Register Jupyter extensions (pip --ignore-installed skips post-install hooks)
RUN mkdir -p /usr/local/etc/jupyter/jupyter_server_config.d && \
  echo '{"ServerApp":{"jpserver_extensions":{"jupyter_server_terminals":true,"jupyterlab":true,"jupyter_resource_usage":true,"jupyterlab_nvdashboard":true}}}' \
  > /usr/local/etc/jupyter/jupyter_server_config.d/extensions.json

# ---- PyTorch version pins (re-declared for runtime stage) ----
ARG TORCH_VERSION
ARG TORCHVISION_VERSION
ARG TORCHAUDIO_VERSION

# Pin PyTorch packages so runtime pip installs cannot overwrite the CUDA wheels
RUN echo "torch==${TORCH_VERSION}" > /etc/pip-torch-constraints.txt && \
  echo "torchvision==${TORCHVISION_VERSION}" >> /etc/pip-torch-constraints.txt && \
  echo "torchaudio==${TORCHAUDIO_VERSION}" >> /etc/pip-torch-constraints.txt

# Set CUDA and PyTorch library paths
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/lib/python3.12/dist-packages/torch/lib:/usr/local/lib/python3.12/dist-packages/torchaudio/lib:/usr/local/cuda/lib64

# Expose Jupyter port
EXPOSE 8888
