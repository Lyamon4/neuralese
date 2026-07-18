# Neuralese Dataset Compression Mirror

`dataset_compression_engine.py` is a standard-library-only Python mirror of
`scripts/ds_obj_serialize.gd::compress_blocks`.

It reproduces:

- adaptive rows-per-block selection (`256`, `512`, or `1024`);
- biased 8-, 16-, and 32-bit big-endian integer encoding;
- float quantization with truncation to `0..255`;
- UTF-8 text terminated by a NUL byte per row;
- concatenated raw Godot image bytes;
- adaptive raw/RLE block selection;
- SHA-256 block hashes;
- the complete header and input/output column layout.

Blocks are represented as lowercase hexadecimal strings in Python JSON output.
Those strings correspond exactly to Godot `PackedByteArray` contents.

## Run Python unit tests

From `local_runtime/tools`:

```powershell
..\python\python.exe test_dataset_compression_engine.py -v
```

With a system Python:

```powershell
python test_dataset_compression_engine.py -v
```

## Verify against the real Godot compressor

```powershell
..\python\python.exe verify_dataset_compression_parity.py
```

An alternate Godot executable can be passed as the first argument.

The verifier creates a temporary minimal Godot project, copies the current
production `ds_obj_serialize.gd` into it, and compares Godot and Python output.
It does not start the Neuralese application or modify the production cache.

## Run the Python engine directly

```powershell
python dataset_compression_engine.py dataset_compression_fixture.json
```

Write output and compare it with canonical Godot output:

```powershell
python dataset_compression_engine.py input.json --output python.json --expected godot.json
```

## Optional live comparison

Live comparison is disabled by default. Enable it before launching Neuralese:

```powershell
$env:NEURALESE_DATASET_COMPRESSION_COMPARE = "1"
```

Alternatively, set the Godot project setting:

```text
debug/neuralese/compare_dataset_compression = true
```

When enabled, Neuralese still stores and uses the original Godot compression
result. The debug observer launches Python after compression and prints:

```text
[DatasetCompressionCompare] MATCH dataset='name'
```

or a field-level mismatch report. Disable the environment variable or project
setting to remove all comparison work.

## Scope

This mirrors the RLE/block compression used by `rle_cache` and
`ws_ds_frames`. The separate `.ds` persistence envelope uses Godot Variant
serialization plus Godot ZSTD and is intentionally not reimplemented here.
