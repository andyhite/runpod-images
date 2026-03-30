# ComfyUI Model Manager & S3 Sync Narrowing

## Problem

ComfyUI pods take a long time to start because the S3 sync transfers the entire `/workspace/comfyui` directory, including multi-GB model files. Models download faster from HuggingFace than from S3, and not every pod needs every model.

## Solution

Two changes:

1. **Narrow S3 sync** to only sync state directories (configs, outputs, workflows, databases), excluding models entirely.
2. **Model manager** that downloads models from HuggingFace, CivitAI, or direct URLs based on a YAML manifest and an environment variable selecting which model groups to activate.

## S3 Sync Narrowing

### Synced Directories

Instead of syncing the entire `/workspace/comfyui` directory, sync only these subdirectories:

- `user/` — workflows, settings, Manager config, SQLite databases
- `output/` — generated images/videos
- `input/` — uploaded reference images
- `custom_nodes/` — user-installed nodes beyond baked ones
- `blueprints/` — blueprints feature data
- `model-manifest.yaml` — the model group definitions file

Models are no longer stored in or synced from S3. Existing model data in S3 becomes orphaned and can be cleaned up manually.

### Implementation Approach

Replace the single `sync_download`/`sync_upload` call with multiple per-directory calls. This is safer than filtering because `sync_upload` uses `rclone sync` (which mirrors, including deletions) — per-directory calls scope the mirror to each subdirectory and avoid accidentally deleting remote data. For the single manifest file, use `rclone copyto` to sync it individually.

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

A default manifest is baked into the image at `/opt/comfyui-baked/model-manifest.yaml`. On first-time setup, it's copied to `/workspace/comfyui/model-manifest.yaml` along with the rest of the baked directory. On subsequent starts, the S3-synced version overlays it (rclone copy overwrites newer files), so per-pod customizations persist.

### Source Prefixes

- **`hf://org/repo/path/file.ext`** — single file from HuggingFace. Uses `hf` CLI. Respects `HF_TOKEN` for gated models.
- **`hf://org/repo/`** (trailing slash) — download full repo contents into `dest` as a subdirectory named after the repo (for sharded checkpoints).
- **`civitai://model_id`** — download default version from CivitAI API. Supports `civitai://model_id/version_id` for specific versions. Respects `CIVITAI_TOKEN`. Filename is resolved from the API response's `Content-Disposition` header.
- **`https://...`** — direct URL download via `wget`/`curl`. Filename is the last path segment of the URL.

### Field Definitions

- **`name`** — human-readable identifier for logging/progress output.
- **`source`** — where to download the model from, using the prefixes above.
- **`dest`** — destination directory relative to `/workspace/comfyui/`. The filename is derived from the source as described above.

## Group Selection

Active groups are selected via environment variable on the RunPod pod/template:

```
MODEL_GROUPS=flux-klein-9b,wan-2.2-14b
```

Comma-separated group names matching keys in the manifest. If `MODEL_GROUPS` is not set, the model manager is skipped entirely.

If a group name in `MODEL_GROUPS` does not exist in the manifest, log a warning and skip it (do not fail startup).

## State Tracking

A state file at `/workspace/comfyui/.model-state.yaml` tracks what's currently installed on disk:

```yaml
installed_groups:
  - flux-klein-9b
installed_models:
  - source: hf://black-forest-labs/FLUX.1-dev/flux1-dev.safetensors
    dest: models/checkpoints/flux1-dev.safetensors
    groups:
      - flux-klein-9b
  - source: hf://black-forest-labs/FLUX.1-dev/ae.safetensors
    dest: models/vae/ae.safetensors
    groups:
      - flux-klein-9b
```

This file is not synced to S3 — it reflects local disk state only.

The `groups` field on each model entry is a list, not a single value. When two groups share a model (same source + dest), both group names appear in the list. The model is only removed when none of its groups are active.

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
- 3 parallel downloads within a group, sequential across groups
- Retry on failure (3 attempts with exponential backoff)

## Error Handling

- **Invalid manifest YAML**: Log error, skip model management, allow ComfyUI to start (user can fix via SSH/Jupyter)
- **Missing manifest file**: Log warning, skip model management
- **Unknown group in `MODEL_GROUPS`**: Log warning for the unknown group, process remaining valid groups
- **Download failure (after retries)**: Log error for the failed model, continue with remaining models, exit with non-zero to surface the issue but do not block ComfyUI startup
- **Insufficient disk space**: No pre-check; if a download fails due to disk space, it's caught by the download failure handling above

## Integration into start.sh

The model manager runs after S3 sync download but before dependency installation:

1. `configure_sync` (narrowed to specific directories)
2. `setup_ssh`, filebrowser, jupyter
3. First-time setup: copy baked ComfyUI to workspace
4. `sync_download` (per-directory calls for user/, output/, input/, custom_nodes/, blueprints/, model-manifest.yaml)
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

## Build Dependencies

The `hf` CLI (from `huggingface-hub` Python package) must be installed in the image. Add `huggingface-hub` to the Dockerfile's pip install step. The `pyyaml` package is also needed for manifest parsing.

The `export_env_vars` function in `start-helpers.sh` needs its grep pattern updated to forward `HF_TOKEN`, `CIVITAI_TOKEN`, and `MODEL_GROUPS` to SSH sessions and child environments.

## Implementation

The model manager is a Python script at `/opt/model-manager.py`, baked into the image at build time. Python over bash because it needs to parse YAML, handle multiple download sources, manage state, and the diffing/cleanup logic benefits from a real language.
