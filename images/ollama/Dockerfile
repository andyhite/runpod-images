# ============================================================================
# Ollama service image — inherits SSH, FileBrowser, rclone from base-core
# ============================================================================
FROM base-core

# Install Ollama (pinned version)
ARG OLLAMA_VERSION
RUN curl -fSL "https://github.com/ollama/ollama/releases/download/${OLLAMA_VERSION}/ollama-linux-amd64.tgz" -o /tmp/ollama.tgz && \
  tar xzf /tmp/ollama.tgz -C /usr && \
  rm /tmp/ollama.tgz

# Configure Ollama for remote access
ENV OLLAMA_HOST=0.0.0.0

# Store models on persistent workspace
ENV OLLAMA_MODELS=/workspace/ollama/models

# Expose Ollama API port
EXPOSE 11434

# Copy start script
COPY images/ollama/start.sh /start.sh

WORKDIR /workspace

ENTRYPOINT ["/start.sh"]
