# Neuralese On-Prem Runtime

This is the first implementation slice for the on-prem ONNX training runtime.

Current state:

- embeddable training core package;
- ONNX bundle parser and validation;
- training job state machine;
- WebSocket event model;
- snapshot zip packaging;
- FastAPI app factory;
- runtime app builder for `uvicorn`;
- CLI entrypoint for local school and cloud-node modes;
- Docker deployment package for school/on-prem launch;
- local school / cloud node launch profiles;
- optional auth token protection for HTTP API and WebSocket routes;
- ONNX Runtime Training adapter for uploaded ONNX bundles;
- retention cleanup for old terminal jobs and orphaned workspaces;
- dummy ONNX bundle generator;
- end-to-end upload/WebSocket/snapshot smoke test;
- server-side public dataset refs backed by `.npz` dataset cache;
- local dataset refs backed by persistent incremental sync cache and packet decompression;
- minimal dashboard served from `/` with runtime, capacity, dataset cache, jobs, and snapshots;
- actionable trainer validation errors for common bad bundle cases;
- tests for the implemented core behavior.

Not implemented yet:

- broad ONNX model compatibility beyond the first supported classification path.

## Local setup

```bash
cd /Users/alim/Documents/neuralese
source .venv-onprem/bin/activate
python -m pytest tests/onprem_runtime -v
```

Run the current server shell:

```bash
python -m onprem_runtime --mode local_school --host 127.0.0.1 --port 8010
```

Protected local run:

```bash
python -m onprem_runtime \
  --mode local_school \
  --host 127.0.0.1 \
  --port 8010 \
  --auth-token school-secret
```

Open:

```text
http://127.0.0.1:8010/
```

The dashboard and API routes are available now. The default server app uses `OrtBundleTrainer`, which trains supported ONNX bundles through ONNX Runtime Training and returns a strict snapshot zip with `inference.onnx` and `metrics.jsonl`.

When `NEURALESE_AUTH_TOKEN` or `--auth-token` is set, protected HTTP routes require one of:

```text
Authorization: Bearer <token>
X-Neuralese-Token: <token>
```

Protected WebSocket routes accept `?token=<token>` or the same HTTP headers during the handshake. `/api/health` and dashboard static files stay public so load balancers and local users can still reach the node.

Create a tiny demo bundle:

```bash
python -m onprem_runtime.examples.make_dummy_bundle /tmp/neuralese_dummy_bundle.zip --epochs 2
```

Then upload `/tmp/neuralese_dummy_bundle.zip` through the dashboard or `POST /api/jobs`.

Create a bundle that references a server-side public dataset instead of embedding `data/train.npz`:

```bash
python -m onprem_runtime.examples.make_dummy_bundle \
  /tmp/neuralese_public_ref_bundle.zip \
  --epochs 2 \
  --public-dataset-id iris \
  --no-embedded-dataset
```

The server reads public datasets from `NEURALESE_PUBLIC_DATASET_DIR`, or from `local_runtime/datasets` by default.

Local datasets use the incremental sync WebSocket:

```text
WS /ws/datasets/sync
```

After sync, bundles can reference the cached dataset:

```json
{
  "dataset_ref": {
    "type": "local",
    "id": "local-or",
    "fingerprint": "sha256:..."
  }
}
```

The default server app decompresses the cached local packet and feeds it into ONNX Runtime Training without embedding the dataset in the bundle.

With the default server app, synced local dataset blocks are persisted under:

```text
<NEURALESE_STORAGE_DIR>/dataset_sync
```

That means a school runtime can restart without forcing every local dataset to upload all blocks again.

Run as a cloud worker-style node:

```bash
python -m onprem_runtime \
  --mode cloud_node \
  --host 127.0.0.1 \
  --port 8010 \
  --storage-dir .neuralese_cloud_node \
  --max-parallel-jobs 4
```

The lower-level `uvicorn onprem_runtime.api.server:app ...` form still works when env vars are already configured.

Cleanup old terminal jobs and orphaned workspaces:

```bash
curl -H "Authorization: Bearer school-secret" \
  -X POST "http://127.0.0.1:8010/api/jobs/cleanup?max_age_seconds=604800"
```

## Docker deployment

Deployment files are in:

```text
onprem_runtime/deployment/
```

Local school run:

```bash
cd onprem_runtime/deployment
docker compose -f docker-compose.local.yml up --build
```

The compose file uses `platform: linux/amd64` because `onnxruntime-training-cpu==1.19.2` is available as an amd64 Linux wheel.

Default mounted paths:

```text
./data/jobs     -> /data/jobs
./data/datasets -> /data/datasets
```

Cloud worker-style run uses the same image with env overrides:

```bash
NEURALESE_RUNTIME_MODE=cloud_node \
NEURALESE_MAX_PARALLEL_JOBS=4 \
NEURALESE_AUTH_TOKEN=school-secret \
docker compose -f docker-compose.local.yml up --build
```

Smoke test without Docker:

```bash
python onprem_runtime/deployment/smoke_test.py --launcher local --port 8125
```

Smoke test through Docker:

```bash
python onprem_runtime/deployment/smoke_test.py --launcher docker --port 8010
```

The smoke test creates a dummy bundle, uploads it to the API, waits for WebSocket completion, downloads `snapshot.zip`, and verifies `manifest.json`, `inference.onnx`, and `metrics.jsonl`.

On macOS, this was verified with Docker CLI, Docker Compose, Buildx, and Colima.

## Runtime shape

```text
client/dashboard
      |
      v
onprem_runtime.api
      |
      v
onprem_runtime.core
      |
      v
OrtBundleTrainer
```
