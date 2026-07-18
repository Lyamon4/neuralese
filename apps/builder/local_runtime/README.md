# Neuralese FullyLocal Runtime

This folder contains the Python runtime launched by `scripts/run_manager.gd` when `FullyLocalConfig.TRAINING` is enabled.

The trainer accepts two dataset sources:

- `builtin_numpy`: checked-in numpy datasets under `local_runtime/datasets/<name>/`.
- `godot_json`: a raw, uncompressed JSON export of a user-created Godot dataset written into the local training job directory by `scripts/run_manager.gd`.

The Godot-side RLE/block dataset cache is only for websocket dataset upload. FullyLocal training bypasses it and reads the raw project dataset from `glob.dataset_datas`.

Development setup on Windows:

```powershell
.\local_runtime\setup_local_python.ps1 -Python C:\path\to\python3.11.exe
python .\local_runtime\tools\build_builtin_datasets.py
```

The shipped app should include `local_runtime/python/` with `numpy`, `onnx`, `onnxruntime-training-cpu`, and `lmdb` installed. Godot looks for:

- `res://local_runtime/python/python.exe`
- `res://local_runtime/python/Scripts/python.exe`
- executable-adjacent `local_runtime/python/python.exe`
- executable-adjacent `local_runtime/python/Scripts/python.exe`
- fallback `python` on `PATH`

Progress is written as JSON lines to `user://fullylocal/jobs/<job_id>/progress.jsonl`. Stop requests are sent by creating `user://fullylocal/jobs/<job_id>/stop`.

The legacy Neuralese `.ds` converter for project-specific datasets is `local_runtime/neuralese_local/legacy_ds.py`. It currently backs the checked-in `car_track` numpy dataset.
