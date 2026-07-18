
import io
import os, torch, torch.nn as nn
import time
from typing import Any, Dict, List, Optional
from .graph_core import node, Context, execute_graph, sh_context, gen_context, Context
from .utils import (
	pick_device, pack_tensor, to_tensor,
	layer_tag, inputs_all_from_kind,
	transplant_linear, transplant_conv,
	_partial_load_linear_from_sd, _partial_load_conv2d_from_sd,
	_partial_load_from_sd
)
from .merge import merge_inputs
from .activations import apply_act
from .optim import (
	_modules, _optims, all_params,
	torch_modules_flag_training, set_eval_mode, get_or_make_optim
)
import record.ds_route as lset
import traceback
import numpy as np
import gymnasium
from typing import Callable
from .fuse_op import op_unary, op_cat, op_softmax, op_flatten, op_identity, op_view2d, op_input, op_shape_adapter
from .sections.hooks import apply_reuse_after_first_build


TorchOp = nn.Module

def _torch_ops(ctx: Context) -> Dict[str, TorchOp]:
	return ctx.extra.setdefault("_torch_ops", {})

def register_torch_op(ctx: Context, nid: str, op: nn.Module, *, once: bool = True) -> None:
	if not ctx.extra.get("_register_torch", False):
		return
	ops = _torch_ops(ctx)
	if once and nid in ops:
		return
	ops[nid] = op

def register_fuse_in_ports(ctx: Context, nid: str, ports: List[str]) -> None:
	"""
	Node-driven ordering for multi-port inputs (Concat etc).
	"""
	if not ctx.extra.get("_register_torch", False):
		return
	ctx.extra.setdefault("_fuse_in_ports", {})[nid] = list(ports)

def apply_activation(y: torch.Tensor, act: str | None) -> torch.Tensor:
	if not act:
		return y
	if act == "relu":
		return torch.relu(y)
	if act == "sigmoid":
		return torch.sigmoid(y)
	if act == "tanh":
		return torch.tanh(y)
	return y


torch.backends.cudnn.benchmark = True
torch.backends.cudnn.deterministic = False
# ----- input node -----
def _ensure_batch(x: torch.Tensor) -> torch.Tensor:
	# [ ] -> [1,1], [F] -> [1,F], [H,W] -> [1,H,W], keep N if already present
	if x.dim() == 0:
		return x.view(1, 1)
	if x.dim() == 1:
		return x.unsqueeze(0)
	if x.dim() == 2:
		return x.unsqueeze(0)
	return x # already has batch


@node("InputNode")
def input_node(inputs: Dict[str, Any], props: Dict[str, Any], ctx: Context) -> Dict[str, Any]:

	device = pick_device(ctx)
	payload = props.get("raw_values", None)
	if payload is None:
		raise ValueError("input payload is empty")
	t = to_tensor(payload, device)

	cfg = props.get("config", {}) or {}
	batch_already = ctx.extra.get("batch_already", False)

	# Read reshape hints (legacy, single-sample flow)
	rows = int(cfg.get("rows", -1))
	cols = int(cfg.get("columns", -1))
	have_rc = (rows != -1) or (cols != -1)

	if batch_already:
		# BEFORE:
		# if t.dim() == 1: t = t.unsqueeze(0)   # => [1, N]  (WRONG for batched scalars)

		# AFTER (critical): (N,) -> (N,1)
		if t.dim() == 0:
			t = t.view(1, 1)
		elif t.dim() == 1:
			t = t.view(-1, 1)  # batch of scalars
		elif t.dim() == 2:
			pass  # [N, F] already OK
		elif t.dim() == 3:
			t = t.unsqueeze(1)

		# keep your optional reshape logic as-is
		if have_rc and (t.dim() == 2 or t.dim() == 3):
			t = reshape_to_2d(t, rows, cols)
	else:
		# Legacy single-sample path
		if have_rc:
			# Ensure batch dim then reshape per-sample
			t = _ensure_batch(t)  # scalar->[1,1], [F]->[1,F], [H,W]->[1,H,W]
			if t.dim() == 3:      # [N,H,W] -> [N,F] before Reshape2D
				N = t.shape[0]
				t = t.contiguous().view(N, -1)
			t = reshape_to_2d(t, rows, cols)
		else:
			t = _ensure_batch(t)

	r = int(t.shape[1]) if (have_rc and t.dim() == 3) else -1
	c = int(t.shape[2]) if (have_rc and t.dim() == 3) else -1
	register_torch_op(ctx, str(props["nid"]), op_input(batch_already, have_rc, r, c))

	pack = pack_tensor(t, "input", None)
	return {"input_out": pack}



def _rebuild_linear(ctx: Context, key: str, in_f: int, out_f: int, bias: bool, device: torch.device) -> nn.Linear:
	cache = _modules(ctx)
	old = cache.get(key)
	layer = nn.Linear(in_f, out_f, bias=bias).to(device)

	if ctx.extra.get("exporting"):
		for param in layer.parameters():
			param.requires_grad_(False)
	else:
		for param in layer.parameters():
			param.requires_grad_(True)

	# prefer restoring from checkpoint; else transplant from old
	ckpt = ctx.extra.get("_ckpt", {}).get(key)
	if isinstance(ckpt, dict):
		_partial_load_from_sd(layer, ckpt, device)
	elif isinstance(old, nn.Linear):
		try: transplant_linear(layer, old)
		except Exception: pass

	cache[key] = layer
	return layer

def _merge_single(inputs: List[Any]) -> torch.Tensor:
	return inputs[0]["tensor"]


def dense_layer(inputs: List[Any], props: Dict[str, Any], ctx: Context) -> Dict[str, Any]:
	device = pick_device(ctx)
	x = _merge_single(inputs)
	if x.dim() > 2:
		x = x.view(x.size(0), -1)

	cfg = props.get("config", {}) or {}
	in_f = x.shape[-1]
	out_f = int(cfg.get("units", props.get("neuron_count", in_f)))
	use_bias = bool(cfg.get("bias", True))
	tag = layer_tag(props, "dense")
	key = f"dense|tag={tag}"

	cache = _modules(ctx)
	layer = cache.get(key)
	if not isinstance(layer, nn.Linear) or layer.in_features != in_f or layer.out_features != out_f:
		layer = _rebuild_linear(ctx, key, in_f, out_f, use_bias, device)

	# ---- register nid → module key (REQUIRED for sections) ----
	ctx.extra.setdefault("_module_key_by_nid", {})[str(props["nid"])] = key

	y = layer(x)
	y = activate(cfg, y)
	register_torch_op(ctx, str(props["nid"]), op_unary(layer, cfg.get("activation")))
	return pack_tensor(y, "dense", layer)




# ----- conv2d -----
def _rebuild_conv(ctx: Context, key: str, in_c: int, out_c: int, k: int, s: int, p: int, bias: bool, device: torch.device) -> nn.Conv2d:
	cache = _modules(ctx)
	old = cache.get(key)
	layer = nn.Conv2d(in_c, out_c, kernel_size=k, stride=s, padding="same", bias=bias).to(device)

	if ctx.extra.get("exporting"):
		for param in layer.parameters():
			param.requires_grad_(False)
	else:
		for param in layer.parameters():
			param.requires_grad_(True)


	ckpt = ctx.extra.get("_ckpt", {}).get(key)
	if isinstance(ckpt, dict):
		_partial_load_from_sd(layer, ckpt, device)
	elif isinstance(old, nn.Conv2d):
		try: transplant_conv(layer, old)
		except Exception: pass

	cache[key] = layer
	return layer

import torch.nn.functional
def activate(cfg, y):
	match cfg.get("activation", "none"):
		case "relu":
			return torch.relu(y)
		case "tanh":
			return torch.tanh(y)
		case "sigmoid":
			return torch.sigmoid(y)
		case "gelu":
			return torch.nn.functional.gelu(y)
	return y

def _ensure_nchw(x: torch.Tensor) -> torch.Tensor:
	if x.dim() == 3:
		return x.unsqueeze(1)  # [N,1,H,W]
	if x.dim() == 4:
		return x
	raise ValueError(f"Conv2D expects 3D or 4D tensor, got {tuple(x.shape)}")


def conv2d_layer(inputs: List[Any], props: Dict[str, Any], ctx: Context) -> Dict[str, Any]:
	device = pick_device(ctx)

	x = _merge_single(inputs)
	x_nchw = _ensure_nchw(x)

	in_ch = int(x_nchw.shape[1])

	cfg = props.get("config", {}) or {}
	k = int(cfg.get("window", 3))
	step = 1 #int(cfg.get("stride", 1))
	p = (k // 2) if cfg.get("keep_size", True) else 0
	out_ch = int(cfg.get("filters", props.get("neuron_count", 16)))
	use_bias = True

	tag = layer_tag(props, "conv2d")
	key = f"conv2d|tag={tag}"

	cache = _modules(ctx)
	layer = cache.get(key)

	# ---- CRITICAL FIX: always rebuild through _rebuild_conv ----
	if (
		not isinstance(layer, nn.Conv2d)
		or layer.in_channels != in_ch
		or layer.out_channels != out_ch
		or tuple(layer.kernel_size) != (k, k)
		or tuple(layer.stride) != (step, step)
	):
		layer = _rebuild_conv(
			ctx,
			key,
			in_c=in_ch,
			out_c=out_ch,
			k=k,
			s=step,
			p=p,
			bias=use_bias,
			device=device,
		)

	# ---- register nid → module key (REQUIRED for sections) ----
	ctx.extra.setdefault("_module_key_by_nid", {})[str(props["nid"])] = key

	y = layer(x_nchw)
	y = activate(cfg, y)

	register_torch_op(ctx, str(props["nid"]) + "_shape", op_shape_adapter())
	register_torch_op(ctx, str(props["nid"]), op_unary(layer, cfg.get("activation")))

	return pack_tensor(y, "conv2d", layer)




def maxpool2d_layer(inputs: List[Any], props: Dict[str, Any], ctx: Context) -> Dict[str, Any]:
	x = _merge_single(inputs)

	cfg = props.get("config", {}) or {}
	k = int(cfg.get("group", 2))

	cache = _modules(ctx)
	key = f"maxpool2d|k={k}"
	pool = cache.get(key)

	if not isinstance(pool, nn.MaxPool2d) or pool.kernel_size != (k, k):
		pool = nn.MaxPool2d(kernel_size=k, stride=k)
		cache[key] = pool

	# eager: be strict (if it's 3D, user meant [N,H,W] -> add channel)
	if x.dim() == 3:
		x = x.unsqueeze(1)

	y = pool(x)

	register_torch_op(ctx, str(props["nid"]) + "_shape", op_shape_adapter())
	register_torch_op(ctx, str(props["nid"]), op_unary(pool))

	return pack_tensor(y, "maxpool2d", None)




# ----- dropout -----
def dropout_layer(inputs: List[Any], props: Dict[str, Any], ctx: Context) -> Dict[str, Any]:
	device = pick_device(ctx)
	x = _merge_single(inputs)
	cfg = props.get("config", {}) or {}
	p = float(cfg.get("p", 0.5))
	training = bool(cfg.get("training", False))
	key = f"dropout|p={p}"
	cache = _modules(ctx)
	drop = cache.get(key)
	if not isinstance(drop, nn.Dropout) or drop.p != p:
		drop = nn.Dropout(p)
		cache[key] = drop
	drop.train(training)
	y = drop(x)
	register_torch_op(ctx, str(props["nid"]), op_unary(drop))
	return pack_tensor(y, "dropout", None)


# ----- layer router node -----
_LAYER_TABLE = {
	"dense": dense_layer,
	"linear": dense_layer,
	"conv2d": conv2d_layer,
	"convolution2d": conv2d_layer,
	"maxpool2d": maxpool2d_layer,
	"dropout": dropout_layer,
}

@node("NeuronLayer")
def neuron_layer(inputs: Dict[str, Any], props: Dict[str, Any], ctx: Context) -> Dict[str, Any]:
	device = pick_device(ctx)
	cfg = props.get("config", {}) or {}
	lt = str(cfg.get("type", "dense")).lower()
	fn = _LAYER_TABLE.get(lt)
	if fn is None:
		raise ValueError(f"unknown layer type '{lt}', available {list(_LAYER_TABLE.keys())}")
	packs = inputs.get("layer_in", [])
	out = fn(packs, props, ctx)
	return {"layer_out": out}


# ----- softmax node -----
@node("SoftmaxNode")
def softmax_node(inputs, props, ctx):
	device = pick_device(ctx)
	x = merge_inputs(inputs.get("layer_in", []), device)
	got = ctx.extra.get("branch_losses", {})
	if ctx.extra.get("is_training") and (got.get(str(props["nid"]), "") == "cross_entropy"):
		register_torch_op(ctx, str(props["nid"]), op_identity())
		return {"soft_out": pack_tensor(x, "logits", None)}  # bypass
	else:
		y = torch.softmax(x, 1)
		register_torch_op(ctx, str(props["nid"]), op_softmax(1))
		return {"soft_out": pack_tensor(y, "softmax", None)}




# ----- redimension nodes -----
@node("Flatten")
def flatten_layer(inputs: List[Any], props: Dict[str, Any], ctx: Context) -> Dict[str, Any]:
	device = pick_device(ctx)
	x = _merge_single(inputs["layer_in"])
	if x.dim() == 1:
		x = x.unsqueeze(0)
	y = x.view(x.size(0), -1)
	register_torch_op(ctx, str(props["nid"]), op_flatten())
	return {"layer_out": pack_tensor(y, "flatten", None)}

@node("Reshape2D")
def reshape2d_node(inputs: Dict[str, Any], props: Dict[str, Any], ctx: Context) -> Dict[str, Any]:
	device = pick_device(ctx)

	candidates = inputs.get("layer_in", [])
	if not candidates:
		for v in inputs.values():
			if isinstance(v, list):
				candidates.extend(v)
			elif v is not None:
				candidates.append(v)
		if not candidates:
			raise ValueError("Reshape2D: no inputs connected")

	x = merge_inputs(candidates, device)  # [N, F], [N, H, W], or [N, C, H, W]
	cfg = props.get("config", {}) or {}

	rows = int(cfg.get("rows", -1))
	cols = int(cfg.get("columns", -1))

	y = reshape_to_2d(x, rows, cols)
	r = int(y.shape[1]) if y.dim() == 3 else -1
	c = int(y.shape[2]) if y.dim() == 3 else -1
	register_torch_op(ctx, str(props["nid"]), op_view2d(r, c))
	return {"layer_out": pack_tensor(y, "reshape2d", None)}




def _infer_2d_shape(total: int, rows: int, cols: int) -> (int, int):
	# behave like the original version, but infer automatically if product mismatches
	if rows <= 0 and cols <= 0:
		# auto-square if nothing is set
		side = int(total ** 0.5)
		return side, total // side
	if rows > 0 and cols > 0:
		if rows * cols != total:
			# auto-fix by expanding rows
			if total % cols == 0:
				return total // cols, cols
			if total % rows == 0:
				return rows, total // rows
			side = int(total ** 0.5)
			return side, total // side
		return rows, cols
	if rows == -1 and cols > 0:
		return total // cols, cols
	if cols == -1 and rows > 0:
		return rows, total // rows
	raise ValueError(f"Reshape2D: invalid rows={rows}, cols={cols} for total={total}")



def reshape_to_2d(x: torch.Tensor, rows: int, cols: int) -> torch.Tensor:
	if x.dim() == 0:
		x = x.view(1, 1)
	elif x.dim() == 1:
		x = x.unsqueeze(0)

	if x.dim() == 2:
		N, F = x.shape
		r, c = _infer_2d_shape(F, rows, cols)
		return x.contiguous().view(N, r, c)

	if x.dim() == 3:
		t = t.unsqueeze(1)
	if x.dim() == 4:
		return x  # already [N, C, H, W]
	raise ValueError(f"Reshape2D: unsupported input rank {x.dim()}")




# ----- loss + training node -----
def _normalize_ce_targets(y_true: torch.Tensor, y_pred: torch.Tensor) -> torch.Tensor:
	if y_pred.dim() == 1: y_pred = y_pred.unsqueeze(0)
	if y_pred.dim() != 2:
		raise ValueError(f"ce expects logits [N,C], got {tuple(y_pred.shape)}")
	N, C = y_pred.shape
	if y_true.dim() == 0: return y_true.view(1).long()
	if y_true.dim() == 1:
		if y_true.numel() == N: return y_true.long()
		if N == 1 and y_true.numel() == C:
			return y_true.argmax(dim=0, keepdim=True).long()
		raise ValueError("ce 1d target mismatch with batch or one-hot size")
	if y_true.dim() == 2 and y_true.shape == (N,C):
		return y_true.argmax(dim=1).long()
	raise ValueError(f"unsupported ce target shape {tuple(y_true.shape)} for logits {tuple(y_pred.shape)}")

@node("ClassifierNode", pass_through=True)
def classifier(inputs: Dict[str, Any], props: Dict[str, Any], ctx: Context) -> Dict[str, Any]:
	# Placeholder. This node is executed on the client.
	return {}

@node("AugmentTF")
def augment_transform(inputs: Dict[str, Any], props: Dict[str, Any], ctx: Context) -> Dict[str, Any]:
	# TODO
	device = pick_device(ctx)
	candidates = inputs.get("layer_in", [])
	x = merge_inputs(candidates, device)
	# just pass-through for now
	return {"layer_out": pack_tensor(x, "augment_tf", None)}


def adapt_lr_by_grad_norm(
	opt,
	grad_norm: float,
	ctx: Context,
	*,
	base_lr: float = 1e-2,
	min_lr: float = 1e-4,
	smooth: float = 0.9,
):
	"""
	Option A: LR = base_lr * g / (g + c)
	where c is EMA of early gradient norms.
	"""

	# initialize EMA container
	state = ctx.extra.setdefault("_grad_norm_ema", {
		"c": None,
	})

	# initialize c on first steps
	if state["c"] is None:
		state["c"] = grad_norm
	else:
		state["c"] = smooth * state["c"] + (1 - smooth) * grad_norm

	c = max(state["c"], 1e-8)

	# compute adaptive lr
	lr = base_lr * (grad_norm / (grad_norm + c))
	lr = max(lr, min_lr)

	# apply to optimizer
	for group in opt.param_groups:
		group["lr"] = lr

	# optional: diagnostics
	ctx.extra["_last_adaptive_lr"] = lr

def compute_grad_norm(ctx: Context) -> float:
	"""
	Computes global L2 norm of all trainable gradients.
	Architecture-agnostic.
	"""
	total_sq = 0.0
	for p in all_params(ctx):
		if p.grad is None:
			continue
		g = p.grad.detach()
		total_sq += g.pow(2).sum().item()
	return total_sq ** 0.5





@node("TrainInput")
def train_node(inputs: Dict[str, Any], props: Dict[str, Any], ctx: Context) -> Dict[str, Any]:
	if not ctx.extra.get("is_training", "") and "parent" not in ctx.extra:
		return {}
	if "parent" in ctx.extra and not ctx.extra["parent"].extra.get("is_training", ""):
		return {}

	parent_ctx = ctx.extra.get("parent", ctx)
	device = pick_device(ctx)
	cfg = props.get("config", {}) or {}

	run_out = inputs["pred_in"]

	# ---- normalize to (heads, losses)
	if isinstance(run_out, list) and len(run_out) == 2 and isinstance(run_out[1], dict):
		# new shape: [heads, losses]
		heads, losses = run_out
	elif (isinstance(run_out, list) and run_out and
	      isinstance(run_out[0], list) and len(run_out[0]) == 2 and isinstance(run_out[0][1], dict)):
		# legacy shape: [[heads, losses]]
		heads, losses = run_out[0]
	else:
		raise ValueError(f"TrainInput: unexpected pred_in format: {type(run_out)} -> {run_out.__class__.__name__}")

	accs: Dict[str, torch.Tensor] = ctx.extra.get("batch_accuracy", {})

	if not losses:
		res = pack_tensor(torch.tensor(0.0), "train_step", None)
		ctx.extra["train_loss"] = res
		ctx.extra["train_acc"] = pack_tensor(torch.tensor(0.0), "train_acc", None)
		return {}

	total_loss = list(losses.values())[0]
	#print(total_loss)
	total_acc = list(accs.values())[0] if accs else torch.tensor(0.0, device=device)

	if not ctx.extra.get("do_update", True):
		ctx.extra["train_loss"] = pack_tensor(total_loss.detach(), "train_step", None)
		ctx.extra["train_acc"] = pack_tensor(total_acc.detach(), "train_acc", None)
		return {}

	torch_modules_flag_training(parent_ctx, True)
	opt = get_or_make_optim(parent_ctx, cfg)

	if opt is not None and bool(cfg.get("zero_grad", True)):
		opt.zero_grad(set_to_none=True)

	total_loss.backward()
	update_policy_after_backward(parent_ctx)

	max_grad = cfg.get("max_grad_norm")
	if opt is not None:
		if max_grad is not None:
			nn.utils.clip_grad_norm_(all_params(parent_ctx), float(max_grad))
		opt.step()
		parent_ctx.extra["_train_step"] = int(parent_ctx.extra.get("_train_step", 0)) + 1

	ctx.extra["train_loss"] = pack_tensor(total_loss.detach(), "train_step", None)
	ctx.extra["train_acc"] = pack_tensor(total_acc.detach(), "train_acc", None)
	torch_modules_flag_training(parent_ctx, False)
	return {}




def diag_print_gate_stats(ctx: Context, every: int = 50) -> None:
	step = int(ctx.extra.get("_train_step", 0))
	if step % every != 0:
		return
	g = ctx.extra.get("_grad_gate_last_gates")
	if not isinstance(g, torch.Tensor):
		print("[GATE][DIAG] no gates tensor")
		return
	zeros = int((g <= 0.0).sum().item())
	ones = int((g > 0.0).sum().item())
	print(f"[GATE][DIAG] step={step} gates: ones={ones} zeros={zeros}")
	entry = ctx.extra.get("_grad_gate_last_entry")
	diag_print_gate_mapping(entry, g)


def diag_print_gate_mapping(entry, gates):
	print("[GATE MAP]")
	for i, g in enumerate(gates.tolist()):
		if g == 0.0:
			pgs = entry["param_groups"][i]
			if pgs:
				shape = tuple(pgs[0].shape)
				print(f" gated op {i} weight_shape={shape}")

# ----- training orchestration -----
def _best_slot(ctx: Context):
	return ctx.extra.setdefault("_best", {"loss": float("inf"), "state": None, "step": -1})

def _snapshot(ctx: Context):
	return {k: m.state_dict() for k,m in _modules(ctx).items()}

def _restore(ctx: Context, state: Dict[str, Any]):
	if not state: return
	cache = _modules(ctx)
	for k,sd in state.items():
		if k in cache: cache[k].load_state_dict(sd)

def _maybe_update_best(ctx: Context, loss_val: float):
	best = _best_slot(ctx)
	if loss_val < best["loss"]:
		best["loss"] = loss_val
		best["state"] = _snapshot(ctx)
		best["step"] = ctx.extra.get("global_step", 0)

def _batch_iter(iterable, batch_size: int):
    if batch_size == 1:
        # normalize single samples to tensors with float32 targets
        for x, y in iterable:
            yield x, y
        return

    batch_x, batch_y = [], []
    for x, y in iterable:
        batch_x.append(x)
        batch_y.append(y)

        if len(batch_x) == batch_size:
            yield torch.stack(batch_x), torch.stack(batch_y)
            batch_x, batch_y = [], []

    if batch_x:
        yield torch.stack(batch_x), torch.stack(batch_y)



def default_callback(*args):
	pass


@node("Concat")
def concat_node(inputs: Dict[str, Any], props: Dict[str, Any], ctx: Context) -> Dict[str, Any]:
	device = pick_device(ctx)
	cfg = props.get("config", {}) or {}
	order = cfg.get("concat_order", [])
	if not order:
		order = list(inputs.keys())

	tensors = []
	for key in order:
		arr = inputs.get(key)
		if not arr or not isinstance(arr, list):
		    continue
		t: torch.tensor = arr[0].get("tensor")
		if t is None:
		    continue
		tensors.append(t)
	if not tensors:
		raise ValueError("ConcatNode: no valid tensors to concatenate")

	y = torch.cat(tensors, dim=1).to(torch.float32)

	nid = str(props["nid"])
	register_fuse_in_ports(ctx, nid, order)
	# pure-torch op: receives tensors in the same order the fuser gathers them
	register_torch_op(ctx, nid, op_cat(dim=1))

	return {"layer_out": pack_tensor(y, "concat", None)}





from .graph_variations import CompiledGraph
from .fuse_core import build_fused_forward

def _inject_warmup_into_inputnode(main_graph: Dict[str, Any], x_warmup: torch.Tensor) -> None:
	# robust scan: find the node whose type/kind/name is "InputNode"
	pages = (main_graph or {}).get("pages", {}) or {}
	for _pk, page in pages.items():
		if not isinstance(page, dict):
			continue
		for _nid, blob in page.items():
			if not isinstance(blob, dict):
				continue
			nt = str(
				blob.get("type")
				or blob.get("kind")
				or blob.get("node_type")
				or blob.get("name")
				or ""
			)
			if nt == "InputNode":
				blob.setdefault("props", {})["raw_values"] = x_warmup
				return
	raise ValueError("get_or_build_fused_main: InputNode not found to inject raw_values")

def get_or_build_fused_main(main_graph: Dict[str, Any], ctx, *, x_warmup: torch.Tensor, output_nid: str) -> nn.Module:
	cache = ctx.extra.setdefault("_fused_main_cache", {})
	device = pick_device(ctx)

	# IMPORTANT FIX: cache key must include input signature, otherwise you reuse a trace for wrong shapes.
	x_sig = (tuple(x_warmup.shape), str(x_warmup.dtype))
	key = (id(main_graph), str(output_nid), str(device), x_sig, bool(ctx.extra.get("batch_already", False)))
	mod = cache.get(key)
	if mod is not None:
		return mod

	# warmup: inject data into *actual* InputNode, not "first key in dict"
	_inject_warmup_into_inputnode(main_graph, x_warmup)

	# collect per-node ops
	ctx.extra["_torch_ops"] = {}
	ctx.extra["_fuse_in_ports"] = {}
	ctx.extra["_register_torch"] = True
	execute_graph(main_graph, ctx)
	ctx.extra["_register_torch"] = False

	compiled = CompiledGraph(main_graph)

	eager = build_fused_forward(compiled, ctx, output_nid=str(output_nid)).to(device)
	example = (x_warmup.to(device),)

	with torch.no_grad():
		traced = torch.jit.trace(eager, example, strict=False, check_trace=False)

	traced.train(bool(ctx.extra.get("is_training")))
	cache[key] = traced
	return traced





def _fused_cache_key(main_graph: Dict[str, Any], ctx, *, x_warmup: torch.Tensor, output_nid: str):
	device = pick_device(ctx)
	x_sig = (tuple(x_warmup.shape), str(x_warmup.dtype))
	return (id(main_graph), str(output_nid), str(device), x_sig, bool(ctx.extra.get("batch_already", False)))

def get_or_build_fused_main_entry(main_graph: Dict[str, Any], ctx, *, x_warmup: torch.Tensor, output_nid: str) -> Dict[str, Any]:
	"""
	Returns dict entry:
	{
		"traced": ScriptModule,
		"order_len": int,
		"param_groups": List[List[Parameter]],
		"trainable_mask": List[bool],
	}
	"""
	cache = ctx.extra.setdefault("_fused_main_cache", {})
	device = pick_device(ctx)
	key = _fused_cache_key(main_graph, ctx, x_warmup=x_warmup, output_nid=output_nid)
	entry = cache.get(key)
	if isinstance(entry, dict) and entry.get("traced") is not None:
		return entry

	# inject warmup into InputNode
	_inject_warmup_into_inputnode(main_graph, x_warmup)

	# collect per-node ops
	ctx.extra["_torch_ops"] = {}
	ctx.extra["_fuse_in_ports"] = {}
	ctx.extra["_register_torch"] = True
	execute_graph(main_graph, ctx)
	ctx.extra["_register_torch"] = False

	compiled = CompiledGraph(main_graph)
	eager = build_fused_forward(compiled, ctx, output_nid=str(output_nid)).to(device)

	# trace with gates input
	gates_example = torch.ones((len(eager.order),), device=device, dtype=torch.float32)
	example = (x_warmup.to(device), gates_example)

	with torch.no_grad():
		traced = torch.jit.trace(eager, example, strict=False, check_trace=False)

	traced.train(bool(ctx.extra.get("is_training")))

	# meta for per-op grads
	param_groups: List[List[nn.Parameter]] = []
	trainable_mask: List[bool] = []
	for op in eager.ops:
		ps = [p for p in op.parameters() if p.requires_grad]
		param_groups.append(ps)
		trainable_mask.append(len(ps) > 0)

	entry = {
		"traced": traced,
		"order_len": int(len(eager.order)),
		"param_groups": param_groups,
		"trainable_mask": trainable_mask,
	}
	cache[key] = entry
	return entry

def run_fused_main(main_graph: Dict[str, Any], ctx, x: torch.Tensor, *, output_nid: str, grad_gates: torch.Tensor) -> torch.Tensor:
	device = pick_device(ctx)
	x = x.to(device)
	g = grad_gates.to(device=device, dtype=torch.float32)
	entry = get_or_build_fused_main_entry(main_graph, ctx, x_warmup=x, output_nid=output_nid)
	return entry["traced"](x, g)

def run_legacy_main(main_graph: Dict[str, Any], parent: Context, x: torch.Tensor) -> torch.Tensor:
	device = pick_device(parent)

	page0 = main_graph["pages"]["0"]
	first_nid = next(iter(page0.keys()))
	page0[first_nid].setdefault("props", {})["raw_values"] = x

	cache = parent.extra.setdefault("_compiled_main", {})
	graph_id = id(main_graph)
	mod = cache.get(graph_id)

	if mod is None:
		compiled = CompiledGraph(main_graph)
		mod = GraphModule(
			compiled.node_defs,
			compiled.node_types,
			compiled.edges,
			compiled.order,
			parent
		).to(device)
		cache[graph_id] = mod
	else:
		mod = mod.to(device)

	y_pred = mod(x.to(device))
	if isinstance(y_pred, dict) and "tensor" in y_pred:
		y_pred = y_pred["tensor"]

	return y_pred



from .graph_variations import CompiledGraph, GraphModule, extract_graph_structure, topo_sort
@node("RunModel")
def train_run_model(inputs: Dict[str, Any], props: Dict[str, Any], ctx: Context) -> Dict[str, Any]:
	parent = ctx.extra.get("parent")
	if not parent or not parent.extra.get("is_training"):
		return {}

	main_graph = ctx.extra["main_graph"]

	cfg = props.get("config", {}) or {}
	branch_losses: Dict[Any, str] = cfg.get("branch_losses", {}) or {}

	# store for SoftmaxNode bypass etc.
	ctx.extra["branch_losses"] = branch_losses
	parent.extra["branch_losses"] = branch_losses

	device = pick_device(ctx)
	x = ctx.extra["current_x"].to(device)
	y_true = ctx.extra["train_target_tensor"]

	# choose branch/head nid deterministically
	branch_id = next(iter(branch_losses.keys()), "default")
	branch_id_s = str(branch_id)

	# mode: "fused" | "legacy"
	mode =   (cfg.get("forward_mode") or parent.extra.get("forward_mode") or "fused").lower()

	if mode == "legacy":
		y_pred = run_legacy_main(main_graph, parent, x)
	else:
		# fused returns the tensor at branch head nid (e.g. Concat nid)
		entry = get_or_build_fused_main_entry(main_graph, parent, x_warmup=x, output_nid=branch_id_s)

		# Gates for this step
		device2 = pick_device(parent)
		gates = build_grad_gates(parent, entry, device=device2)
		parent.extra["_grad_gate_last_gates"] = gates
		#diag_print_gate_stats(parent, every=2)

		# Run traced forward with gates
		y_pred = entry["traced"](x.to(device2), gates)

	# normalize
	if isinstance(y_pred, dict) and "tensor" in y_pred:
		y_pred = y_pred["tensor"]
	if y_pred.dim() == 1:
		y_pred = y_pred.unsqueeze(0)
	y_pred = y_pred.view(y_pred.shape[0], -1)

	loss_name = (branch_losses.get(branch_id) or branch_losses.get(branch_id_s) or "cross_entropy").lower()

	if "ce" in loss_name or "cross" in loss_name:
		y_true_t = _normalize_ce_targets(to_tensor(y_true, device), y_pred)
		loss_val = nn.CrossEntropyLoss()(y_pred, y_true_t)
		with torch.no_grad():
			acc_val = (y_pred.argmax(dim=1) == y_true_t).float().mean()
	else:
		y_true_t = to_tensor(y_true, device).to(torch.float32)
		if y_true_t.dim() == 1:
			y_true_t = y_true_t.unsqueeze(0)

		err = y_pred - y_true_t

		# residual-normalized MSE
		ema_key = "_mse_residual_ema"
		alpha = 0.85
		stats = parent.extra.get(ema_key)
		with torch.no_grad():
			batch_scale = err.abs().mean(dim=0) * 1.2533141373155001
			if stats is None or stats["scale"].shape != batch_scale.shape:
				stats = {"scale": batch_scale.clamp_min(1e-3)}
			else:
				stats["scale"] = alpha * stats["scale"] + (1 - alpha) * batch_scale
			parent.extra[ema_key] = stats

		scale = stats["scale"].detach()
		loss_val = (err / scale).pow(2).mean()

		# bounded R²-like proxy
		with torch.no_grad():
			vkey = "_mse_target_var_ema"
			vstats = parent.extra.get(vkey)
			batch_var = torch.var(y_true_t, dim=0, unbiased=False)
			if vstats is None or vstats["var"].shape != batch_var.shape:
				vstats = {"var": batch_var.clamp_min(1e-6)}
			else:
				vstats["var"] = alpha * vstats["var"] + (1 - alpha) * batch_var.clamp_min(1e-6)
			parent.extra[vkey] = vstats

			mse = err.pow(2).mean()
			var_y = vstats["var"].mean().clamp_min(1e-6)
			acc_val = torch.clamp(1.0 - mse / var_y, 0.0, 1.0)

	ctx.extra["batch_accuracy"] = {branch_id_s: acc_val}
	parent.extra["batch_accuracy"] = {branch_id_s: acc_val}

	heads = {branch_id_s: {"out": [pack_tensor(y_pred, "logits", None)]}}
	losses = {branch_id_s: loss_val}
	return {"model_out": [heads, losses]}


@node("OutputMap")
def train_output_map(inputs: Dict[str, Any], props: Dict[str, Any], ctx: Context) -> Dict[str, Any]:
	if not ctx.extra["parent"].extra.get("is_training"):
	    return {}
	input = inputs["model_in"][0]

	return {
		"model_out": input,
	}



def _sanitize_heads(pack: Dict) -> Dict:
	result = {}
	vals = pack.values()
	for id in pack:
		for port in pack[id]:
			if isinstance(pack[id][port], list):
				for el in pack[id][port]:
					if "tensor" in el:
						result.setdefault(id, []).append(el["tensor"])
			else:
				el = pack[id][port]
				if "tensor" in el:
					result.setdefault(id, []).append(el["tensor"])
	return result


@node("TrainBegin")
def train_begin_node(inputs: Dict[str, Any], props: Dict[str, Any], ctx: Context) -> Dict[str, Any]:
	#ctx.extra["current_x"]
	return {"input_out": 0.0}


def _run_step(pack: dict, ctx: "Context", x: "torch.Tensor", y: "torch.Tensor", do_update: bool):
	train_graph = pack["train_graph"]
	device = pick_device(ctx)

	cache = ctx.extra.setdefault("_compiled_train", {})
	graph_id = id(train_graph)
	comp = cache.get(graph_id)

	if comp is None:
		comp = CompiledGraph(train_graph)
		cache[graph_id] = comp

	#print(type(x))
	ctx.nested.extra["current_x"] =  x if isinstance(x, torch.Tensor) else torch.from_numpy(x).to(device)
	ctx.nested.extra["main_graph"] = pack["graph"]
	ctx.nested.extra["train_target_tensor"] = y if isinstance(y, torch.Tensor)else torch.from_numpy(y).to(device)
	ctx.nested.extra["do_update"] = do_update

	comp.run(ctx.nested)

	loss_val = ctx.nested.extra["train_loss"]["tensor"].item()
	acc_val = (
		ctx.nested.extra.get("train_acc", {}).get("tensor", torch.tensor(0.6, device=device)).item()
	)
	return loss_val, acc_val



def local_ds_iter(local_ds, batch_size: int):
    if not local_ds or batch_size <= 0:
        return

    total = len(local_ds)
    for i in range(0, total, batch_size):
        batch = local_ds[i : i + batch_size]

        x_list = [pair[0] for pair in batch]
        y_list = [pair[1] for pair in batch]

        # Ensure (N,1) not (N,)
        x = np.asarray(x_list, dtype=np.float32).reshape(-1, 1)
        y = np.asarray(y_list, dtype=np.float32).reshape(-1, 1)

        yield x, y



def _maybe_get_iterable(dataset: str, rl: bool, batch_size: int, device, args):
	if args.get('local_dataset'):
		return local_ds_iter(args["local_dataset"], batch_size)
	#if rl:
	#    return _batch_iter(GymIterable(dataset, device=device), batch_size) if batch_size > 1 else GymIterable(dataset, device=device)
	#else:
	return _batch_iter(lset.read_dataset(dataset, False, ), batch_size) if batch_size > 1 else lset.read_dataset(dataset)



from torch.profiler import profile, ProfilerActivity

import os
import time

def timed_run_step(
	pack,
	ctx,
	x,
	y,
	do_update: bool,
	profiled: bool,
):
	if profiled and torch.cuda.is_available():
		start = torch.cuda.Event(enable_timing=True)
		end = torch.cuda.Event(enable_timing=True)

		torch.cuda.synchronize()
		start.record()

		loss, acc = _run_step(pack, ctx, x, y, do_update)

		end.record()
		torch.cuda.synchronize()

		torch_time_s = start.elapsed_time(end) * 1e-3  # ms → s
		return loss, acc, torch_time_s

	loss, acc = _run_step(pack, ctx, x, y, do_update)
	return loss, acc, 0.0



class LocalDataset:
    def __init__(self, data):
        self.x = torch.tensor(
            [p[0] for p in data],
            dtype=torch.float32
        ).view(-1, 1)

        self.y = torch.tensor(
            [p[1] for p in data],
            dtype=torch.float32
        ).view(-1, 1)

    def __len__(self):
        return self.x.shape[0]

    def get_batch(self, idx: torch.Tensor):
        return self.x[idx], self.y[idx]


import cProfile, pstats, io

def _probe_pretrain(pack: dict, ctx: "Context", ds, B: int) -> tuple[float, float]:
	# single no-update step on first batch, to detect leakage / verify reuse actually changes weights
	try:
		end = min(B, len(ds))
		# assumes your dataset object supports get_batch() and has .x for device, like LocalDataset
		idx = torch.arange(0, end, device=ds.x.device)
		x, y = ds.get_batch(idx)

		set_eval_mode(ctx)
		loss, acc = _run_step(pack, ctx, x, y, do_update=False)
		return float(loss), float(acc)
	except Exception as e:
		print(f"[DIAG][PRETRAIN] probe failed: {e}")
		return -1.0, -1.0

from .grad_gating import build_grad_gates, update_policy_after_backward

def train(
	pack: dict,
	ctx: "Context",
	epochs: int,
	dataset: str,
	batching_size: int = 0,
	profiled: int = False,
	profile_every: int = 3
):
	if not lset.has_dataset(dataset) and not pack.get("local_dataset"):
		return

	batching_size = 128
	eval_runs = 60_000
	device = pick_device(ctx)

	ctx.extra["_best"] = {"loss": float("inf"), "state": None, "step": -1}
	ctx.extra["_sections_last_acc"] = 0.0
	ctx.extra["_sections_max_acc"] = 0.0

	if not pack.get("graph") or not pack["graph"].get("pages"):
		return

	ctx.extra["is_training"] = dataset
	ctx.extra["batch_already"] = batching_size > 1

	best = _best_slot(ctx)
	set_eval_mode(ctx)
	cache = {}

	test_dataset = not pack.get("local_dataset") and lset.has_test_dataset(dataset)

	if torch.cuda.is_available():
		torch.cuda.synchronize()

	wall_start = time.perf_counter()
	torch_time_s = 0.0
	step_counter = 0



	try:
		# ---- dataset ----
		if not pack.get("local_dataset"):
			ds_train = lset.read_dataset(dataset, test=False)
		else:
			ds_train = LocalDataset(pack["local_dataset"])

		N_train = len(ds_train)
		B = batching_size

		# ---- expose module cache for section registry ----
		from .optim import _modules
		ctx.extra["_modules_ref"] = _modules(ctx)

		# ---- FIRST BUILD (NO UPDATE) + SECTION REUSE ----
		print("start")
		try:
			end0 = min(B, N_train)
			idx0 = torch.arange(0, end0, device=ds_train.x.device)
			x0, y0 = ds_train.get_batch(idx0)

			# build modules
			_run_step(pack, ctx, x0, y0, do_update=False)

			# probe BEFORE reuse
			pre_loss0, pre_acc0 = _probe_pretrain(pack, ctx, ds_train, B)
			print(f"[DIAG][PRETRAIN] before reuse: loss={pre_loss0:.4f} acc={pre_acc0:.4f}")

			# apply section reuse
			applied = apply_reuse_after_first_build(
				ctx=ctx,
				graph=pack["graph"],
				dataset_stamp=str(dataset),
			)

			# if weights were injected, optimizers must reset
			if applied > 0:
				ctx.extra.pop("_optims", None)

			# probe AFTER reuse
			pre_loss1, pre_acc1 = _probe_pretrain(pack, ctx, ds_train, B)
			print(f"[DIAG][PRETRAIN] after  reuse: loss={pre_loss1:.4f} acc={pre_acc1:.4f} applied_layers={applied}")


		except Exception:
			pass

		# ---- TRAINING LOOP ----
		for ep in range(epochs):
			train_loss = 0.0
			train_acc = 0.0
			train_len = 0

			if ep == 1 and profiled:
				pr = cProfile.Profile()
				pr.enable()

			for i in range(0, N_train, B):
				do_profile = profiled and (step_counter % profile_every == 0)

				end = min(i + B, N_train)
				idx = torch.arange(i, end, device=ds_train.x.device)
				x, y = ds_train.get_batch(idx)

				l, a, t_s = timed_run_step(
					pack,
					ctx,
					x,
					y,
					do_update=True,
					profiled=do_profile,
				)

				train_loss += l
				train_acc += a
				train_len += 1
				torch_time_s += t_s
				step_counter += 1

			if train_len > 0:
				train_loss /= train_len
				train_acc /= train_len

			ctx.extra["last_loss"] = train_loss
			ctx.extra["global_step"] = ctx.extra.get("global_step", 0) + 1

			if ep == 1 and profiled:
				pr.disable()
				s = io.StringIO()
				ps = pstats.Stats(pr, stream=s).sort_stats("cumulative")
				ps.print_stats(30)
				print(s.getvalue())

			val_loss = None
			val_acc = None

			if test_dataset:
				set_eval_mode(ctx)
				ds_test = lset.read_dataset(dataset, test=True)
				N_test = len(ds_test)

				val_loss = 0.0
				val_acc = 0.0
				val_len = 0

				for i in range(0, min(N_test, eval_runs), B):
					end = min(i + B, N_test)
					idx = torch.arange(i, end, device=ds_test.x.device)
					x, y = ds_test.get_batch(idx)

					l, a, t_s = timed_run_step(
						pack,
						ctx,
						x,
						y,
						do_update=False,
						profiled=False,
					)

					val_loss += l
					val_acc += a
					val_len += 1
					torch_time_s += t_s

				if val_len > 0:
					val_loss /= val_len
					val_acc /= val_len

				_maybe_update_best(ctx, val_loss)
			else:
				_maybe_update_best(ctx, train_loss)

			# ---- SECTION METRICS (REQUIRED FOR PERSISTENCE LOGIC) ----
			cur_acc = float(val_acc if val_acc is not None else train_acc)
			ctx.extra["_sections_last_acc"] = cur_acc
			ctx.extra["_sections_max_acc"] = max(
				float(ctx.extra.get("_sections_max_acc", 0.0)),
				cur_acc,
			)

			yield {
				"epoch": ep,
				"left": epochs - ep,
				"cache": cache,
				"type": "loss",
				"data": {
					"train_loss": train_loss,
					"val_loss": val_loss if val_loss is not None else train_loss,
					"train_acc": train_acc,
					"val_acc": val_acc if val_acc is not None else train_acc,
					"length": train_len,
					"batch_size": batching_size,
				},
			}

	except Exception as e:
		print("\n".join(traceback.format_exception(e)))

	finally:
		if profiled and torch.cuda.is_available():
			torch.cuda.synchronize()

		set_eval_mode(ctx)

		if best["state"] is not None:
			_restore(ctx, best["state"])

		ctx.extra["is_training"] = ""
		ctx.extra["train_target_tensor"] = None
		ctx.extra["batch_already"] = False





import io
# ----- save/load -----
def save_model(ctx: Context, path: str | io.BytesIO):
	mods = _modules(ctx); opts = _optims(ctx)
	state = {"modules": {k: m.state_dict() for k, m in mods.items() if not getattr(m, "_fused_parent", None)},
	         "optimizers": {k:o.state_dict() for k,o in opts.items()}}
	#print("save...")
	if isinstance(path, io.BytesIO):
		torch.save(state, path)
		path.seek(0)
	else:
		torch.save(state, path)

def load_model(ctx, path: str | io.BytesIO):
	device = pick_device(ctx)

	if path is None: return
	# If it's a string, check file existence
	if isinstance(path, str):
		if not os.path.exists(path):
			return
		state = torch.load(path, map_location=device)
	else:
		path.seek(0)
		state = torch.load(path, map_location=device)

	# keep around for future builds
	ctx.extra["_ckpt"] = state.get("modules", {})

	mods = _modules(ctx)
	for k, m in mods.items():
		sd = ctx.extra["_ckpt"].get(k)
		if isinstance(sd, dict):
			try:
				_partial_load_from_sd(m, sd, device)
			except Exception:
				pass

	_try_load_opts(ctx, state.get("optimizers", {}))

def _try_load_opts(ctx: Context, opt_state: Dict[str, Any]):
	if not opt_state: return
	cache = _optims(ctx)
	for key,opt in list(cache.items()):
		sd = opt_state.get(key)
		if sd is None: continue
		try:
			if "param_groups" in sd and len(sd["param_groups"]) == len(opt.param_groups):
				opt.load_state_dict(sd)
		except Exception: pass


