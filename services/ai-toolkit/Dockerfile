# ============================================================================
# AI Toolkit service image — inherits CUDA, PyTorch, Jupyter, FileBrowser from base
# ============================================================================
FROM base

# Install Node.js (needed for AI Toolkit UI)
RUN curl -sL https://deb.nodesource.com/setup_23.x -o /tmp/nodesource_setup.sh && \
  bash /tmp/nodesource_setup.sh && \
  apt-get update && \
  apt-get install -y nodejs && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* /tmp/nodesource_setup.sh

# Clone AI Toolkit repo (CACHEBUST invalidates cache to pull latest)
ARG CACHEBUST=1234
ARG GIT_COMMIT=main
WORKDIR /tmp/build
RUN echo "Cache bust: ${CACHEBUST}" && \
  git clone https://github.com/ostris/ai-toolkit.git && \
  cd ai-toolkit && \
  git checkout ${GIT_COMMIT}

WORKDIR /tmp/build/ai-toolkit

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt && \
  pip install setuptools==69.5.1 --no-cache-dir

# Build UI
WORKDIR /tmp/build/ai-toolkit/ui
RUN npm install && \
  npm run build && \
  npm run update_db

# Bake to known location for runtime copy
RUN cp -r /tmp/build/ai-toolkit /opt/ai-toolkit-baked

# Clean up build artifacts
RUN rm -rf /tmp/build

# Expose AI Toolkit UI port
EXPOSE 8675

# Copy start script
COPY services/ai-toolkit/start.sh /start.sh

WORKDIR /workspace

ENTRYPOINT ["/start.sh"]
