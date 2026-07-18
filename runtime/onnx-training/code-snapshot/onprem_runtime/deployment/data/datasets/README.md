# Public Dataset Directory

Put server-side public datasets here when using `docker-compose.local.yml`.

Required layout:

```text
dataset_id/train.npz
```

`train.npz` must contain:

```text
x
y
```

Optional validation arrays:

```text
val_x
val_y
```

Optional metadata:

```text
dataset_id/meta.json
```

Example:

```text
iris/train.npz
iris/meta.json
```
