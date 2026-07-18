# FullyLocal Builtin Datasets

The Godot frontend advertises these builtin dataset identifiers for the FullyLocal MVP:

- `mnist`
- `iris`
- `titanic`
- `car_track`

Each dataset directory must contain either:

- `train.npz` with arrays `x` and `y`, plus optional `val_x` / `val_y` or `test_x` / `test_y`
- or `train_x.npy` and `train_y.npy`, plus optional `val_x.npy` / `val_y.npy` or `test_x.npy` / `test_y.npy`

Arrays are consumed directly by `local_runtime/neuralese_local/dataset_store.py`.

User-created Godot datasets do not live in this directory. When FullyLocal training starts, `scripts/run_manager.gd` converts the raw in-memory dataset table from `glob.dataset_datas[name]` into a temporary uncompressed `godot_json` dataset inside the job directory, then the Python trainer loads it through `load_godot_json_dataset()`.

`mnist`, `iris`, and `titanic` can be materialized with `python local_runtime/tools/build_builtin_datasets.py`.

`car_track` was converted from Neuralese's legacy single-file LMDB `.ds` dataset format into `local_runtime/datasets/car_track/train.npz`. The conversion reader lives in `local_runtime/neuralese_local/legacy_ds.py`; use it when refreshing the dataset from canonical `.ds` files.
