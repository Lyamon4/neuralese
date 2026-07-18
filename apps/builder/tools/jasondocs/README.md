# JasonDocs CLI

Static-analysis powered documentation tooling for Neuralese graph nodes.

Run from the repo root:

```powershell
python -m tools.jasondocs scan
python -m tools.jasondocs sync
python -m tools.jasondocs report
python -m tools.jasondocs validate
python -m tools.jasondocs build
python -m tools.jasondocs combos --max-nodes 8
```

The CLI owns generated technical metadata under each `JasonDocs/<node_id>/node.json` and preserves the `docs` section for authors.

## Commands

- `scan`: inspect active `graph_types` nodes without writing files.
- `sync`: create/update `JasonDocs` node directories, generated metadata, schema, and icons.
- `report`: list missing prose and translation TODOs.
- `validate`: fail if JasonDocs is stale or missing required trilingual prose.
- `build`: generate full Markdown, compact Markdown, assets, and manifests from JasonDocs only.

## Authoring Rule

Authors write only the `docs` section:

- `title`
- `summary`
- `operation`
- per-port descriptions
- per-setting descriptions
- `compact.body`
- optional examples and curated `connects_to` notes

Fields under `generated` are overwritten by `sync`.


## Network Combinatorics

`combos` reads only `JasonDocs` and treats each `generated.static_compatible_nodes` entry as one exact port-level transition. Unbounded Neuralese chains can be infinite when compatible nodes form cycles, so the command reports that fact and then gives exact bounded counts for chains up to `--max-nodes`.

Useful examples:

```powershell
python -m tools.jasondocs combos --max-nodes 8
python -m tools.jasondocs combos --start input,input_1d --end classifier,train_input,train_rl --max-nodes 8
python -m tools.jasondocs combos --start input --end classifier --max-nodes 5 --enumerate docs/generated/combos_input_classifier.jsonl --limit 20
```

The counts are exact arbitrary-precision Python integers. They are intentionally bounded because repeated compatible nodes make the complete unbounded search space infinite.