# ============================================================================
# ComfyUI service image — inherits CUDA, PyTorch, Jupyter, FileBrowser from base
# ============================================================================
FROM base

# ---- Version pins (set in docker-bake.hcl) ----
ARG COMFYUI_VERSION
ARG MANAGER_SHA
ARG KJNODES_SHA
ARG CIVICOMFY_SHA
ARG RUNPODDIRECT_SHA
ARG TORCH_VERSION
ARG TORCHVISION_VERSION
ARG TORCHAUDIO_VERSION

# Download pinned source archives
WORKDIR /tmp/build
RUN curl -fSL "https://github.com/comfyanonymous/ComfyUI/archive/refs/tags/${COMFYUI_VERSION}.tar.gz" -o comfyui.tar.gz && \
  mkdir -p ComfyUI && tar xzf comfyui.tar.gz --strip-components=1 -C ComfyUI && rm comfyui.tar.gz

WORKDIR /tmp/build/ComfyUI/custom_nodes
RUN curl -fSL "https://github.com/ltdrdata/ComfyUI-Manager/archive/${MANAGER_SHA}.tar.gz" -o manager.tar.gz && \
  mkdir -p ComfyUI-Manager && tar xzf manager.tar.gz --strip-components=1 -C ComfyUI-Manager && rm manager.tar.gz && \
  curl -fSL "https://github.com/kijai/ComfyUI-KJNodes/archive/${KJNODES_SHA}.tar.gz" -o kjnodes.tar.gz && \
  mkdir -p ComfyUI-KJNodes && tar xzf kjnodes.tar.gz --strip-components=1 -C ComfyUI-KJNodes && rm kjnodes.tar.gz && \
  curl -fSL "https://github.com/MoonGoblinDev/Civicomfy/archive/${CIVICOMFY_SHA}.tar.gz" -o civicomfy.tar.gz && \
  mkdir -p Civicomfy && tar xzf civicomfy.tar.gz --strip-components=1 -C Civicomfy && rm civicomfy.tar.gz && \
  curl -fSL "https://github.com/MadiatorLabs/ComfyUI-RunpodDirect/archive/${RUNPODDIRECT_SHA}.tar.gz" -o runpoddirect.tar.gz && \
  mkdir -p ComfyUI-RunpodDirect && tar xzf runpoddirect.tar.gz --strip-components=1 -C ComfyUI-RunpodDirect && rm runpoddirect.tar.gz

# Init git repos with upstream remotes so ComfyUI-Manager can detect versions
RUN cd /tmp/build/ComfyUI && \
  git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ComfyUI ${COMFYUI_VERSION}" && git tag "${COMFYUI_VERSION}" && \
  git remote add origin https://github.com/comfyanonymous/ComfyUI.git && \
  cd /tmp/build/ComfyUI/custom_nodes/ComfyUI-Manager && \
  git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ComfyUI-Manager ${MANAGER_SHA}" && \
  git remote add origin https://github.com/ltdrdata/ComfyUI-Manager.git && \
  cd /tmp/build/ComfyUI/custom_nodes/ComfyUI-KJNodes && \
  git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ComfyUI-KJNodes ${KJNODES_SHA}" && \
  git remote add origin https://github.com/kijai/ComfyUI-KJNodes.git && \
  cd /tmp/build/ComfyUI/custom_nodes/Civicomfy && \
  git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "Civicomfy ${CIVICOMFY_SHA}" && \
  git remote add origin https://github.com/MoonGoblinDev/Civicomfy.git && \
  cd /tmp/build/ComfyUI/custom_nodes/ComfyUI-RunpodDirect && \
  git init && git add -A && git -c user.name=- -c user.email=- commit -q -m "ComfyUI-RunpodDirect ${RUNPODDIRECT_SHA}" && \
  git remote add origin https://github.com/MadiatorLabs/ComfyUI-RunpodDirect.git

# Generate lock file from all requirements, then install with hash verification
WORKDIR /tmp/build
RUN cat ComfyUI/requirements.txt > requirements.in && \
  for node_dir in ComfyUI/custom_nodes/*/; do \
  if [ -f "$node_dir/requirements.txt" ]; then \
  cat "$node_dir/requirements.txt" >> requirements.in; \
  fi; \
  done && \
  echo "GitPython" >> requirements.in && \
  echo "opencv-python" >> requirements.in && \
  echo "torch==${TORCH_VERSION}" >> constraints.txt && \
  echo "torchvision==${TORCHVISION_VERSION}" >> constraints.txt && \
  echo "torchaudio==${TORCHAUDIO_VERSION}" >> constraints.txt && \
  echo "pillow>=12.1.1" >> constraints.txt && \
  PIP_CONSTRAINT=constraints.txt pip-compile --generate-hashes --output-file=requirements.lock --strip-extras --allow-unsafe requirements.in && \
  python3.12 -m pip install --no-cache-dir --ignore-installed --require-hashes -r requirements.lock

# Pre-populate ComfyUI-Manager cache so first cold start skips the slow registry fetch
COPY images/comfyui/scripts/prebake-manager-cache.py /tmp/prebake-manager-cache.py
RUN python3.12 /tmp/prebake-manager-cache.py /tmp/build/ComfyUI/user/__manager/cache

# Bake ComfyUI + custom nodes into a known location for runtime copy
RUN cp -r /tmp/build/ComfyUI /opt/comfyui-baked

# Clean up build artifacts
RUN rm -rf /tmp/build

# Expose ComfyUI port
EXPOSE 8188

# Copy start script
COPY images/comfyui/start.sh /start.sh

WORKDIR /workspace

ENTRYPOINT ["/start.sh"]
