# Neuralese Clean Backend

This is the cleaned backend target for Neuralese.

It intentionally separates:

- Clerk device handoff and Neuralese JWTs
- storage-backed user profiles and username uniqueness
- Gumroad billing/license bindings
- Python-served Clerk login/signup page at `/auth`
- project save/load/list/delete
- classroom state and SSE events
- dataset metadata listing

It intentionally does not include:

- server-side training
- server-side inference
- server-side ONNX export
- PyTorch runtime
- Trio task execution
- model contexts

Runtime state is stored through `storage/fs_core.py`, not JSON profile files.

## Run

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

On Windows PowerShell, activate the environment with `.\.venv\Scripts\Activate.ps1` and run the same `pip` and `python app.py` commands.

The unified process serves both APIs and the browser auth UI:

```text
http://127.0.0.1:8081
http://127.0.0.1:8081/auth
```

## Identity Model

External auth comes from Clerk. Internally the backend stores data under stable account IDs:

```text
account_id = sha3_224("clerk:user_xxx")
```

Storage layout:

```text
/profiles/{account_id}.doc
/usernames/{username}.doc
/accounts/{account_id}/config.doc
/accounts/{account_id}/projects/{scene_id}/data.scn
/accounts/{account_id}/projects/{scene_id}/meta.doc
/classrooms/{classroom_id}/meta.doc
/classrooms/{classroom_id}/students.doc
/billing/users/{account_id}/entitlement.doc
```

Usernames are display identities only. Classroom ownership and project ownership use stable account IDs.
