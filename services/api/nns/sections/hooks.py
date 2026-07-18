from __future__ import annotations
from typing import Any, Dict, Optional, List
from .partition import partition_graph_into_section_plans
from .section_registry import (
	match_and_apply_reuse_after_build,
	register_built_sections,
)

def prepare_ctx_for_sections(*, ctx, user_id: str, local_dataset: bool) -> None:
	print(
		f"[SECTIONS][HOOK] prepare_ctx_for_sections "
		f"user={user_id} local_dataset={local_dataset}"
	)
	ctx.extra["_sections_user_id"] = str(user_id)
	ctx.extra["_sections_local_dataset"] = bool(local_dataset)


def apply_reuse_after_first_build(*, ctx, graph: Dict[str, Any], dataset_stamp: str) -> int:
	print(
		f"[SECTIONS][HOOK] apply_reuse_after_first_build "
		f"dataset={dataset_stamp}"
	)
	plans = partition_graph_into_section_plans(graph)
	ctx.extra["_sections_plans"] = plans

	applied = match_and_apply_reuse_after_build(
		ctx=ctx,
		plans=plans,
		dataset_stamp=dataset_stamp,
	)
	print(f"[SECTIONS][REUSE] total layers applied = {applied}")
	return applied


def maybe_register_sections_after_training(*, ctx, graph: Dict[str, Any], dataset_stamp: str, acc: float) -> None:
	print(
		f"[SECTIONS][HOOK] maybe_register_sections_after_training "
		f"dataset={dataset_stamp} acc={acc}"
	)

	if not dataset_stamp:
		print("[SECTIONS][REGISTER] skipped: empty dataset_stamp")
		return

	user_id = str(ctx.extra.get("_sections_user_id", "anon"))
	print(f"[SECTIONS][REGISTER] user={user_id}")

	plans = ctx.extra.get("_sections_plans")
	if not plans:
		print("[SECTIONS][REGISTER] plans missing → recompute")
		plans = partition_graph_into_section_plans(graph)
		ctx.extra["_sections_plans"] = plans

	register_built_sections(
		ctx=ctx,
		graph=graph,
		dataset_stamp=dataset_stamp,
		user_id=user_id,
		acc=float(acc),
		plans=plans,
	)


