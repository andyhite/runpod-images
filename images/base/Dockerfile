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
  python3.12 -m pip install --no-cache-dir pip-tools && \
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
# Stage 2: Runtime - Clean image with pre-installed packages
# ============================================================================
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV IMAGEIO_FFMPEG_EXE=/usr/bin/ffmpeg
ENV TORCH_CUDA_ARCH_LIST="8.0 8.6 8.9 9.0 10.0 12.0"

# ---- CUDA variant (re-declared for runtime stage) ----
ARG CUDA_VERSION_DASH=13-0

# ---- FileBrowser version pin (set in docker-bake.hcl) ----
ARG FILEBROWSER_VERSION
ARG FILEBROWSER_SHA256
ARG RCLONE_VERSION
ARG RCLONE_SHA256

# Update and install runtime dependencies, CUDA, and common tools
RUN apt-get update && \
  apt-get upgrade -y && \
  apt-get install -y --no-install-recommends \
  git \
  python3.12 \
  python3.12-venv \
  python3.12-dev \
  build-essential \
  libssl-dev \
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
  unzip \
  openssl \
  ffmpeg \
  && wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
  && dpkg -i cuda-keyring_1.1-1_all.deb \
  && apt-get update \
  && apt-get install -y --no-install-recommends cuda-minimal-build-${CUDA_VERSION_DASH} \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && rm cuda-keyring_1.1-1_all.deb \
  && rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED

# Copy Python packages, executables, and Jupyter data from builder stage
COPY --from=builder /usr/local/lib/python3.12 /usr/local/lib/python3.12
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /usr/local/share/jupyter /usr/local/share/jupyter

# Register Jupyter extensions (pip --ignore-installed skips post-install hooks)
RUN mkdir -p /usr/local/etc/jupyter/jupyter_server_config.d && \
  echo '{"ServerApp":{"jpserver_extensions":{"jupyter_server_terminals":true,"jupyterlab":true,"jupyter_resource_usage":true,"jupyterlab_nvdashboard":true}}}' \
  > /usr/local/etc/jupyter/jupyter_server_config.d/extensions.json

# Install FileBrowser (pinned version with checksum)
RUN curl -fSL "https://github.com/filebrowser/filebrowser/releases/download/${FILEBROWSER_VERSION}/linux-amd64-filebrowser.tar.gz" -o /tmp/fb.tar.gz && \
  echo "${FILEBROWSER_SHA256}  /tmp/fb.tar.gz" | sha256sum -c - && \
  tar xzf /tmp/fb.tar.gz -C /usr/local/bin filebrowser && \
  rm /tmp/fb.tar.gz

# Install rclone (pinned version with checksum)
RUN curl -fSL "https://downloads.rclone.org/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-linux-amd64.zip" -o /tmp/rclone.zip && \
  echo "${RCLONE_SHA256}  /tmp/rclone.zip" | sha256sum -c - && \
  unzip -j /tmp/rclone.zip "*/rclone" -d /usr/local/bin && \
  chmod +x /usr/local/bin/rclone && \
  rm /tmp/rclone.zip

# Set CUDA and PyTorch library paths
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/lib/python3.12/dist-packages/torch/lib:/usr/local/lib/python3.12/dist-packages/torchaudio/lib:/usr/local/cuda/lib64

# Allow container to start on hosts with older CUDA drivers
ENV NVIDIA_REQUIRE_CUDA=""
ENV NVIDIA_DISABLE_REQUIRE=true
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all

# Configure SSH for root login
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
  sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
  mkdir -p /run/sshd && \
  rm -f /etc/ssh/ssh_host_*

# Set Python 3.12 as default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
  update-alternatives --set python3 /usr/bin/python3.12 && \
  ln -sf /usr/bin/python3 /usr/bin/python

# Copy shared start helpers
COPY images/base/start-helpers.sh /start-helpers.sh

# Create workspace directory
RUN mkdir -p /workspace
WORKDIR /workspace

# Expose common ports: SSH, Jupyter, FileBrowser
EXPOSE 22 8888 8080
