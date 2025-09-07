FROM runpod/base:0.6.3-cuda11.8.0

ARG VERSION

# Create model directories
RUN mkdir -p /ComfyUI/models/{checkpoints,clip,clip_vision,controlnet,diffusers,embeddings,loras,upscale_models,vae} && \
  cd /ComfyUI/models/checkpoints

# Setup Python and pip symlinks
RUN ln -sf /usr/bin/python3.10 /usr/bin/python && \
  ln -sf /usr/bin/python3.10 /usr/bin/python3 && \
  python -m pip install --upgrade pip && \
  ln -sf /usr/local/bin/pip3.10 /usr/local/bin/pip

# Install ComfyUI and ComfyUI Manager
RUN cd /ComfyUI && \
  git init && \
  git remote add origin https://github.com/comfyanonymous/ComfyUI.git && \
  git fetch --depth 1 origin tag v${VERSION} && \
  git checkout FETCH_HEAD && \
  pip install -r requirements.txt && \
  git clone https://github.com/ltdrdata/ComfyUI-Manager.git custom_nodes/ComfyUI-Manager && \
  cd custom_nodes/ComfyUI-Manager && \
  pip install -r requirements.txt

# Create user directory to store logs
RUN mkdir -p /ComfyUI/user

# Copy the extra_model_paths.yml and start script
COPY --chmod=755 start.sh /start.sh
COPY ./extra_model_paths.yml /ComfyUI/extra_model_paths.yml

CMD ["/start.sh"]
