# Shared Base Image Design

## Summary

Extract common CUDA/PyTorch/tooling layers from service Dockerfiles into a shared base image (`andyhite/runpod-base`). Service images (comfyui, ai-toolkit) inherit from the base and add only app-specific setup. All services use the same bake-to-opt/copy-to-workspace pattern. Path convention changes from `/workspace/runpod-slim/...` to `/workspace/<service-name>`.

## File Structure

```
images/
  base/
    Dockerfile            # shared base image (two-stage build)
    start-helpers.sh      # common shell functions sourced by service start scripts
services/
  comfyui/
    Dockerfile            # FROM base, app-specific setup
    start.sh              # sources start-helpers.sh, runs ComfyUI
    scripts/
      prebake-manager-cache.py
  ai-toolkit/
    Dockerfile            # FROM base, app-specific setup
    start.sh              # sources start-helpers.sh, runs ai-toolkit UI
```

## Shared Base Image (`images/base/Dockerfile`)

### Builder Stage

- Base: `ubuntu:24.04`
- Build deps: git, curl, wget, python3.12, python3.12-venv, python3.12-dev, build-essential, ca-certificates
- CUDA: manual install via `cuda-keyring` + `cuda-minimal-build-${CUDA_VERSION_DASH}` + `libcusparse-dev-${CUDA_VERSION_DASH}`
- pip: installed via `get-pip.py`, plus `pip-tools`
- PyTorch: `torch==${TORCH_VERSION}`, `torchvision==${TORCHVISION_VERSION}`, `torchaudio==${TORCHAUDIO_VERSION}` from `https://download.pytorch.org/whl/${TORCH_INDEX_SUFFIX}`
- Jupyter: jupyter, jupyter-resource-usage, jupyterlab-nvdashboard
- Lock file: `pip-compile --generate-hashes`, install with `--require-hashes`

### Runtime Stage

- Base: `ubuntu:24.04`
- Runtime deps: git, python3.12, python3.12-venv, python3.12-dev, build-essential, libssl-dev, wget, gnupg, xz-utils, openssh-client, openssh-server, nano, curl, htop, tmux, ca-certificates, less, net-tools, iputils-ping, procps, openssl, ffmpeg
- CUDA: manual runtime install via `cuda-keyring` + `cuda-minimal-build-${CUDA_VERSION_DASH}`
- Python packages + Jupyter data: copied from builder
- Jupyter extensions: registered via config JSON
- FileBrowser: pinned version with SHA256 checksum
- SSH: configured for root login (PermitRootLogin yes, PasswordAuthentication yes, host keys cleared for runtime generation)
- Python: `python3.12` set as default via `update-alternatives`
- `start-helpers.sh`: copied to `/start-helpers.sh`

### Build Args (all from docker-bake.hcl)

- `CUDA_VERSION_DASH`
- `TORCH_INDEX_SUFFIX`
- `TORCH_VERSION`
- `TORCHVISION_VERSION`
- `TORCHAUDIO_VERSION`
- `FILEBROWSER_VERSION`
- `FILEBROWSER_SHA256`

### Environment Variables

```
DEBIAN_FRONTEND=noninteractive
PYTHONUNBUFFERED=1
IMAGEIO_FFMPEG_EXE=/usr/bin/ffmpeg
PATH=/usr/local/cuda/bin:${PATH}
LD_LIBRARY_PATH=/usr/local/cuda/lib64
NVIDIA_REQUIRE_CUDA=""
NVIDIA_DISABLE_REQUIRE=true
NVIDIA_VISIBLE_DEVICES=all
NVIDIA_DRIVER_CAPABILITIES=all
```

### Exposed Ports

- 22 (SSH)
- 8888 (Jupyter)
- 8080 (FileBrowser)

## Shared Start Helpers (`images/base/start-helpers.sh`)

Sourced by each service's `start.sh`. Provides:

### `setup_ssh`

- Generate host keys with `ssh-keygen -A` if missing
- If `PUBLIC_KEY` env var set: add to `~/.ssh/authorized_keys`
- Otherwise: generate random password with `openssl rand -base64 12`, set via `chpasswd`
- Enable `PermitUserEnvironment yes`
- Start sshd

### `export_env_vars`

- Export `RUNPOD_*`, `PATH`, `CUDA*`, `LD_LIBRARY_PATH`, `PYTHONPATH` to:
  - `/etc/environment` (system-wide)
  - `/etc/security/pam_env.conf` (PAM)
  - `/root/.ssh/environment` (SSH sessions)
  - `/etc/rp_environment` (sourced in bashrc)

### `init_filebrowser`

- Check for DB at `/workspace/filebrowser.db`
- If missing: `filebrowser config init`, set address `0.0.0.0`, port `8080`, root `/workspace`, auth method `json`, add admin user

### `start_filebrowser`

- Start FileBrowser in background, log to `/filebrowser.log`

### `start_jupyter`

- Start JupyterLab on port 8888, root dir `/workspace`, token from `JUPYTER_PASSWORD` env var

## ComfyUI Service (`services/comfyui/Dockerfile`)

### Changes from Current

- Remove builder stage (CUDA, PyTorch, pip-tools all come from base)
- `FROM` the base image (via bake `contexts = { base = "target:base" }`)
- Keep all app-specific logic: download ComfyUI + custom nodes, init git repos, pip-compile app deps, prebake manager cache, bake to `/opt/comfyui-baked`
- Remove: uv uninstall step (stays or moves to base if needed)
- Path: `/opt/comfyui-baked` (build) -> `/workspace/comfyui` (runtime)

### Build Args (from docker-bake.hcl)

- `COMFYUI_VERSION`
- `MANAGER_SHA`, `KJNODES_SHA`, `CIVICOMFY_SHA`, `RUNPODDIRECT_SHA`

### ComfyUI `start.sh`

- Source `/start-helpers.sh`
- Call `setup_ssh`, `export_env_vars`, `init_filebrowser`, `start_filebrowser`, `start_jupyter`
- First-run: copy `/opt/comfyui-baked` -> `/workspace/comfyui`
- Create venv at `/workspace/comfyui/.venv-cu128` with `--system-site-packages`
- CUDA migration logic (updated paths: `/workspace/comfyui/...`)
- Read `/workspace/comfyui/comfyui_args.txt` for custom args
- Start ComfyUI on port 8188
- Crash recovery: log message, `sleep infinity` (SSH/Jupyter stay alive)

### Exposed Ports (additional)

- 8188 (ComfyUI)

## AI Toolkit Service (`services/ai-toolkit/Dockerfile`)

### Structure

- `FROM` the base image (via bake `contexts = { base = "target:base" }`)
- Install Node.js 23.x (via nodesource)
- Clone `https://github.com/ostris/ai-toolkit.git` with `CACHEBUST` + `GIT_COMMIT` args
- Install Python deps: `pip install -r requirements.txt` + `setuptools==69.5.1`
- Build UI: `npm install && npm run build && npm run update_db`
- Bake to `/opt/ai-toolkit-baked`
- Copy `start.sh`

### Build Args

- `CACHEBUST` (default: 1234)
- `GIT_COMMIT` (default: main)

### AI Toolkit `start.sh`

- Source `/start-helpers.sh`
- Call `setup_ssh`, `export_env_vars`, `init_filebrowser`, `start_filebrowser`, `start_jupyter`
- First-run: copy `/opt/ai-toolkit-baked` -> `/workspace/ai-toolkit`
- Start UI: `cd /workspace/ai-toolkit/ui && npm run start`
- Crash recovery: log message, `sleep infinity`

### Exposed Ports (additional)

- 8675 (ai-toolkit UI)

## docker-bake.hcl

### Variables

Existing shared variables remain (CUDA, PyTorch, FileBrowser pins). No new variables needed.

### Targets

**`base`:**
- `context = "."`
- `dockerfile = "images/base/Dockerfile"`
- `tags = ["andyhite/runpod-base:${TAG}", "andyhite/runpod-base:latest"]`
- Args: CUDA, PyTorch, FileBrowser versions

**`comfyui`:**
- `context = "."`
- `dockerfile = "services/comfyui/Dockerfile"`
- `contexts = { base = "target:base" }`
- `tags = ["andyhite/runpod-comfyui:${TAG}", "andyhite/runpod-comfyui:latest"]`
- Args: COMFYUI_VERSION, custom node SHAs

**`ai-toolkit`:**
- `context = "."`
- `dockerfile = "services/ai-toolkit/Dockerfile"`
- `contexts = { base = "target:base" }`
- `tags = ["andyhite/runpod-ai-toolkit:${TAG}", "andyhite/runpod-ai-toolkit:latest"]`
- Args: CACHEBUST, GIT_COMMIT

### Groups

- `default` group includes all three targets (or configurable per need)

## Makefile

- `SERVICE` variable selectable: `make build SERVICE=ai-toolkit`
- Build commands use `docker buildx bake $(SERVICE)`
- `IMAGE_NAME` derived from `SERVICE`
- All path references updated from `/workspace/runpod-slim` to `/workspace/<service>`

## Path Migration Summary

| Old Path | New Path |
|---|---|
| `/workspace/runpod-slim/ComfyUI` | `/workspace/comfyui` |
| `/workspace/runpod-slim/ComfyUI/.venv-cu128` | `/workspace/comfyui/.venv-cu128` |
| `/workspace/runpod-slim/comfyui_args.txt` | `/workspace/comfyui/comfyui_args.txt` |
| `/workspace/runpod-slim/.filebrowser.json` | `/workspace/.filebrowser.json` |
| `/workspace/runpod-slim/filebrowser.db` | `/workspace/filebrowser.db` |
| N/A (new) | `/workspace/ai-toolkit` |
