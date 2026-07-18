# Neuralese Executable Export Cores

This directory stores precompiled Rust Yolk runner cores used by
`local_runtime/neuralese_local/export_yolk.py`.

The exported executable is produced by byte concatenation:

```text
[runner core][onnx bytes][manifest json][meta_len:u64][model_len:u64][magic]
```

The runner opens its own executable file, reads the appended ONNX model into
memory, consumes JSON arrays from stdin, and prints stringified output arrays to
stdout.

Current checked-in core:

- `windows-x64/neuralese_yolk_runner.exe`

Linux export requires a matching `linux-x64/neuralese_yolk_runner` built from
`local_runtime/yolk_runner_proto`. The old legacy `yolk_linux_gnu` binary uses a
different footer/stdout contract and must not be used here.
