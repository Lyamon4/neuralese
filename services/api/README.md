# Neuralese API (Backend)

This repository contains the **Neuralese backend**: a Sanic-based service that powers authentication, project storage, training/inference orchestration, classroom synchronization, AI mentor chat, audio transcription, and model export.

Frontend client repo: https://github.com/hex358/neuralese-builder/

Documentation (Google Docs): https://docs.google.com/document/d/14X1OiqzYf2y7u7MoeVcdXkXFn4Jk1LRs/edit?usp=sharing&ouid=110125251749853102144&rtpof=true&sd=true

---

## What this backend does

At a high level, the backend provides:

- **User and classroom management**
  - Account creation/login.
  - Classroom creation/join and teacher/student coordination endpoints.
- **Project and dataset APIs**
  - Save/load/delete projects.
  - Project list retrieval.
  - Public dataset catalog endpoint (MNIST, Titanic, Iris, car_track).
- **Neural training + inference runtime**
  - WebSocket training and inference sessions.
  - Context lifecycle management (load/save/delete model contexts).
  - ONNX export endpoint.
- **AI mentor integration (Axon)**
  - Chat WebSocket endpoint for multi-message conversations.
  - One-shot ask endpoint.
  - Graph-state hash synchronization for stable AI context.
- **Audio transcription**
  - Batched Whisper transcription endpoint with queueing.
- **Update delivery**
  - Health check, update state endpoint, and executable download stream.

---

## Main architecture

### 1) API server

- Framework: **Sanic**.
- Entrypoint: `app_bp.py` (creates app, binds DB, registers blueprints).
- Blueprints:
  - `routes/auth_bp.py`
  - `routes/project_bp.py`
  - `routes/classroom_bp.py`
  - `routes/trio_bp.py`
  - `routes/chat_bp.py`
  - `routes/audio_bp.py`

### 2) Storage model

Neuralese uses a path-oriented document/blob abstraction backed by RocksDB-style storage wrappers:

- `storage/fs_core.py` – database operations (list, exists, delete, batch_get, etc.)
- `storage/fs_node.py` – `Node` API for hierarchical `.doc` (JSON) and blob files.

This allows a filesystem-like structure under each user (`/{user}/...`) for projects, contexts, chats, datasets, and config.

### 3) Training execution flow

Training/inference tasks are offloaded to worker processes/threads through the pebble-based scheduler:

- API layer submits jobs (`common/trio_exec.py`, route handlers).
- Worker tasks run via:
  - `worker/worker_pebble.py`
  - `worker/trio_tasks.py`
  - `worker/worker_tasks.py`

This keeps HTTP/WebSocket handlers responsive while long-running GPU operations execute asynchronously.

### 4) Neural engine and optimization modules

Core NN logic and optimization components live under `nns/`:

- Graph/model runtime: `nns/model_core.py`, `nns/graph_core.py`
- Export: `nns/onnx_exporter.py`
- **Section Reuse hooks**: `nns/sections/*`
- **Fused SuperGraph / TopoFuse**: `nns/topofuse/*`

These modules implement the backend side of the computational optimization (reuse of similar sections and fused execution across topologically similar workloads).

---

## Core API surfaces (quick map)

### Auth & updates

- `POST /login`
- `POST /create_user`
- `GET /health`
- `GET /check`
- `GET /download`

### Projects and datasets

- `POST /save`
- `POST /project`
- `POST /delete_project`
- `POST /project_list`
- `GET /datasets`
- `POST /reg_dataset`

### Classroom

- Prefixed with `/classroom` (create/join/stream/update flows).

### Training / inference / export

- `WS /ws/train`
- `WS /ws/infer`
- `POST /export`
- `POST /delete_ctx`
- `POST /get_ctxs`

### Axon chat

- `WS /ws/talk`
- `POST /ask_once`
- `POST /get_chat`
- `POST /clear_chat`

### Audio

- `POST /transcribe_file`

---

## Typical runtime flow with Neuralese client

1. User logs in (`/login`).
2. Client loads/saves graph projects (`/project`, `/save`).
3. For training:
   - Client opens `WS /ws/train`.
   - Backend optionally receives local dataset blocks and reconstructs dataset.
   - Backend executes train task in worker runtime.
   - Progress streamed back over WebSocket.
   - Updated model context persisted under user project context blob.
4. User asks Axon for help (`WS /ws/talk`), including graph summary/hash.
5. User exports model (`POST /export`) to ONNX payload.

---

## Local development

### Prerequisites

- Python 3.12+ recommended.
- CUDA-enabled PyTorch environment (for GPU training/transcription paths).
- RocksDB-compatible environment for `rocksdict`.
- Optional: Rust toolchain for local Rust extension builds.

### Install

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Environment variables

Create `.env` as needed. Important keys include:

- `API_KEY` – required for Gemini-based Axon chat (`routes/chat_bp.py`).

### Run

```bash
python app_bp.py
```

Default bind in code is `0.0.0.0:8000`.

---

## Notes for production

- Add request authentication hardening and rate limiting in front of public endpoints.
- Isolate LLM and transcription workloads to dedicated workers/queues for predictable latency.
- Externalize storage path and runtime knobs (`batch_size`, caches, worker pool sizing) into structured config.
- Add endpoint-level integration tests for WebSocket train/infer and chat synchronization.

