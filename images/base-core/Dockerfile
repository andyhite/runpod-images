# ============================================================================
# base-core: Universal RunPod foundation
# SSH, FileBrowser, rclone, Python 3.12 — no CUDA or PyTorch
# ============================================================================
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# ---- FileBrowser version pin (set in docker-bake.hcl) ----
ARG FILEBROWSER_VERSION
ARG FILEBROWSER_SHA256
ARG RCLONE_VERSION
ARG RCLONE_SHA256

# Update and install runtime dependencies and common tools
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
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED

# Install pip
RUN curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
  python3.12 get-pip.py && \
  rm get-pip.py

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
COPY images/base-core/start-helpers.sh /start-helpers.sh

# Create workspace directory
RUN mkdir -p /workspace
WORKDIR /workspace

# Expose common ports: SSH, FileBrowser
EXPOSE 22 8080
