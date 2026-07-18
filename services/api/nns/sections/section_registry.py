from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any, Dict, List, Tuple, Optional, Set
from collections import defaultdict
import io
import time
import json
import hashlib
import torch

from .module_cache import persist_binary, get_persisted_binary # must provide persist_binary(topo,key,binary), get_persisted_binary(topo,key)


# --------- keys ---------

@dataclass(frozen=True)
class RoughTopoKey:
	layers: Tuple[str, ...]  # ("conv2d","dense","dense")

	def as_storage_key(self) -> str:
		return "|".join(self.layers)


@dataclass(frozen=True)
class SectionKey:
	"""
	Exact key must include dataset stamp and per-layer param shapes.
	We explicitly do NOT hash the whole graph. This key is only about this section.
	"""
	dataset_stamp: str
	rough: RoughTopoKey
	layer_param_shapes: Tuple[Tuple[int, ...], ...]  # e.g. ((16,1,3,3),(120,400),(10,120))
	layer_kinds: Tuple[str, ...]                     # mirrors rough.layers (but keep explicit)
	version: int = 1

	def as_storage_key(self) -> str:
		obj = {
			"v": self.version,
			"ds": self.dataset_stamp,
			"rough": self.rough.layers,
			"kinds": self.layer_kinds,
			"shapes": self.layer_param_shapes,
		}
		s = json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
		return hashlib.sha256(s.encode("utf-8")).hexdigest()[:32]


# --------- section payload ---------

@dataclass
class Section:
	key: SectionKey

	# Ordered list of per-layer state_dicts (only parameters/buffers)
	# aligned with plan.param_nids order
	layer_states: List[Dict[str, torch.Tensor]] = field(default_factory=list)

	# accounting
	refcount: int = 0
	user_ids: Set[str] = field(default_factory=set)
	max_acc: float = 0.0
	created_ts: float = field(default_factory=time.time)

	def bump(self, *, user_id: str, acc: float) -> None:
		self.refcount += 1
		self.user_ids.add(str(user_id))
		if acc > self.max_acc:
			self.max_acc = float(acc)


# --------- RAM buckets ---------
# topo_str -> exact_key -> Section
RAM_SECTIONS: Dict[str, Dict[str, Section]] = defaultdict(dict)


# --------- serialization ---------

def _serialize_section(sec: Section) -> bytes:
	buf = io.BytesIO()
	payload = {
		"key": {
			"dataset_stamp": sec.key.dataset_stamp,
			"rough": sec.key.rough.layers,
			"layer_kinds": sec.key.layer_kinds,
			"layer_param_shapes": sec.key.layer_param_shapes,
			"version": sec.key.version,
			"storage_key": sec.key.as_storage_key(),
		},
		"layer_states": sec.layer_states,
		"refcount": sec.refcount,
		"user_ids": list(sec.user_ids),
		"max_acc": sec.max_acc,
		"created_ts": sec.created_ts,
	}
	torch.save(payload, buf)
	return buf.getvalue()


def _deserialize_section(data: bytes) -> Section:
	buf = io.BytesIO(data)
	payload = torch.load(buf, map_location="cpu")

	k = payload["key"]
	rough = RoughTopoKey(tuple(k["rough"]))
	key = SectionKey(
		dataset_stamp=str(k["dataset_stamp"]),
		rough=rough,
		layer_param_shapes=tuple(tuple(x) for x in k["layer_param_shapes"]),
		layer_kinds=tuple(k["layer_kinds"]),
		version=int(k.get("version", 1)),
	)

	sec = Section(
		key=key,
		layer_states=list(payload.get("layer_states") or []),
		refcount=int(payload.get("refcount", 0)),
		user_ids=set(payload.get("user_ids") or []),
		max_acc=float(payload.get("max_acc", 0.0)),
		created_ts=float(payload.get("created_ts", time.time())),
	)
	return sec


# --------- storage API ---------

def get_persisted_section(topo: RoughTopoKey, key: SectionKey) -> Optional[Section]:
	topo_s = topo.as_storage_key()
	key_s = key.as_storage_key()
	bin_ = get_persisted_binary(topo_s, key_s)
	if not bin_:
		return None
	try:
		return _deserialize_section(bin_)
	except Exception:
		return None


def persist_section(sec: Section) -> None:
	topo_s = sec.key.rough.as_storage_key()
	key_s = sec.key.as_storage_key()
	bin_ = _serialize_section(sec)
	persist_binary(topo_s, key_s, bin_)


# --------- building section from ctx ---------

def _layer_param_shape_from_state(sd: Dict[str, torch.Tensor]) -> Tuple[int, ...]:
	"""
	We define layer param shape by weight tensor shape (most discriminative).
	- Linear: weight [out,in]
	- Conv2d: weight [out,in,kh,kw]
	"""
	w = sd.get("weight")
	if isinstance(w, torch.Tensor):
		return tuple(int(x) for x in w.shape)
	# fallback: first tensor in sd
	for v in sd.values():
		if isinstance(v, torch.Tensor):
			return tuple(int(x) for x in v.shape)
	return ()


def build_section_key(
	*,
	dataset_stamp: str,
	rough_layers: Tuple[str, ...],
	layer_states: List[Dict[str, torch.Tensor]],
) -> SectionKey:
	shapes = tuple(_layer_param_shape_from_state(sd) for sd in layer_states)
	return SectionKey(
		dataset_stamp=str(dataset_stamp),
		rough=RoughTopoKey(tuple(rough_layers)),
		layer_param_shapes=shapes,
		layer_kinds=tuple(rough_layers),
		version=1,
	)


def build_section_from_ctx(
	*,
	ctx,
	plan_param_nids: Tuple[str, ...],
	rough_layers: Tuple[str, ...],
	dataset_stamp: str,
) -> Optional[Section]:
	"""
	Requires ctx.extra["_module_key_by_nid"] to exist (we will add it in model_core).
	"""
	key_map = (ctx.extra.get("_module_key_by_nid") or {})
	mod_cache = ctx.extra.get("_torch_modules") or ctx.extra.get("_modules")  # depends on your impl
	if mod_cache is None:
		# fallback: use nns.optim._modules(ctx) via ctx.extra
		mod_cache = ctx.extra.get("_torch_ops")  # not correct but keep safe
	modules = ctx.extra.get("_torch_modules_cache")  # if you have it
	# Real modules live in optim._modules(ctx); registry can't import optim to avoid cycles.
	# So we rely on ctx.extra injection we will do in model_core: ctx.extra["_modules_ref"] = _modules(ctx)
	modules = ctx.extra.get("_modules_ref")

	if not isinstance(modules, dict):
		return None

	layer_states: List[Dict[str, torch.Tensor]] = []
	for nid in plan_param_nids:
		mkey = key_map.get(str(nid))
		if not mkey:
			return None
		m = modules.get(mkey)
		if m is None or not hasattr(m, "state_dict"):
			return None
		sd = m.state_dict()
		# clone to CPU to decouple from current device
		cpu_sd = {}
		for k, v in sd.items():
			if isinstance(v, torch.Tensor):
				cpu_sd[k] = v.detach().to("cpu").clone()
			else:
				cpu_sd[k] = v
		layer_states.append(cpu_sd)

	sec_key = build_section_key(
		dataset_stamp=dataset_stamp,
		rough_layers=rough_layers,
		layer_states=layer_states,
	)
	return Section(key=sec_key, layer_states=layer_states)


# --------- matching / applying reuse ---------

def _topo_bucket(topo: RoughTopoKey) -> Dict[str, Section]:
	return RAM_SECTIONS[topo.as_storage_key()]


def match_best_section(*, dataset_stamp, rough_layers, layer_states_shape_only):
	print(
		f"\n[SECTIONS][REUSE] match_best_section "
		f"dataset={dataset_stamp} rough={rough_layers}"
	)

	rough = RoughTopoKey(tuple(rough_layers))
	full_key = build_section_key(
		dataset_stamp=dataset_stamp,
		rough_layers=rough_layers,
		layer_states=layer_states_shape_only,
	)

	print(f"[SECTIONS][REUSE] exact key={full_key.as_storage_key()}")

	got = get_persisted_section(rough, full_key)
	if got:
		print("[SECTIONS][REUSE] HIT: persisted exact")
		return got

	bucket = _topo_bucket(rough)
	got = bucket.get(full_key.as_storage_key())
	if got:
		print("[SECTIONS][REUSE] HIT: RAM exact")
		return got

	for L in range(len(rough_layers) - 1, 0, -1):
		prefix_layers = rough_layers[:L]
		prefix_states = layer_states_shape_only[:L]
		prefix_rough = RoughTopoKey(tuple(prefix_layers))
		prefix_key = build_section_key(
			dataset_stamp=dataset_stamp,
			rough_layers=tuple(prefix_layers),
			layer_states=prefix_states,
		)

		print(
			f"[SECTIONS][REUSE] try prefix L={L} key={prefix_key.as_storage_key()}"
		)

		got = get_persisted_section(prefix_rough, prefix_key)
		if got:
			print("[SECTIONS][REUSE] HIT: persisted prefix")
			return got

		bucket = _topo_bucket(prefix_rough)
		got = bucket.get(prefix_key.as_storage_key())
		if got:
			print("[SECTIONS][REUSE] HIT: RAM prefix")
			return got

	print("[SECTIONS][REUSE] MISS")
	return None


from .section_adaptation import adapt_state_dict

def apply_section_to_ctx_modules(*, ctx, plan_param_nids, sec):
	print(
		f"[SECTIONS][APPLY] applying section "
		f"layers={len(sec.layer_states)}"
	)

	key_map = ctx.extra.get("_module_key_by_nid") or {}
	modules = ctx.extra.get("_modules_ref")
	if not isinstance(modules, dict):
		print("[SECTIONS][APPLY] modules map missing")
		return 0

	applied = 0
	for i, nid in enumerate(plan_param_nids):
		if i >= len(sec.layer_states):
			break

		mkey = key_map.get(str(nid))
		if not mkey:
			print(f"[SECTIONS][APPLY] no module key for nid={nid}")
			break

		m = modules.get(mkey)
		if m is None:
			print(f"[SECTIONS][APPLY] module missing for key={mkey}")
			break

		try:
			m.load_state_dict(sec.layer_states[i], strict=True)
			print(f"[SECTIONS][APPLY] loaded layer nid={nid}")
			applied += 1
		except Exception as e:
			print(
				f"[SECTIONS][APPLY][ERROR] load failed nid={nid} err={e}"
			)
			break

	print(f"[SECTIONS][APPLY] total applied={applied}")
	return applied



# --------- registration / persistence ---------

def register_built_sections(*, ctx, graph, dataset_stamp, user_id, acc, plans):
	print(
		f"\n[SECTIONS][REGISTER] register_built_sections "
		f"user={user_id} dataset={dataset_stamp} acc={acc}"
	)

	if ctx.extra.get("_sections_local_dataset", False):
		print("[SECTIONS][REGISTER] skipped: local dataset")
		return

	for plan in plans:
		print(
			f"[SECTIONS][REGISTER] plan rough={plan.rough_layers} "
			f"nids={plan.param_nids}"
		)

		sec = build_section_from_ctx(
			ctx=ctx,
			plan_param_nids=plan.param_nids,
			rough_layers=plan.rough_layers,
			dataset_stamp=dataset_stamp,
		)

		if sec is None:
			print("[SECTIONS][REGISTER] build_section_from_ctx → None")
			continue

		topo = sec.key.rough
		exact = sec.key.as_storage_key()
		bucket = _topo_bucket(topo)

		existing = bucket.get(exact)
		if existing is None:
			print(f"[SECTIONS][RAM] new section key={exact}")
			sec.bump(user_id=user_id, acc=acc)
			bucket[exact] = sec
			existing = sec
		else:
			print(f"[SECTIONS][RAM] update section key={exact}")
			existing.bump(user_id=user_id, acc=acc)

		print(
			f"[SECTIONS][RAM] refcount={existing.refcount} "
			f"users={existing.user_ids} "
			f"max_acc={existing.max_acc}"
		)

		if len(existing.user_ids) >= 2 and existing.max_acc >= 0.80:
			print(f"[SECTIONS][DISK] persist section key={exact}")
			persist_section(existing)
		else:
			print("[SECTIONS][DISK] persist conditions NOT met")



def match_and_apply_reuse_after_build(
	*,
	ctx,
	plans: List[Any],          # SectionPlan list
	dataset_stamp: str,
) -> int:
	"""
	Call ONLY after modules are built (so we can compute exact key shapes).
	Disk-first match, then apply weights into existing modules.
	Returns total layers applied across all sections.
	"""
	if not dataset_stamp:
		return 0
	if ctx.extra.get("_sections_local_dataset", False):
		return 0

	total = 0

	for plan in plans:
		# build "shape-only" layer states by reading current module shapes (state_dict)
		key_map = (ctx.extra.get("_module_key_by_nid") or {})
		modules = ctx.extra.get("_modules_ref")
		if not isinstance(modules, dict):
			continue

		layer_states_shape_only: List[Dict[str, torch.Tensor]] = []
		ok = True
		for nid in plan.param_nids:
			mkey = key_map.get(str(nid))
			if not mkey:
				ok = False
				break
			m = modules.get(mkey)
			if m is None or not hasattr(m, "state_dict"):
				ok = False
				break
			sd = m.state_dict()
			# keep only weight shape definition; still store tensors for key construction
			layer_states_shape_only.append(sd)

		if not ok or not layer_states_shape_only:
			continue

		best = match_best_section(
			dataset_stamp=dataset_stamp,
			rough_layers=plan.rough_layers,
			layer_states_shape_only=layer_states_shape_only,
		)
		if best is None:
			continue

		applied = apply_section_to_ctx_modules(
			ctx=ctx,
			plan_param_nids=plan.param_nids,
			sec=best,
		)
		total += applied

	return total
