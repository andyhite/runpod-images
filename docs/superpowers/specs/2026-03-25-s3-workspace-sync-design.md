# S3 Workspace Sync Design

## Problem

RunPod storage volumes are region-locked, which severely limits GPU availability. When a specific region has no GPUs available, the user is stuck waiting rather than being able to spin up a pod in any available region.

## Solution

Replace persistent storage volumes with S3-backed workspace sync using rclone. On pod start, download workspace data from S3. During the pod's life, periodically sync changes back. On pod termination (SIGTERM), perform a final upload. This decouples data persistence from region, allowing pods to start in any region with GPU availability.

## Design Decisions

- **Sync all of `/workspace`** — no exclusions. Application code is small relative to models/data (100GB+), and deps live in system Python, so the overhead is negligible. Avoids edge cases where important files are missed.
- **rclone over aws cli** — supports any S3-compatible backend (AWS, R2, B2, etc.) via environment variables. Better sync/filtering. Single static binary (~30MB).
- **S3 is source of truth between pods** — on start, S3 overwrites local. During a pod's life, local is canonical and periodically pushes to S3.
- **Opt-in via credentials** — if S3 env vars are present, sync activates. No env vars = no sync. No explicit toggle needed.
- **Periodic background sync** — protects against hard kills where SIGTERM isn't honored or the grace period is too short.

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `RCLONE_REMOTE_TYPE` | No | `s3` | rclone remote type |
| `RCLONE_S3_PROVIDER` | No | `AWS` | S3 provider (AWS, Cloudflare, etc.) |
| `RCLONE_S3_ACCESS_KEY_ID` | Yes* | — | S3 access key |
| `RCLONE_S3_SECRET_ACCESS_KEY` | Yes* | — | S3 secret key |
| `RCLONE_S3_REGION` | No | `us-east-1` | S3 region |
| `RCLONE_S3_ENDPOINT` | No | — | Custom endpoint (for R2, B2, etc.) |
| `SYNC_BUCKET` | Yes* | — | Bucket + optional path, e.g. `my-bucket/runpod/comfyui` |
| `SYNC_INTERVAL` | No | `600` | Seconds between periodic syncs |

\* Required for sync to activate. If `RCLONE_S3_ACCESS_KEY_ID` or `SYNC_BUCKET` are missing, sync is silently skipped.

rclone natively supports configuration via `RCLONE_`-prefixed environment variables, so no config file generation is needed. The remote is referenced as `:s3:${SYNC_BUCKET}`.

## Changes

### 1. Base Dockerfile: Install rclone

Add rclone installation to the runtime stage of `images/base/Dockerfile`, following the existing FileBrowser pattern:

- Pin version in `docker-bake.hcl` with `RCLONE_VERSION` and `RCLONE_SHA256` variables
- Download the official Linux AMD64 zip from rclone.org
- Verify SHA256 checksum
- Extract the `rclone` binary to `/usr/local/bin`
- Pass `RCLONE_VERSION` and `RCLONE_SHA256` as build args in the `base` target

### 2. `start-helpers.sh`: Add sync functions

Four new functions:

#### `configure_sync()`
- Checks for `RCLONE_S3_ACCESS_KEY_ID` and `SYNC_BUCKET`
- If either is missing, sets `SYNC_ENABLED=false` and returns
- Sets `SYNC_ENABLED=true`
- Constructs `SYNC_REMOTE=":s3:${SYNC_BUCKET}"`
- Defaults `SYNC_INTERVAL` to `600` if unset

#### `sync_download()`
- Guards on `SYNC_ENABLED`
- Uses `rclone copy` (not `rclone sync`) to avoid deleting local files that don't exist in S3. This is critical: on first run, S3 is empty, and `rclone sync` would wipe the baked app copy. `rclone copy` only adds/overwrites — never deletes.
- Runs: `rclone copy "$SYNC_REMOTE" /workspace --transfers=16 --checkers=32 --s3-no-check-bucket --fast-list --stats=30s --stats-one-line`
- `--transfers=16`: parallel file downloads for throughput on large datasets
- `--checkers=32`: parallel file comparison
- `--s3-no-check-bucket`: skip bucket existence check (faster, avoids permission issues)
- `--fast-list`: single LIST call instead of per-directory (faster for large buckets)
- `--stats=30s --stats-one-line`: progress logging every 30s so large syncs don't appear to hang
- If S3 path is empty (first-ever run), this is a no-op — the baked app copy remains intact
- **Error handling:** all rclone calls are guarded with `|| true` to prevent `set -e` from aborting the start script on sync failure. Errors are logged but never fatal.

#### `sync_upload()`
- Guards on `SYNC_ENABLED`
- Uses `rclone sync` (not `copy`) — upload direction intentionally mirrors local to S3, including deleting S3 objects that no longer exist locally. S3 should be an exact mirror of `/workspace`.
- Runs: `rclone sync /workspace "$SYNC_REMOTE" --transfers=16 --checkers=32 --s3-no-check-bucket --fast-list --stats=30s --stats-one-line`
- **Error handling:** guarded with `|| true`, same as download.
- **Note:** since `sync` propagates local deletions to S3, accidental local file removal will be reflected in S3 on the next upload. This is accepted behavior — S3 mirrors the workspace state.

#### `start_periodic_sync()`
- Guards on `SYNC_ENABLED`
- Launches a background subshell that loops: `sleep $SYNC_INTERVAL` then `sync_upload`
- Uses flock (`/tmp/sync.lock`) to prevent overlapping sync operations — if a previous sync is still running when the next interval fires, it skips that cycle
- Stores the loop PID in `SYNC_PID` for cleanup by the SIGTERM handler

### 3. Service start scripts: Integration

Both `images/comfyui/start.sh` and `images/ai-toolkit/start.sh` follow the same updated flow:

#### Startup order

```
1. source /start-helpers.sh
2. configure_sync
3. setup_ssh, export_env_vars (updated to include RCLONE_*/SYNC_*), init_filebrowser, start_filebrowser, start_jupyter
4. Copy baked app to /workspace (existing first-run logic — only if dir doesn't exist)
5. sync_download  ← S3 overlays on top, overwriting baked copy with persisted state
6. Install/update deps, start the service
7. start_periodic_sync
8. while true; do sleep 86400 & wait $!; done  (replaces sleep infinity, allows traps)
```

Step 4 provides a working baseline on the very first run (when S3 is empty). On all subsequent runs, step 5 overwrites it with the full persisted workspace from S3.

#### SIGTERM handling

Replace the current trap + `sleep infinity` pattern with:

```bash
shutdown() {
    set +e  # Disable set -e so kill failures don't abort the handler
    kill $APP_PID 2>/dev/null
    kill $SYNC_PID 2>/dev/null
    sync_upload wait
    exit 0
}
trap 'shutdown' SIGTERM SIGINT

# Start the application
<service> &
APP_PID=$!

start_periodic_sync

# Wait for app — if it exits (crash), fall through to keep-alive
wait $APP_PID || true

# If app crashes (not SIGTERM), keep container alive for SSH/Jupyter
echo "Service crashed — SSH and Jupyter still available"

# wait with no args returns immediately if no children remain,
# so use a blocking loop that still allows trap execution
while true; do sleep 86400 & wait $!; done
```

Key details:
- `set +e` inside `shutdown()` prevents `kill` on already-exited PIDs from aborting the handler before `sync_upload` runs.
- The final `while true; do sleep 86400 & wait $!; done` pattern blocks indefinitely while allowing traps to fire. Plain `wait` or `sleep infinity` would not work: `wait` returns immediately with no children, and `sleep infinity` is not interruptible by traps.

### 4. `docker-bake.hcl`: Version pins

Add two new variables:

```hcl
variable "RCLONE_VERSION" {
  default = "<latest stable>"
}
variable "RCLONE_SHA256" {
  default = "<sha256 of linux-amd64 zip>"
}
```

Pass them to the `base` target's `args` block.

### 5. `start-helpers.sh`: Update `export_env_vars()`

The `printenv` filter on line 42 currently only exports `RUNPOD_*`, `PATH`, `CUDA*`, `LD_LIBRARY_PATH`, and `PYTHONPATH`. Add `RCLONE_*` and `SYNC_*` patterns so that SSH sessions have access to sync credentials (needed if the user wants to run manual rclone commands via SSH for debugging).

### 6. `.env.example`: Document new variables

Add the sync-related environment variables with comments explaining usage. The file already exists at `.env.example`.

## Data Flow

```
First run (S3 empty):
  baked app → /workspace → rclone copy (no-op, S3 empty) → service starts → periodic sync → S3 gets first copy

Subsequent runs:
  baked app → /workspace → rclone copy overlays S3 data → service starts → periodic sync

Pod termination:
  SIGTERM → kill app → kill sync loop → final sync_upload → exit

Hard kill (no SIGTERM):
  Last periodic sync is the recovery point (max SYNC_INTERVAL seconds of data loss)
```

## Failure Modes

| Scenario | Behavior |
|---|---|
| S3 credentials invalid | rclone fails on sync_download (guarded with `|| true`), logged to stdout. Baked app still works, service starts, no sync. |
| S3 bucket doesn't exist | Same as above — rclone error logged, service still starts normally. |
| Network drops during sync | rclone retries by default (3 low-level retries). Periodic sync picks up on next interval. |
| Hard kill (no SIGTERM) | Data loss limited to changes since last periodic sync (default: up to 10 minutes). |
| SIGTERM with short grace period | Final sync_upload starts but may be interrupted. Periodic sync minimizes impact. |
| First run, S3 empty | `rclone copy` from empty source is a no-op (no deletions). Baked app provides working baseline. First periodic sync populates S3. |
| Accidental local file deletion | `rclone sync` upload mirrors local state to S3, so deletions propagate. Accepted behavior — S3 mirrors workspace. |
| Two pods with same SYNC_BUCKET | Unsupported. Both pods would overwrite each other's uploads. Use distinct paths per pod/service. |
| Overlapping sync operations | Prevented by flock — if a periodic sync is still running, the next interval skips. |
