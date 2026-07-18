# section_reuse_lenet5_bench_fast_phase_portrait.py
# Copy-paste ready.
# Adds Variant #2 logging: "SGD phase portrait" points (loss vs grad_norm) for baseline vs reuse.
# Keeps your fast tensor-cached dataset path (GPU/CPU).
#
# Output JSON will include:
#   run_meta["phase_portrait_points"] : list[ {N, user_id, scenario, step, loss, grad_norm} ]
#
# Example run:
#   python section_reuse_lenet5_bench_fast_phase_portrait.py --device cuda --amp --cache_dataset
#
# Plot (quick):
#   python - <<'PY'
#   import json, matplotlib.pyplot as plt, math
#   path = "./bench_out/section_reuse_lenet5_fast_YYYYMMDD_HHMMSS.json"
#   d = json.load(open(path, "r", encoding="utf-8"))
#   pts = d["phase_portrait_points"]
#   lb, gb, lr, gr = [], [], [], []
#   for p in pts:
#       if p["scenario"] == "baseline":
#           lb.append(p["loss"]); gb.append(p["grad_norm"])
#       elif p["scenario"] == "reuse":
#           lr.append(p["loss"]); gr.append(p["grad_norm"])
#   plt.figure(figsize=(7,5))
#   plt.scatter(lb, gb, s=10, alpha=0.35, label="Baseline")
#   plt.scatter(lr, gr, s=10, alpha=0.35, label="Section Reuse")
#   plt.yscale("log")
#   plt.xlabel("Training loss")
#   plt.ylabel("Gradient L2 norm")
#   plt.title("SGD Phase Portrait: Loss vs ||grad||")
#   plt.grid(True, linestyle="--", alpha=0.5)
#   plt.legend()
#   plt.tight_layout()
#   plt.show()
#   PY

import os
import time
import json
import math
import argparse
import platform
from dataclasses import dataclass, asdict
from typing import Dict, List, Tuple, Optional, Any

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, Subset

try:
	from torchvision import datasets, transforms
except Exception as e:
	raise RuntimeError("Install torchvision: pip install torchvision") from e


# ----------------------------
# Model: LeNet-5 (classic-ish)
# ----------------------------
class LeNet5(nn.Module):
	"""
	Sections (for reuse):
	  S1: conv1 + relu + pool
	  S2: conv2 + relu + pool
	  S3: fc1 + relu
	  S4: fc2 + relu
	  S5: fc3
	"""
	def __init__(self, fc1_out: int = 120, fc2_out: int = 84, num_classes: int = 10):
		super().__init__()
		self.conv1 = nn.Conv2d(1, 6, kernel_size=5)     # 28->24
		self.conv2 = nn.Conv2d(6, 16, kernel_size=5)    # after pool: 12->8; then pool: 8->4
		self.fc1 = nn.Linear(256, fc1_out)
		self.fc2 = nn.Linear(fc1_out, fc2_out)
		self.fc3 = nn.Linear(fc2_out, num_classes)

	def forward(self, x):
		x = F.relu(self.conv1(x))
		x = F.max_pool2d(x, 2)          # 24->12
		x = F.relu(self.conv2(x))
		x = F.max_pool2d(x, 2)          # 8->4
		x = torch.flatten(x, 1)
		x = F.relu(self.fc1(x))
		x = F.relu(self.fc2(x))
		x = self.fc3(x)
		return x


# ----------------------------
# Section reuse helpers
# ----------------------------
def extract_sections_state(model: LeNet5) -> Dict[str, Dict[str, torch.Tensor]]:
	# Store per-section state_dict fragments (tensors on CPU for portability)
	sd = model.state_dict()
	sections = {
		"S1_conv1": {k: sd[k].detach().cpu().clone() for k in sd.keys() if k.startswith("conv1.")},
		"S2_conv2": {k: sd[k].detach().cpu().clone() for k in sd.keys() if k.startswith("conv2.")},
		"S3_fc1":   {k: sd[k].detach().cpu().clone() for k in sd.keys() if k.startswith("fc1.")},
		"S4_fc2":   {k: sd[k].detach().cpu().clone() for k in sd.keys() if k.startswith("fc2.")},
		"S5_fc3":   {k: sd[k].detach().cpu().clone() for k in sd.keys() if k.startswith("fc3.")},
	}
	return sections


def _expand_linear_weight(W: torch.Tensor, out_new: int, alpha: float = 0.02) -> torch.Tensor:
	out_old, in_f = W.shape
	if out_new == out_old:
		return W
	if out_new < out_old:
		return W[:out_new, :].contiguous()

	W_new = torch.empty((out_new, in_f), dtype=W.dtype)
	W_new[:out_old] = W
	with torch.no_grad():
		base = W.norm(p=2).item() / math.sqrt(W.numel() + 1e-9)
		noise = torch.randn((out_new - out_old, in_f), dtype=W.dtype) * (alpha * base)
		W_new[out_old:] = noise
	return W_new.contiguous()


def _expand_bias(b: torch.Tensor, out_new: int, alpha: float = 0.02) -> torch.Tensor:
	out_old = b.shape[0]
	if out_new == out_old:
		return b
	if out_new < out_old:
		return b[:out_new].contiguous()

	b_new = torch.empty((out_new,), dtype=b.dtype)
	b_new[:out_old] = b
	with torch.no_grad():
		base = b.norm(p=2).item() / math.sqrt(b.numel() + 1e-9) if b.numel() else 0.0
		noise = torch.randn((out_new - out_old,), dtype=b.dtype) * (alpha * base + 1e-6)
		b_new[out_old:] = noise
	return b_new.contiguous()


def apply_sections_reuse(
	model: LeNet5,
	sections_cache: Dict[str, Dict[str, torch.Tensor]],
	reuse_policy: str = "all",
	best_effort: bool = True,
) -> Dict[str, str]:
	status = {}

	def _load(sec_key: str):
		if reuse_policy == "conv_only" and not (sec_key.startswith("S1") or sec_key.startswith("S2")):
			status[sec_key] = "skipped(policy=conv_only)"
			return
		if reuse_policy == "conv_fc12" and sec_key.startswith("S5"):
			status[sec_key] = "skipped(policy=conv_fc12)"
			return

		sec_sd = sections_cache.get(sec_key, None)
		if not sec_sd:
			status[sec_key] = "miss"
			return

		own_sd = model.state_dict()
		ok = True
		for k, v in sec_sd.items():
			if k not in own_sd or own_sd[k].shape != v.shape:
				ok = False
				break

		if ok:
			model.load_state_dict(sec_sd, strict=False)
			status[sec_key] = "hit(exact)"
			return

		if not best_effort:
			status[sec_key] = "shape_mismatch(no_best_effort)"
			return

		converted = {}
		for k, v in sec_sd.items():
			if k not in own_sd:
				continue
			if own_sd[k].shape == v.shape:
				converted[k] = v
				continue

			if k.endswith(".weight") and ("fc" in k):
				out_new, in_new = own_sd[k].shape
				out_old, in_old = v.shape
				if in_new != in_old:
					continue
				converted[k] = _expand_linear_weight(v, out_new)
			elif k.endswith(".bias") and ("fc" in k):
				out_new = own_sd[k].shape[0]
				converted[k] = _expand_bias(v, out_new)
			else:
				continue

		if len(converted) == 0:
			status[sec_key] = "miss(shape_mismatch_unhandled)"
			return

		model.load_state_dict(converted, strict=False)
		status[sec_key] = "hit(best_effort)"

	_load("S1_conv1")
	_load("S2_conv2")
	_load("S3_fc1")
	_load("S4_fc2")
	_load("S5_fc3")
	return status


# ----------------------------
# Data splits to emulate many "users"
# ----------------------------
def build_user_subsets(
	n_users: int,
	dataset_len: int,
	train_size: int,
	overlap: float,
	seed: int
) -> List[List[int]]:
	g = torch.Generator().manual_seed(seed)
	all_idx = torch.randperm(dataset_len, generator=g).tolist()

	shared_n = int(train_size * max(0.0, min(1.0, overlap)))
	uniq_n = train_size - shared_n

	shared = all_idx[:shared_n]
	cursor = shared_n

	user_indices = []
	for _u in range(n_users):
		uniq = all_idx[cursor:cursor + uniq_n]
		cursor += uniq_n
		if len(uniq) < uniq_n:
			cursor = shared_n
			uniq = all_idx[cursor:cursor + uniq_n]
			cursor += uniq_n
		user_indices.append(shared + uniq)

	return user_indices


# ----------------------------
# Timing utilities
# ----------------------------
@dataclass
class TrainMetrics:
	user_id: int
	scenario: str               # "baseline" or "reuse" or "reuse_seed"
	reuse_policy: str
	best_effort: bool
	sections_status: Dict[str, str]

	fc1_out: int
	fc2_out: int
	batch_size: int
	train_samples: int
	overlap: float

	target_acc: float
	reached: bool
	steps_to_target: int
	epochs_ran: int

	train_wall_s: float
	train_gpu_ms: float
	eval_wall_s: float
	eval_gpu_ms: float

	final_test_acc: float
	best_test_acc: float

	samples_seen: int
	steps_total: int


def cuda_sync_if_needed(device: torch.device):
	if device.type == "cuda":
		torch.cuda.synchronize()


class CUDATimer:
	def __init__(self, device: torch.device):
		self.device = device
		self.enabled = (device.type == "cuda")
		self.ms = 0.0
		self._t0 = 0.0
		self._start = None
		self._end = None

	def start(self):
		if not self.enabled:
			self._t0 = time.perf_counter()
			return
		self._start = torch.cuda.Event(enable_timing=True)
		self._end = torch.cuda.Event(enable_timing=True)
		self._start.record()

	def stop(self):
		if not self.enabled:
			self.ms += (time.perf_counter() - self._t0) * 1000.0
			return
		self._end.record()
		torch.cuda.synchronize()
		self.ms += self._start.elapsed_time(self._end)


# ----------------------------
# Fast tensor caching + GPU batch loader
# ----------------------------
@torch.no_grad()
def preload_dataset_to_tensors(dataset, device: torch.device, batch_size: int = 2048) -> Tuple[torch.Tensor, torch.Tensor]:
	loader = DataLoader(dataset, batch_size=batch_size, shuffle=False, num_workers=0)
	xs = []
	ys = []
	for x, y in loader:
		xs.append(x.to(device, non_blocking=True))
		ys.append(y.to(device, non_blocking=True))
	x_all = torch.cat(xs, dim=0).contiguous()
	y_all = torch.cat(ys, dim=0).contiguous()
	return x_all, y_all


class TensorBatchLoader:
	def __init__(self, x: torch.Tensor, y: torch.Tensor, indices: List[int], batch_size: int, shuffle: bool = True):
		self.x = x
		self.y = y
		self.bs = int(batch_size)
		self.shuffle = bool(shuffle)
		self.idx = torch.tensor(indices, device=x.device, dtype=torch.long)

	def __iter__(self):
		if self.shuffle:
			perm = torch.randperm(self.idx.numel(), device=self.idx.device)
			idx = self.idx[perm]
		else:
			idx = self.idx

		for i in range(0, idx.numel(), self.bs):
			sel = idx[i:i + self.bs]
			yield self.x.index_select(0, sel), self.y.index_select(0, sel)

	def __len__(self) -> int:
		return (self.idx.numel() + self.bs - 1) // self.bs

	@property
	def batch_size(self) -> int:
		return self.bs

	@property
	def dataset_size(self) -> int:
		return int(self.idx.numel())


# ----------------------------
# Train / eval (tensor loaders)
# ----------------------------
@torch.no_grad()
def eval_accuracy_tensorloader(
	model: nn.Module,
	loader: TensorBatchLoader,
	device: torch.device,
	max_batches: Optional[int] = None
) -> Tuple[float, float, int]:
	model.eval()
	correct = 0
	total = 0
	gpu_t = CUDATimer(device)
	wall0 = time.perf_counter()

	gpu_t.start()
	for bi, (x, y) in enumerate(loader):
		logits = model(x)
		pred = logits.argmax(dim=1)
		correct += (pred == y).sum().item()
		total += y.numel()
		if max_batches is not None and (bi + 1) >= max_batches:
			break
	gpu_t.stop()

	wall = time.perf_counter() - wall0
	acc = correct / max(1, total)
	return acc, wall, int(gpu_t.ms)


def _compute_grad_norm_l2(model: nn.Module) -> float:
	# L2 norm over all parameter gradients.
	total_sq = 0.0
	for p in model.parameters():
		if p.grad is None:
			continue
		# ensure float
		n = p.grad.data.norm(2).item()
		total_sq += n * n
	return math.sqrt(total_sq)


def train_one_user_tensor(
	user_id: int,
	scenario: str,
	device: torch.device,
	train_loader: TensorBatchLoader,
	test_loader_fast: TensorBatchLoader,
	test_loader_full: TensorBatchLoader,
	fc1_out: int,
	fc2_out: int,
	sections_cache: Optional[Dict[str, Dict[str, torch.Tensor]]],
	reuse_policy: str,
	best_effort: bool,
	target_acc: float,
	max_epochs: int,
	eval_every_steps: int,
	max_train_steps: int,
	amp: bool,
	lr: float,
	noise_warmup: bool = True,

	# Phase portrait logging
	log_phase_portrait: bool = True,
	log_every_steps: int = 5,
	N_context: int = -1,
) -> Tuple[TrainMetrics, Optional[Dict[str, Dict[str, torch.Tensor]]], List[Dict[str, Any]]]:

	model = LeNet5(fc1_out=fc1_out, fc2_out=fc2_out).to(device)

	sections_status = {"S1_conv1": "n/a", "S2_conv2": "n/a", "S3_fc1": "n/a", "S4_fc2": "n/a", "S5_fc3": "n/a"}
	if scenario == "reuse" and sections_cache is not None:
		sections_status = apply_sections_reuse(model, sections_cache, reuse_policy=reuse_policy, best_effort=best_effort)

	opt = torch.optim.SGD(model.parameters(), lr=lr, momentum=0.9)
	scaler = torch.cuda.amp.GradScaler(enabled=(amp and device.type == "cuda"))

	phase_points: List[Dict[str, Any]] = []

	# Optional warmup step to reduce first-iteration noise
	if noise_warmup:
		model.train()
		cuda_sync_if_needed(device)
		x0, y0 = next(iter(train_loader))
		with torch.cuda.amp.autocast(enabled=(amp and device.type == "cuda")):
			loss0 = F.cross_entropy(model(x0), y0)
		scaler.scale(loss0).backward()
		scaler.step(opt)
		scaler.update()
		opt.zero_grad(set_to_none=True)
		cuda_sync_if_needed(device)

	train_gpu = CUDATimer(device)
	train_wall0 = time.perf_counter()

	reached = False
	steps_to_target = 0
	best_acc = 0.0

	steps_total = 0
	samples_seen = 0
	epochs_ran = 0

	eval_wall_s_total = 0.0
	eval_gpu_ms_total = 0.0

	for epoch in range(max_epochs):
		model.train()
		epochs_ran += 1

		for x, y in train_loader:
			steps_total += 1
			samples_seen += y.numel()

			train_gpu.start()
			with torch.cuda.amp.autocast(enabled=(amp and device.type == "cuda")):
				logits = model(x)
				loss = F.cross_entropy(logits, y)

			# backward
			scaler.scale(loss).backward()

			# Phase portrait logging: loss vs grad_norm (before step)
			if log_phase_portrait and (steps_total % max(1, log_every_steps) == 0):
				# Unscale grads before norm so AMP doesn't distort magnitude
				if amp and device.type == "cuda":
					scaler.unscale_(opt)
				grad_norm = _compute_grad_norm_l2(model)
				phase_points.append({
					"N": int(N_context),
					"user_id": int(user_id),
					"scenario": str(scenario),
					"step": int(steps_total),
					"loss": float(loss.item()),
					"grad_norm": float(grad_norm),
				})

			# step
			scaler.step(opt)
			scaler.update()
			opt.zero_grad(set_to_none=True)
			train_gpu.stop()

			# periodic eval for early stop
			if (steps_total % eval_every_steps) == 0:
				acc, e_wall, e_gpu_ms = eval_accuracy_tensorloader(model, test_loader_fast, device, max_batches=None)
				best_acc = max(best_acc, acc)
				eval_wall_s_total += e_wall
				eval_gpu_ms_total += e_gpu_ms
				if acc >= target_acc:
					reached = True
					steps_to_target = steps_total
					break

			if steps_total >= max_train_steps:
				break

		if reached or steps_total >= max_train_steps:
			break

	train_wall_s = time.perf_counter() - train_wall0

	# Final full test
	final_acc, final_wall, final_gpu_ms = eval_accuracy_tensorloader(model, test_loader_full, device, max_batches=None)
	best_acc = max(best_acc, final_acc)
	eval_wall_s_total += final_wall
	eval_gpu_ms_total += final_gpu_ms

	metrics = TrainMetrics(
		user_id=user_id,
		scenario=scenario,
		reuse_policy=reuse_policy,
		best_effort=best_effort,
		sections_status=sections_status,
		fc1_out=fc1_out,
		fc2_out=fc2_out,
		batch_size=train_loader.batch_size,
		train_samples=train_loader.dataset_size,
		overlap=-1.0,  # filled by caller
		target_acc=target_acc,
		reached=reached,
		steps_to_target=steps_to_target if reached else -1,
		epochs_ran=epochs_ran,
		train_wall_s=float(train_wall_s),
		train_gpu_ms=float(train_gpu.ms),
		eval_wall_s=float(eval_wall_s_total),
		eval_gpu_ms=float(eval_gpu_ms_total),
		final_test_acc=float(final_acc),
		best_test_acc=float(best_acc),
		samples_seen=int(samples_seen),
		steps_total=int(steps_total),
	)

	new_cache = None
	if scenario == "baseline":
		new_cache = extract_sections_state(model)

	return metrics, new_cache, phase_points


# ----------------------------
# Reporting
# ----------------------------
def print_env(device: torch.device):
	print("\n=== Environment ===")
	print(f"Python: {platform.python_version()}  |  OS: {platform.system()} {platform.release()}")
	print(f"Torch: {torch.__version__}")
	if device.type == "cuda":
		print(f"CUDA: {torch.version.cuda} | Device: {torch.cuda.get_device_name(0)}")
	else:
		print("Device: CPU")


def summarize(metrics: List[TrainMetrics]) -> Dict[str, float]:
	total_train_wall = sum(m.train_wall_s for m in metrics)
	total_train_gpu = sum(m.train_gpu_ms for m in metrics)
	total_eval_wall = sum(m.eval_wall_s for m in metrics)
	total_eval_gpu = sum(m.eval_gpu_ms for m in metrics)
	total_steps = sum(m.steps_total for m in metrics)
	total_samples = sum(m.samples_seen for m in metrics)
	reached_cnt = sum(1 for m in metrics if m.reached)
	mean_final_acc = sum(m.final_test_acc for m in metrics) / max(1, len(metrics))

	exact_hits = 0
	best_effort_hits = 0
	misses = 0
	skipped = 0
	for m in metrics:
		for st in m.sections_status.values():
			if st.startswith("hit(exact)"):
				exact_hits += 1
			elif st.startswith("hit(best_effort)"):
				best_effort_hits += 1
			elif st.startswith("miss"):
				misses += 1
			elif st.startswith("skipped"):
				skipped += 1

	return {
		"users": len(metrics),
		"total_train_wall_s": float(total_train_wall),
		"total_train_gpu_ms": float(total_train_gpu),
		"total_eval_wall_s": float(total_eval_wall),
		"total_eval_gpu_ms": float(total_eval_gpu),
		"total_steps": int(total_steps),
		"total_samples_seen": int(total_samples),
		"reached_count": int(reached_cnt),
		"success_rate": float(reached_cnt / max(1, len(metrics))),
		"mean_final_test_acc": float(mean_final_acc),
		"gpu_ms_per_success": float(total_train_gpu / reached_cnt) if reached_cnt > 0 else float("inf"),
		"reuse_exact_hits": int(exact_hits),
		"reuse_best_effort_hits": int(best_effort_hits),
		"reuse_misses": int(misses),
		"reuse_skipped": int(skipped),
	}


def write_csv(path: str, rows: List[Dict]):
	import csv
	with open(path, "w", newline="", encoding="utf-8") as f:
		w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
		w.writeheader()
		for r in rows:
			w.writerow(r)


def main():
	p = argparse.ArgumentParser(description="Section Reuse benchmark on LeNet-5 (MNIST) — fast tensor-cached + phase portrait logging")
	p.add_argument("--data_dir", type=str, default="./data", help="MNIST download/cache dir")
	p.add_argument("--out_dir", type=str, default="./bench_out", help="Where to save CSV/JSON")
	p.add_argument("--device", type=str, default="cuda", help="cuda or cpu")
	p.add_argument("--seed", type=int, default=123, help="RNG seed")

	p.add_argument("--users_list", type=str, default="1,2,4,8,16,32", help="comma list for N users sweep")
	p.add_argument("--train_samples", type=int, default=12000, help="train samples per user")
	p.add_argument("--test_samples_fast", type=int, default=2000, help="fast eval subset size")
	p.add_argument("--test_samples_full", type=int, default=10000, help="full eval size (MNIST test is 10000)")
	p.add_argument("--overlap", type=float, default=0.85, help="fraction of shared train indices among users")

	p.add_argument("--batch", type=int, default=256, help="batch size")
	p.add_argument("--amp", action="store_true", help="use mixed precision on CUDA")
	p.add_argument("--lr", type=float, default=0.02, help="SGD learning rate")
	p.add_argument("--max_epochs", type=int, default=8, help="max epochs per user")
	p.add_argument("--max_steps", type=int, default=1200, help="max train steps per user (hard cap)")
	p.add_argument("--eval_every", type=int, default=50, help="evaluate every K steps (fast subset)")

	p.add_argument("--reuse_policy", type=str, default="all", choices=["all", "conv_only", "conv_fc12"],
				   help="which sections to reuse")
	p.add_argument("--best_effort", action="store_true", help="enable best-effort conversion for FC dims mismatch")
	p.add_argument("--fc1_out", type=int, default=120, help="LeNet fc1 out features (default 120)")
	p.add_argument("--fc2_out", type=int, default=84, help="LeNet fc2 out features (default 84)")
	p.add_argument("--fc1_out_per_user", type=str, default="", help="optional per-user fc1_out list")

	p.add_argument("--cache_dataset", action="store_true", help="cache MNIST tensors on device (recommended on CUDA)")
	p.add_argument("--cache_batch", type=int, default=4096, help="batch size used to preload dataset tensors")

	# Phase portrait knobs
	p.add_argument("--log_phase", action="store_true", help="log (loss, grad_norm) points for phase portrait")
	p.add_argument("--log_every", type=int, default=5, help="log every K train steps")

	args = p.parse_args()

	os.makedirs(args.out_dir, exist_ok=True)
	torch.manual_seed(args.seed)

	device = torch.device(args.device if (args.device != "cuda" or torch.cuda.is_available()) else "cpu")
	if device.type == "cuda":
		torch.backends.cudnn.benchmark = True

	print_env(device)

	# Load MNIST
	tfm = transforms.Compose([
		transforms.ToTensor(),
		transforms.Normalize((0.1307,), (0.3081,))
	])
	train_ds_full = datasets.MNIST(args.data_dir, train=True, download=True, transform=tfm)
	test_ds_full = datasets.MNIST(args.data_dir, train=False, download=True, transform=tfm)

	# Fixed test subsets for comparability
	g = torch.Generator().manual_seed(args.seed + 999)
	test_idx = torch.randperm(len(test_ds_full), generator=g).tolist()
	test_fast_idx = test_idx[:min(args.test_samples_fast, len(test_ds_full))]
	test_full_idx = test_idx[:min(args.test_samples_full, len(test_ds_full))]

	users_list = [int(x.strip()) for x in args.users_list.split(",") if x.strip()]
	if len(users_list) == 0:
		raise ValueError("--users_list is empty")

	per_user_fc1 = None
	if args.fc1_out_per_user.strip():
		per_user_fc1 = [int(x.strip()) for x in args.fc1_out_per_user.split(",") if x.strip()]

	use_cache = bool(args.cache_dataset)

	if use_cache:
		print("\nCaching datasets to tensors (on device) ...")
		train_x, train_y = preload_dataset_to_tensors(train_ds_full, device=device, batch_size=args.cache_batch)
		test_x, test_y = preload_dataset_to_tensors(test_ds_full, device=device, batch_size=args.cache_batch)
		test_loader_fast = TensorBatchLoader(test_x, test_y, test_fast_idx, batch_size=512, shuffle=False)
		test_loader_full = TensorBatchLoader(test_x, test_y, test_full_idx, batch_size=512, shuffle=False)
	else:
		print("\nDataset caching disabled: using per-subset preload fallback (slower).")
		test_fast = Subset(test_ds_full, test_fast_idx)
		test_full = Subset(test_ds_full, test_full_idx)
		test_x2, test_y2 = preload_dataset_to_tensors(test_fast, device=device, batch_size=args.cache_batch)
		test_loader_fast = TensorBatchLoader(test_x2, test_y2, list(range(len(test_fast))), batch_size=512, shuffle=False)
		test_x3, test_y3 = preload_dataset_to_tensors(test_full, device=device, batch_size=args.cache_batch)
		test_loader_full = TensorBatchLoader(test_x3, test_y3, list(range(len(test_full))), batch_size=512, shuffle=False)

	run_rows = []
	all_phase_points: List[Dict[str, Any]] = []

	run_meta = {
		"args": vars(args),
		"env": {
			"python": platform.python_version(),
			"torch": torch.__version__,
			"cuda": torch.version.cuda if device.type == "cuda" else None,
			"device_name": torch.cuda.get_device_name(0) if device.type == "cuda" else "CPU",
		},
		"runs": []
	}

	# Sweep N users
	for N in users_list:
		print(f"\n\n============================")
		print(f" Sweep: N users = {N}")
		print(f"============================")

		train_size = min(args.train_samples, len(train_ds_full))
		dataset_len = int(train_x.shape[0]) if (use_cache) else len(train_ds_full)
		user_idx = build_user_subsets(
			n_users=N,
			dataset_len=dataset_len,
			train_size=train_size,
			overlap=args.overlap,
			seed=args.seed + 1000 + N
		)

		# ------------------------
		# Scenario 1: Baseline
		# ------------------------
		baseline_metrics: List[TrainMetrics] = []
		t0 = time.perf_counter()

		for u in range(N):
			fc1 = per_user_fc1[u] if (per_user_fc1 and u < len(per_user_fc1)) else args.fc1_out

			if use_cache:
				train_loader = TensorBatchLoader(train_x, train_y, user_idx[u], batch_size=args.batch, shuffle=True)
			else:
				subset = Subset(train_ds_full, user_idx[u])
				xu, yu = preload_dataset_to_tensors(subset, device=device, batch_size=args.cache_batch)
				train_loader = TensorBatchLoader(xu, yu, list(range(len(subset))), batch_size=args.batch, shuffle=True)

			met, _cache, phase_pts = train_one_user_tensor(
				user_id=u,
				scenario="baseline",
				device=device,
				train_loader=train_loader,
				test_loader_fast=test_loader_fast,
				test_loader_full=test_loader_full,
				fc1_out=fc1,
				fc2_out=args.fc2_out,
				sections_cache=None,
				reuse_policy=args.reuse_policy,
				best_effort=args.best_effort,
				target_acc=0.98,
				max_epochs=args.max_epochs,
				eval_every_steps=args.eval_every,
				max_train_steps=args.max_steps,
				amp=args.amp,
				lr=args.lr,
				log_phase_portrait=bool(args.log_phase),
				log_every_steps=int(args.log_every),
				N_context=int(N),
			)
			met.overlap = args.overlap
			baseline_metrics.append(met)

			if args.log_phase:
				all_phase_points.extend(phase_pts)

		baseline_wall = time.perf_counter() - t0
		base_sum = summarize(baseline_metrics)

		# ------------------------
		# Scenario 2: Reuse (seed + warm-start)
		# ------------------------
		reuse_metrics: List[TrainMetrics] = []
		sections_cache = None

		t1 = time.perf_counter()
		for u in range(N):
			fc1 = per_user_fc1[u] if (per_user_fc1 and u < len(per_user_fc1)) else args.fc1_out

			if use_cache:
				train_loader = TensorBatchLoader(train_x, train_y, user_idx[u], batch_size=args.batch, shuffle=True)
			else:
				subset = Subset(train_ds_full, user_idx[u])
				xu, yu = preload_dataset_to_tensors(subset, device=device, batch_size=args.cache_batch)
				train_loader = TensorBatchLoader(xu, yu, list(range(len(subset))), batch_size=args.batch, shuffle=True)

			if u == 0:
				met, sections_cache, phase_pts = train_one_user_tensor(
					user_id=u,
					scenario="baseline",
					device=device,
					train_loader=train_loader,
					test_loader_fast=test_loader_fast,
					test_loader_full=test_loader_full,
					fc1_out=fc1,
					fc2_out=args.fc2_out,
					sections_cache=None,
					reuse_policy=args.reuse_policy,
					best_effort=args.best_effort,
					target_acc=0.98,
					max_epochs=args.max_epochs,
					eval_every_steps=args.eval_every,
					max_train_steps=args.max_steps,
					amp=args.amp,
					lr=args.lr,
					log_phase_portrait=False,  # don't mix seed points into "reuse" portrait
					log_every_steps=int(args.log_every),
					N_context=int(N),
				)
				met.scenario = "reuse_seed"
				met.overlap = args.overlap
				reuse_metrics.append(met)
			else:
				met, _cache2, phase_pts = train_one_user_tensor(
					user_id=u,
					scenario="reuse",
					device=device,
					train_loader=train_loader,
					test_loader_fast=test_loader_fast,
					test_loader_full=test_loader_full,
					fc1_out=fc1,
					fc2_out=args.fc2_out,
					sections_cache=sections_cache,
					reuse_policy=args.reuse_policy,
					best_effort=args.best_effort,
					target_acc=0.98,
					max_epochs=args.max_epochs,
					eval_every_steps=args.eval_every,
					max_train_steps=args.max_steps,
					amp=args.amp,
					lr=args.lr,
					log_phase_portrait=bool(args.log_phase),
					log_every_steps=int(args.log_every),
					N_context=int(N),
				)
				met.overlap = args.overlap
				reuse_metrics.append(met)

				if args.log_phase:
					all_phase_points.extend(phase_pts)

		reuse_wall = time.perf_counter() - t1
		reuse_only_sum = summarize([m for m in reuse_metrics if m.scenario != "reuse_seed"])
		reuse_all_sum = summarize(reuse_metrics)

		# Print comparison
		print("\n--- Baseline totals (all users from scratch) ---")
		print(f"Wall total (script): {baseline_wall:.2f} s")
		print(f"Train wall total:    {base_sum['total_train_wall_s']:.2f} s")
		print(f"Train GPU total:     {base_sum['total_train_gpu_ms']/1000.0:.2f} s")
		print(f"Total steps:         {base_sum['total_steps']}")
		print(f"Reached target:      {base_sum['reached_count']}/{N}  (success_rate={base_sum['success_rate']:.3f})")
		print(f"Mean final acc:      {base_sum['mean_final_test_acc']:.4f}")
		print(f"GPU ms / success:    {base_sum['gpu_ms_per_success']:.2f}")

		print("\n--- Reuse totals (user0 seeds cache + others warm-start) ---")
		print(f"Wall total (script): {reuse_wall:.2f} s")
		print(f"Train wall total:    {reuse_all_sum['total_train_wall_s']:.2f} s")
		print(f"Train GPU total:     {reuse_all_sum['total_train_gpu_ms']/1000.0:.2f} s")
		print(f"Total steps:         {reuse_all_sum['total_steps']}")
		print(f"Reached target:      {reuse_all_sum['reached_count']}/{N}  (success_rate={reuse_all_sum['success_rate']:.3f})")
		print(f"Mean final acc:      {reuse_all_sum['mean_final_test_acc']:.4f}")
		print(f"GPU ms / success:    {reuse_all_sum['gpu_ms_per_success']:.2f}")

		# First-variant key deltas
		work_eliminated = 1.0 - (reuse_all_sum["total_steps"] / max(1, base_sum["total_steps"]))
		print("\n--- First-variant metrics ---")
		print(f"Work eliminated ratio (by steps): {work_eliminated:.3f}")
		print(f"Baseline GPU ms/success: {base_sum['gpu_ms_per_success']:.2f}")
		print(f"Reuse GPU ms/success:     {reuse_all_sum['gpu_ms_per_success']:.2f}")
		print(f"Reuse section hits: exact={reuse_all_sum['reuse_exact_hits']} best_effort={reuse_all_sum['reuse_best_effort_hits']} misses={reuse_all_sum['reuse_misses']} skipped={reuse_all_sum['reuse_skipped']}")

		# Row for CSV
		row = {
			"N_users": N,
			"overlap": args.overlap,
			"batch": args.batch,
			"target_acc": 0.98,
			"reuse_policy": args.reuse_policy,
			"best_effort": bool(args.best_effort),
			"amp": bool(args.amp),
			"cache_dataset": bool(use_cache),
			"baseline_total_train_gpu_ms": base_sum["total_train_gpu_ms"],
			"reuse_total_train_gpu_ms": reuse_all_sum["total_train_gpu_ms"],
			"baseline_total_train_wall_s": base_sum["total_train_wall_s"],
			"reuse_total_train_wall_s": reuse_all_sum["total_train_wall_s"],
			"baseline_total_steps": base_sum["total_steps"],
			"reuse_total_steps": reuse_all_sum["total_steps"],
			"work_eliminated_ratio": float(work_eliminated),
			"baseline_success_rate": base_sum["success_rate"],
			"reuse_success_rate": reuse_all_sum["success_rate"],
			"baseline_gpu_ms_per_success": base_sum["gpu_ms_per_success"],
			"reuse_gpu_ms_per_success": reuse_all_sum["gpu_ms_per_success"],
			"baseline_mean_final_acc": base_sum["mean_final_test_acc"],
			"reuse_mean_final_acc": reuse_all_sum["mean_final_test_acc"],
			"reuse_exact_hits": reuse_all_sum["reuse_exact_hits"],
			"reuse_best_effort_hits": reuse_all_sum["reuse_best_effort_hits"],
			"reuse_misses": reuse_all_sum["reuse_misses"],
		}
		run_rows.append(row)

		run_meta["runs"].append({
			"N": N,
			"baseline_users": [asdict(m) for m in baseline_metrics],
			"reuse_users": [asdict(m) for m in reuse_metrics],
			"baseline_summary": base_sum,
			"reuse_summary_including_seed": reuse_all_sum,
			"reuse_summary_only_reused_users": reuse_only_sum,
		})

		print("\nPer-user quick view (baseline):")
		for m in baseline_metrics:
			print(f"  u={m.user_id:02d} steps={m.steps_total:4d} gpu_train={m.train_gpu_ms/1000.0:6.2f}s acc={m.final_test_acc:.4f} reached={m.reached}")

		print("\nPer-user quick view (reuse):")
		for m in reuse_metrics:
			sec = ", ".join([f"{k}:{v}" for k, v in m.sections_status.items()])
			print(f"  u={m.user_id:02d} [{m.scenario}] steps={m.steps_total:4d} gpu_train={m.train_gpu_ms/1000.0:6.2f}s acc={m.final_test_acc:.4f} reached={m.reached}  | {sec}")

	# Save CSV + JSON
	ts = time.strftime("%Y%m%d_%H%M%S")
	csv_path = os.path.join(args.out_dir, f"section_reuse_lenet5_fast_{ts}.csv")
	json_path = os.path.join(args.out_dir, f"section_reuse_lenet5_fast_{ts}.json")

	write_csv(csv_path, run_rows)
	run_meta["phase_portrait_points"] = all_phase_points

	with open(json_path, "w", encoding="utf-8") as f:
		json.dump(run_meta, f, ensure_ascii=False, indent=2)

	print("\n\n=== Saved ===")
	print(f"CSV:  {csv_path}")
	print(f"JSON: {json_path}")
	if args.log_phase:
		print(f"Phase portrait points: {len(all_phase_points)}")
	print("\nNext: plot curves like work_eliminated_ratio, gpu_ms_per_success, success_rate vs N.")
	print("If --log_phase was enabled: plot loss vs grad_norm from JSON['phase_portrait_points'].")


if __name__ == "__main__":
	main()
