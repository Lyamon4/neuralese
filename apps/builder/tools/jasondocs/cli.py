from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

from .godot_static import EnhancedJsonEncoder, GodotStaticAnalyzer
from .jason_docs import report_todos, sync_jasondocs, validate_docs
from .markdown_build import build_markdown
from .network_combinatorics import chain_summary, write_chain_jsonl


def configure_stdio() -> None:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")


def find_repo_root(start: Path) -> Path:
    current = start.resolve()
    if current.is_file():
        current = current.parent
    for candidate in (current, *current.parents):
        if (candidate / "project.godot").exists() and (candidate / "scripts" / "graph_manager.gd").exists():
            return candidate
    raise SystemExit("Could not find Neuralese repo root; pass --repo-root")


def repo_root_from_args(args: argparse.Namespace) -> Path:
    if args.repo_root:
        return Path(args.repo_root).resolve()
    return find_repo_root(Path(__file__))


def docs_root_from_args(args: argparse.Namespace, repo_root: Path) -> Path:
    return (repo_root / args.docs_root).resolve() if not Path(args.docs_root).is_absolute() else Path(args.docs_root)


def out_root_from_args(args: argparse.Namespace, repo_root: Path) -> Path:
    return (repo_root / args.out_root).resolve() if not Path(args.out_root).is_absolute() else Path(args.out_root)


def output_path_from_repo(value: str, repo_root: Path) -> Path:
    path = Path(value)
    return path.resolve() if path.is_absolute() else (repo_root / path).resolve()


def split_node_filters(values: list[str] | None) -> list[str]:
    result: list[str] = []
    for value in values or []:
        result.extend(part.strip() for part in value.split(",") if part.strip())
    return result


def scan_nodes(repo_root: Path):
    analyzer = GodotStaticAnalyzer(repo_root)
    return analyzer.scan()


def cmd_scan(args: argparse.Namespace) -> int:
    repo_root = repo_root_from_args(args)
    nodes = scan_nodes(repo_root)
    if args.format == "json":
        print(json.dumps([node.to_generated() for node in nodes], ensure_ascii=False, indent=2, cls=EnhancedJsonEncoder))
        return 0
    print(f"repo: {repo_root}")
    print(f"active graph nodes: {len(nodes)}")
    for node in nodes:
        title = node.title_candidates.get("en") or node.node_id
        print(
            f"- {node.node_id}: {title}; server={node.server_typename or '-'}; "
            f"script={node.script_path or '-'}; ports={len(node.ports)}; settings={len(node.settings)}"
        )
    return 0


def cmd_sync(args: argparse.Namespace) -> int:
    repo_root = repo_root_from_args(args)
    docs_root = docs_root_from_args(args, repo_root)
    nodes = scan_nodes(repo_root)
    schema_source = Path(__file__).with_name("node.schema.json")
    messages = sync_jasondocs(
        repo_root=repo_root,
        docs_root=docs_root,
        nodes=nodes,
        schema_source=schema_source,
        dry_run=args.dry_run,
    )
    for message in messages:
        print(message)
    if args.dry_run:
        print("dry run: no files written")
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    repo_root = repo_root_from_args(args)
    docs_root = docs_root_from_args(args, repo_root)
    nodes = scan_nodes(repo_root)
    issues = validate_docs(docs_root, nodes, strict_generated=not args.no_strict_generated)
    for issue in issues:
        print(issue.format(), file=sys.stderr if issue.level == "error" else sys.stdout)
    if any(issue.level == "error" for issue in issues):
        return 1
    print("JasonDocs validation passed")
    return 0


def cmd_report(args: argparse.Namespace) -> int:
    repo_root = repo_root_from_args(args)
    docs_root = docs_root_from_args(args, repo_root)
    nodes = scan_nodes(repo_root)
    lines = report_todos(docs_root, nodes)
    if not lines:
        print("No JasonDocs TODOs found")
        return 0
    print("\n".join(lines))
    return 0


def cmd_build(args: argparse.Namespace) -> int:
    repo_root = repo_root_from_args(args)
    docs_root = docs_root_from_args(args, repo_root)
    out_root = out_root_from_args(args, repo_root)
    nodes = scan_nodes(repo_root)
    if not args.skip_validate:
        issues = validate_docs(docs_root, nodes, strict_generated=not args.no_strict_generated)
        errors = [issue for issue in issues if issue.level == "error"]
        if errors:
            for issue in errors:
                print(issue.format(), file=sys.stderr)
            return 1
    messages = build_markdown(docs_root, out_root)
    for message in messages:
        print(message)
    return 0


def cmd_combos(args: argparse.Namespace) -> int:
    repo_root = repo_root_from_args(args)
    docs_root = docs_root_from_args(args, repo_root)
    starts = split_node_filters(args.start)
    ends = split_node_filters(args.end)
    try:
        summary = chain_summary(
            docs_root=docs_root,
            min_nodes=args.min_nodes,
            max_nodes=args.max_nodes,
            starts_requested=starts,
            ends_requested=ends,
        )
    except ValueError as exc:
        print(f"combos: {exc}", file=sys.stderr)
        return 2

    if args.format == "json":
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    else:
        print(f"docs: {summary['docs_root']}")
        print(f"nodes: {summary['node_count']}")
        print(f"port-level compatibility edges: {summary['port_level_compatibility_edges']}")
        print(f"unbounded chain count: {summary['unbounded_chain_count']}")
        if summary["cycle_components"]:
            print("cycle components:")
            for component in summary["cycle_components"][:10]:
                print(f"  - {', '.join(component)}")
            if len(summary["cycle_components"]) > 10:
                print(f"  ... {len(summary['cycle_components']) - 10} more")
        print(f"bounded exact chain counts ({summary['min_nodes']}..{summary['max_nodes']} nodes):")
        for length, count in summary["chain_counts_by_nodes"].items():
            print(f"  {length}: {count}")
        print(f"bounded total: {summary['total_chains']}")

    if args.enumerate:
        target = output_path_from_repo(args.enumerate, repo_root)
        try:
            written = write_chain_jsonl(
                docs_root=docs_root,
                target=target,
                min_nodes=args.min_nodes,
                max_nodes=args.max_nodes,
                starts_requested=starts,
                ends_requested=ends,
                limit=args.limit,
            )
        except ValueError as exc:
            print(f"combos: {exc}", file=sys.stderr)
            return 2
        print(f"enumerated {written} chains -> {target}")
    return 0



def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="jasondocs",
        description="Static-analysis powered JasonDocs CLI for Neuralese graph nodes.",
    )
    parser.add_argument("--repo-root", default=None, help="Neuralese repo root. Defaults to auto-discovery.")
    parser.add_argument("--docs-root", default="JasonDocs", help="JasonDocs root, relative to repo root by default.")

    sub = parser.add_subparsers(dest="command", required=True)

    scan = sub.add_parser("scan", help="Inspect active Godot graph nodes without writing files.")
    scan.add_argument("--format", choices=("text", "json"), default="text")
    scan.set_defaults(func=cmd_scan)

    sync = sub.add_parser("sync", help="Create/update JasonDocs node basis from static analysis.")
    sync.add_argument("--dry-run", action="store_true", help="Show intended writes without changing files.")
    sync.set_defaults(func=cmd_sync)

    validate = sub.add_parser("validate", help="Validate JasonDocs against current Godot node scenes.")
    validate.add_argument("--no-strict-generated", action="store_true", help="Do not fail on stale generated metadata.")
    validate.set_defaults(func=cmd_validate)

    report = sub.add_parser("report", help="Print author TODOs for missing prose/translations.")
    report.set_defaults(func=cmd_report)

    build = sub.add_parser("build", help="Generate Markdown, compact Markdown, assets, and manifests.")
    build.add_argument("--out-root", default="docs/generated", help="Generated docs output root.")
    build.add_argument("--skip-validate", action="store_true", help="Build even when validation would fail.")
    build.add_argument("--no-strict-generated", action="store_true", help="Do not fail on stale generated metadata.")
    build.set_defaults(func=cmd_build)

    combos = sub.add_parser("combos", help="Count and optionally enumerate bounded compatible node chains.")
    combos.add_argument("--min-nodes", type=int, default=2, help="Minimum node count in a chain.")
    combos.add_argument("--max-nodes", type=int, default=8, help="Maximum node count in a chain.")
    combos.add_argument(
        "--start",
        action="append",
        help="Allowed starting node id. Can be repeated or comma-separated. Defaults to all nodes.",
    )
    combos.add_argument(
        "--end",
        action="append",
        help="Allowed ending node id. Can be repeated or comma-separated. Defaults to all nodes.",
    )
    combos.add_argument("--format", choices=("text", "json"), default="text")
    combos.add_argument("--enumerate", help="Write concrete bounded chains as JSONL to this path.")
    combos.add_argument("--limit", type=int, default=1000, help="Maximum chains to write with --enumerate.")
    combos.set_defaults(func=cmd_combos)

    return parser


def main(argv: list[str] | None = None) -> int:
    configure_stdio()
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())


