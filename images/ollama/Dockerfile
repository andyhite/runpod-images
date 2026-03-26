# ============================================================================
# Ollama service image — inherits SSH, FileBrowser, rclone from base-core
# ============================================================================
FROM base-core

# Install Ollama (pinned version with checksum)
ARG OLLAMA_VERSION
ARG OLLAMA_SHA256
RUN curl -fSL "https://github.com/ollama/ollama/releases/download/${OLLAMA_VERSION}/ollama-linux-amd64.tgz" -o /tmp/ollama.tgz && \
  echo "${OLLAMA_SHA256}  /tmp/ollama.tgz" | sha256sum -c - && \
  tar xzf /tmp/ollama.tgz -C /usr && \
  rm /tmp/ollama.tgz

# Install Open WebUI
RUN pip install --no-cache-dir open-webui

# Configure Ollama for remote access
ENV OLLAMA_HOST=0.0.0.0

# Store models on persistent workspace
ENV OLLAMA_MODELS=/workspace/ollama/models

# Expose Ollama API and Open WebUI ports
EXPOSE 11434 6969

# Copy start script
COPY images/ollama/start.sh /start.sh

WORKDIR /workspace

ENTRYPOINT ["/start.sh"]
