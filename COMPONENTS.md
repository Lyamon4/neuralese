# Component provenance

This repository vendors clean snapshots from the following Neuralese repositories. Nested Git metadata and untracked local files are intentionally excluded so the hackathon repository can be cloned as one project.

| Destination | Source repository | Branch | Commit |
| --- | --- | --- | --- |
| `apps/builder` | `hex358/neuralese-builder` | `main` | `600bbf5063fb676a1ee76c61658601925b3aceaa` |
| `apps/block-editor` | `Lyamon4/neuralese-block-editor` | `main` | `d4785997ed75fce4ec84ddf584c2bc8803095542` |
| `services/api` | `hex358/neuralese-api` | `master` | `8469bea3419577b2787a17fd01a7ab98f95f91d8` |
| `services/backend` | `hex358/neuralese-backend` | `main` | `6b8a32f0967f29c6c5f886f7c0f845f1d0cf6075` |
| `services/landing` | `hex358/neuralese-landing` | `main` | `8b12c230f6bc1d69ea4c148dded15270a99cb980` |
| `runtime/onnx-training` | `Lyamon4/neuralese-onnx` | `main` | `9f9a6b67ed8f6d4573d6b9e8e2fb2bce8bc73682` |
| `installer/setup` | `hex358/neuralese-setup` | `main` | `6ba0d31522b166eaae095ab087e4a9c3cc8fa78e` |

## Snapshot policy

- Source files are taken from each repository's default branch at the commit above.
- Generated dependency directories such as `node_modules`, virtual environments, and nested `.git` directories are not included.
- Files already tracked by a source repository remain in the snapshot, including research assets and native runtime dependencies, except runtime databases that may contain local account/chat state.
- The root `dist/` artifacts are release copies and are independently checksummed.
- Updating a component requires recording its new source commit here in the same commit as the snapshot change.

## Consolidation patches

The monorepo applies narrowly scoped integration fixes after snapshotting:

- `services/api/api/userdata.db` is intentionally excluded because it is runtime state, not source, and contains local account/chat records.
- `services/landing/src/i18n/context.tsx` imports the `ReactNode` type directly instead of referencing the unavailable global `React` namespace. No runtime behavior is changed.
- `apps/builder/README.md` documents the actual Godot 4.7, clean-backend port `8081`, FullyLocal, and bundled GDExtension configuration.
- `apps/builder/addons/yaml/yaml.gdextension` points macOS directly at the tracked `.dylib` files instead of untracked local symlink names, making a clean clone load the YAML extension.
- `apps/block-editor/scripts/build-syntax-compiler.mjs` auto-detects the sibling `apps/builder` checkout in this monorepo; its README now uses portable syntax-parity commands.
- `services/backend/README.md` replaces a machine-specific launcher path with direct virtual-environment and `python app.py` instructions.
- `runtime/onnx-training/README.md` replaces machine-specific native commands with repository-relative Linux instructions and directs macOS users to Docker.
