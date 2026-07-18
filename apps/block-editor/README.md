# Neuralese Teacher Tutorial Block Editor

Standalone web editor for building Neuralese tutorial bundles with visual blocks instead of hand-written YAML.

## Run locally

```bash
npm ci
npm run dev
```

Open:

```text
http://127.0.0.1:5175/
```

## Checks

```bash
npm run test -- --run
npm run build
npm run e2e
```

## What it exports

The editor exports a ZIP lesson bundle compatible with the existing Neuralese lesson bundle shape. Block definitions and YAML mappings are schema-driven from JSON files under `src/schema/`.

Each lesson contains one protected main-flow root. Every optional branch is a separate named root block, matching Neuralese's `flow` plus `branches` YAML structure. Orphan top-level actions cannot be exported.

## Languages

Lesson titles, questions, options, and explanation text support Unicode, so teachers can write in Russian, English, or another language. The current Neuralese `YAMLComp` format has no language-switching metadata; separate localized versions should therefore be exported as separate lessons or bundles.

## Syntax coverage

The schema covers every action and requirement registered in `scripts/dsl_registry.gd`, including timed explanations, questions and branches, multi-node creation, topology/config checks, grouped highlights, confetti targets, arrows, selection, deletion locks, and events.

## Generated syntax-parity test

Run the editor's emitted YAML through the current Neuralese Godot compiler:

```bash
# From apps/block-editor in the consolidated Neuralese repository.
# The sibling ../builder checkout is detected automatically.
GODOT_BIN="/path/to/Godot" npm run test:syntax-parity
```

Windows PowerShell example:

```powershell
$env:GODOT_BIN="C:\path\to\godot.exe"
npm run test:syntax-parity
```

Outside the consolidated repository, set `NEURALESE_ENGINE_DIR` to a Neuralese Builder checkout. The parity workflow runs locally and does not require repository tokens or remote engine access.

The command performs the complete contract test:

```text
tutorialBlocks.schema.json
  -> generated block AST variants
  -> production astToTutorialBundle()
  -> production YAML exporter
  -> isolated Godot compiler project
  -> copied current yaml_comp.gd / dsl_compile.gd / dsl_registry.gd
  -> current YAML addon
  -> YAMLComp.compile_bundle()
```

No block fixtures or compiler snapshots are maintained by hand. Cases cover every block type, compatible nested-block type, enum value, boolean value, conditional field path, topology dependencies, branches, persistent steps, and one all-actions sequence. The generator uses bounded structural and field-partition coverage rather than an infeasible Cartesian product.

The isolated project is rebuilt on every run under `generated_syntax_parity/compiler_project/`. It auto-generates the dummy `DSLRuntime` API from `runtime.*` references in the copied registry. The build fails if the real compiler starts calling graph-runtime methods, preventing a shallow stub from silently reducing validation.

Outputs:

- `generated_syntax_parity/godot_compile_report.json` — machine-readable pass/fail cases.
- `generated_syntax_parity/godot-engine.log` — complete Godot engine log and backtraces.
- `generated_syntax_parity/godot-process-trace.log` — commands, exit states, stdout, and stderr.
- `generated_syntax_parity/compiler_project/source_manifest.json` — engine commit, dirty state, copied-source hashes, and generated adapters.

To build only the isolated project:

```bash
npm run build:syntax-compiler
```

To export a standalone Windows compiler executable:

```bash
npm run export:syntax-compiler
```

Standalone export requires Godot export templates matching `GODOT_BIN`. The resulting executable is written under `generated_syntax_parity/compiler_project/bin/`.
