# ComfyUI Model Manager & S3 Sync Narrowing

## Problem

ComfyUI pods take a long time to start because the S3 sync transfers the entire `/workspace/comfyui` directory, including multi-GB model files. Models download faster from HuggingFace than from S3, and not every pod needs every model.

## Solution

Two changes:

1. **Narrow S3 sync** to only sync state directories (configs, outputs, workflows, databases), excluding models entirely.
2. **Model manager** that downloads models from HuggingFace, CivitAI, or direct URLs based on a YAML manifest and an environment variable selecting which model groups to activate.

## S3 Sync Narrowing

### Synced Directories

Instead of syncing the entire `/workspace/comfyui` directory, sync only:

- `user/` — workflows, settings, Manager config, SQLite databases
- `output/` — generated images/videos
- `input/` — uploaded reference images
- `custom_nodes/` — user-installed nodes beyond baked ones
- `blueprints/` — blueprints feature data

Additionally, sync the manifest file: `model-manifest.yaml` (at workspace root).

Models are no longer stored in or synced from S3. Existing model data in S3 becomes orphaned and can be cleaned up manually.

## Model Manifest

A YAML file at `/workspace/comfyui/model-manifest.yaml` defines available model groups:

```yaml
groups:
  flux-klein-9b:
    models:
      - name: flux-klein-9b
        source: hf://black-forest-labs/FLUX.1-dev/flux1-dev.safetensors
        dest: models/checkpoints/
      - name: ae-vae
        source: hf://black-forest-labs/FLUX.1-dev/ae.safetensors
        dest: models/vae/
      - name: t5-fp16
        source: hf://comfyanonymous/flux_text_encoders/t5xxl_fp16.safetensors
        dest: models/text_encoders/

  wan-2.2-14b:
    models:
      - name: wan-2.2-t2v-14b
        source: hf://Wan-AI/Wan2.2-T2V-14B/model.safetensors
        dest: models/checkpoints/
      - name: some-lora
        source: civitai://123456
        dest: models/loras/
      - name: custom-model
        source: https://example.com/model.safetensors
        dest: models/other/
```

### Source Prefixes

- **`hf://org/repo/path/file.ext`** — single file from HuggingFace. Uses `hf` CLI. Respects `HF_TOKEN` for gated models.
- **`hf://org/repo/`** — download full repo contents (for sharded checkpoints).
- **`civitai://model_id`** — download default version from CivitAI API. Supports `civitai://model_id/version_id` for specific versions. Respects `CIVITAI_TOKEN`.
- **`https://...`** — direct URL download via `wget`/`curl`.

### Field Definitions

- **`name`** — human-readable identifier for logging/progress output.
- **`source`** — where to download the model from, using the prefixes above.
- **`dest`** — destination directory relative to `/workspace/comfyui/`. The filename comes from the source.

## Group Selection

Active groups are selected via environment variable on the RunPod pod/template:

```
MODEL_GROUPS=flux-klein-9b,wan-2.2-14b
```

Comma-separated group names matching keys in the manifest. If `MODEL_GROUPS` is not set, the model manager is skipped entirely.

## State Tracking

A state file at `/workspace/comfyui/.model-state.yaml` tracks what's currently installed on disk:

```yaml
installed_groups:
  - flux-klein-9b
installed_models:
  - source: hf://black-forest-labs/FLUX.1-dev/flux1-dev.safetensors
    dest: models/checkpoints/flux1-dev.safetensors
    group: flux-klein-9b
  - source: hf://black-forest-labs/FLUX.1-dev/ae.safetensors
    dest: models/vae/ae.safetensors
    group: flux-klein-9b
```

This file is not synced to S3 — it reflects local disk state only.

If two groups share a model (same source + dest), the model stays on disk as long as at least one group referencing it is active.

## Startup Behavior

On pod startup, the model manager:

1. Reads `MODEL_GROUPS` env var
2. Reads the manifest to resolve which models are needed
3. Reads the state file to see what's already installed
4. **Downloads** models in newly-added groups (skipping any already present on disk)
5. **Removes** models belonging to groups no longer in `MODEL_GROUPS`
6. Updates the state file

## Download Behavior

- Downloads go to a temp file first, then move into place (avoids partial files on interruption)
- Progress output per model ("Downloading flux-klein-9b: model 2/5 — t5-fp16...")
- Parallel downloads within a group (default 2-3 concurrent)
- Retry on failure (2-3 attempts with backoff)

## Integration into start.sh

The model manager runs after S3 sync download but before dependency installation:

1. `configure_sync` (narrowed to specific directories)
2. `setup_ssh`, filebrowser, jupyter
3. First-time setup: copy baked ComfyUI to workspace
4. `sync_download` (only syncs user/, output/, input/, custom_nodes/, blueprints/, model-manifest.yaml)
5. **Run model manager** (new)
6. Install/update dependencies
7. Start ComfyUI

```bash
if [ -n "$MODEL_GROUPS" ]; then
    python /opt/model-manager.py \
        --manifest "$COMFYUI_DIR/model-manifest.yaml" \
        --state "$COMFYUI_DIR/.model-state.yaml" \
        --base-dir "$COMFYUI_DIR" \
        --groups "$MODEL_GROUPS"
fi
```

## Implementation

The model manager is a Python script at `/opt/model-manager.py`, baked into the image at build time. Python over bash because it needs to parse YAML, handle multiple download sources, manage state, and the diffing/cleanup logic benefits from a real language.

A default manifest ships baked into the image, but the workspace copy (synced from S3) takes precedence so it can be customized per-pod.
