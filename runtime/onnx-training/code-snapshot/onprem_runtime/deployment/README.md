# Neuralese On-Prem Deployment

This folder contains the minimal deployment package for the on-prem ONNX training runtime.

## Local School

Run from the repository root:

```bash
cd onprem_runtime/deployment
docker compose -f docker-compose.local.yml up --build
```

Open:

```text
http://127.0.0.1:8010/
```

The service is pinned to `platform: linux/amd64` in compose because the ONNX Runtime Training CPU wheel used here is available for amd64 Linux.

## macOS Docker Setup

For a CLI-only setup without Docker Desktop:

```bash
brew install docker docker-compose docker-buildx colima
mkdir -p ~/.docker
```

`~/.docker/config.json` should include:

```json
{
  "cliPluginsExtraDirs": [
    "/opt/homebrew/lib/docker/cli-plugins"
  ]
}
```

Start the Docker daemon:

```bash
colima start --cpu 2 --memory 4 --disk 20
```

Verify:

```bash
docker ps
docker compose version
docker buildx version
```

Default local-school settings live in `.env.example`:

```text
NEURALESE_RUNTIME_MODE=local_school
NEURALESE_STORAGE_DIR=/data/jobs
NEURALESE_PUBLIC_DATASET_DIR=/data/datasets
NEURALESE_MAX_PARALLEL_JOBS=1
NEURALESE_AUTH_TOKEN=
```

Leave `NEURALESE_AUTH_TOKEN` empty for local demos. Set it to require auth on protected HTTP API and WebSocket routes.

The compose file mounts:

```text
./data/jobs     -> /data/jobs
./data/datasets -> /data/datasets
```

`/data/jobs` stores job workspaces and snapshots. `/data/datasets` is read-only inside the container and contains server-side public datasets.
The local contents of `./data/jobs` are runtime state and are ignored by git except for `.gitkeep`.

## Public Dataset Layout

Public datasets are loaded from `NEURALESE_PUBLIC_DATASET_DIR`.

Example:

```text
data/datasets/
  local-or/
    train.npz
    meta.json
```

Inside a bundle, reference it as:

```json
{
  "dataset_ref": {
    "type": "public",
    "id": "local-or"
  }
}
```

`local-or/train.npz` must contain `x` and `y`. Optional validation arrays are `val_x` and `val_y`.

## Cloud Node

For a Neuralese Cloud worker-style node, keep the same image and change env:

```bash
NEURALESE_RUNTIME_MODE=cloud_node \
NEURALESE_STORAGE_DIR=/data/jobs \
NEURALESE_PUBLIC_DATASET_DIR=/data/datasets \
NEURALESE_MAX_PARALLEL_JOBS=4 \
NEURALESE_AUTH_TOKEN=school-secret \
docker compose -f docker-compose.local.yml up --build
```

In `cloud_node`, the runtime disables the dashboard and direct upload by default. The scheduler can use:

```text
GET /api/health
GET /api/capacity
```

## Auth Token

When `NEURALESE_AUTH_TOKEN` is set, protected HTTP routes require:

```text
Authorization: Bearer <token>
```

or:

```text
X-Neuralese-Token: <token>
```

Protected WebSockets accept:

```text
?token=<token>
```

Example:

```bash
curl -H "Authorization: Bearer school-secret" http://127.0.0.1:8010/api/jobs
```

The dashboard has an API token field. It stores the token only in the current browser local storage.

## Smoke Test

Run the install smoke test without Docker:

```bash
python smoke_test.py --launcher local --port 8010
```

This starts the runtime through `python -m onprem_runtime`, creates a dummy ONNX bundle, uploads it to `POST /api/jobs`, waits on `WS /ws/jobs/{job_id}`, downloads `snapshot.zip`, and checks that the snapshot contains:

```text
manifest.json
inference.onnx
metrics.jsonl
```

Run the same smoke test through Docker:

```bash
python smoke_test.py --launcher docker --port 8010
```

If the runtime is already running, only test the API flow:

```bash
python smoke_test.py --launcher external --host 127.0.0.1 --port 8010
```

## Cleanup

Delete old completed/failed/stopped jobs and orphaned workspaces:

```bash
curl -H "Authorization: Bearer school-secret" \
  -X POST "http://127.0.0.1:8010/api/jobs/cleanup?max_age_seconds=604800"
```

Running jobs are never removed by cleanup.

## Local Synced Datasets

User-created local datasets do not need to be mounted as full files. The client syncs changed blocks through:

```text
WS /ws/datasets/sync
```

Then a training bundle references the cached dataset by fingerprint:

```json
{
  "dataset_ref": {
    "type": "local",
    "id": "school-dataset",
    "fingerprint": "sha256:..."
  }
}
```

The local sync cache is persisted under:

```text
/data/jobs/dataset_sync
```

Because `docker-compose.local.yml` mounts `./data/jobs` to `/data/jobs`, synced local dataset blocks survive container restarts.
