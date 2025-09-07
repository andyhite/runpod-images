FROM runpod/base:0.6.3-cuda11.8.0

ARG VERSION

WORKDIR /ComfyUI

# Create model directories
RUN mkdir -p /ComfyUI/models/{checkpoints,clip,clip_vision,controlnet,diffusers,embeddings,loras,upscale_models,vae}

# Setup Python and pip symlinks
RUN ln -sf /usr/bin/python3.10 /usr/bin/python && \
  ln -sf /usr/bin/python3.10 /usr/bin/python3 && \
  python -m pip install --upgrade pip && \
  ln -sf /usr/local/bin/pip3.10 /usr/local/bin/pip

# Install ComfyUI manually
RUN git init && \
  git remote add origin https://github.com/comfyanonymous/ComfyUI.git && \
  git fetch --depth 1 origin tag v${VERSION} && \
  git checkout FETCH_HEAD && \
  pip install -r requirements.txt

# Install ComfyUI Manager
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git custom_nodes/ComfyUI-Manager && \
  cd custom_nodes/ComfyUI-Manager && \
  pip install -r requirements.txt

# Create user directory to store logs
RUN mkdir -p ./user

# Copy the extra_model_paths.yml and start script
COPY ./extra_model_paths.yml ./extra_model_paths.yml
COPY --chmod=755 start.sh /start.sh

CMD ["/start.sh"]
