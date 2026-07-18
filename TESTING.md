# Submission verification

The following checks were executed against this consolidated snapshot on 2026-07-18. This file distinguishes source/build checks from platform runtime tests so the results are reproducible and not overstated.

## Executed checks

| Component | Command or check | Result |
| --- | --- | --- |
| Root snapshot | `./scripts/verify-submission.sh` | Passed: repository map, SHA-256 hashes, PE type, DMG container, and PDF type |
| Teacher block editor | `npm run test -- --run` | 21 test files, 85 tests passed |
| Teacher block editor | `npm run build` | Production build passed |
| Lesson syntax parity | `npm run test:syntax-parity` with Godot 4.7.1 and `apps/builder` compiler sources | 102/102 generated YAML cases passed the real Godot compiler |
| On-prem runtime | `python -m pytest runtime/onnx-training/code-snapshot/tests/onprem_runtime -q` with the component on `PYTHONPATH` | 95 tests passed |
| Clean backend | Fresh virtual environment, `pip install -r requirements.txt`, then `python smoke_test.py` | `clean backend smoke OK` |
| Landing site | `npm run lint` and `npm run build` | Type check and production build passed |
| Rust/Slint installer | `cargo test` with the actual local payload supplied to the ignored payload path | Build/test command passed; crate currently contains 0 Rust unit tests |
| macOS artifact | `hdiutil verify`, `lipo -archs`, and deep strict `codesign --verify` | Valid DMG; application and bundled native libraries contain `arm64 + x86_64`; ad-hoc signature valid |
| Windows artifact | SHA-256 and `file`/PE inspection | Valid PE32+ GUI x86-64 artifact; runtime execution was not performed in this macOS pass |

## Platform limits

- The macOS application is ad-hoc signed, not Developer ID signed or Apple-notarized.
- The Windows executable and Windows-native installer were not runtime-smoke-tested on Windows during this consolidation pass.
- The legacy full API requires its Windows/CUDA-oriented environment; no CUDA training benchmark was rerun during repository consolidation.
- The on-prem ONNX runtime uses a Linux `amd64` training wheel. Docker is the supported path on macOS.
- Generated dependency/build directories are ignored and are not part of the committed snapshot.

## Re-run the portable checks

```bash
./scripts/verify-submission.sh

cd apps/block-editor
npm ci
npm run test -- --run
npm run build

cd ../../services/landing
npm ci
npm run lint
npm run build
```

Godot syntax parity additionally requires `GODOT_BIN` and `NEURALESE_ENGINE_DIR`; see [`apps/block-editor/README.md`](apps/block-editor/README.md). ONNX tests require the Linux-compatible runtime dependencies described in [`runtime/onnx-training/README.md`](runtime/onnx-training/README.md).
