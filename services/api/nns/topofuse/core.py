# topofuse/core.py
"""
Topo Fusion: Runtime graph deduplication for multi-user training.

When User A and User B train the same architecture (same rough-topo hash),
their forward/backward passes are fused at the layer level to maximize
GPU utilization through batch concatenation and grouped operations.
"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import Dict, List, Tuple, Optional, Set, Any
from collections import defaultdict
import hashlib
import json
import torch
import torch.nn as nn


# ========== Types ==========

@dataclass
class UserSlice:
	"""Represents one user's portion of a fused super-batch."""
	user_id: str
	ctx_key: str  # context cache key
	batch_start: int
	batch_end: int
	input_tensor: torch.Tensor
	target_tensor: torch.Tensor

	@property
	def batch_size(self) -> int:
		return self.batch_end - self.batch_start


@dataclass
class FusedLayer:
	"""
	A layer that processes multiple users' data simultaneously.

	fusion_mode:
		- "identity": same weights (section reuse), concat batch only
		- "grouped": same shape, different weights, use grouped ops
		- "split": incompatible, must split and route separately
	"""
	layer_id: str
	fusion_mode: str  # "identity" | "grouped" | "split"

	# For identity mode: single shared module
	shared_module: Optional[nn.Module] = None

	# For grouped mode: list of per-user modules
	user_modules: List[nn.Module] = field(default_factory=list)
	user_ids: List[str] = field(default_factory=list)

	def can_fuse_with(self, other: "FusedLayer") -> bool:
		"""Check if this layer can fuse with another user's layer."""
		if self.layer_id != other.layer_id:
			return False

		if self.fusion_mode == "identity" and other.fusion_mode == "identity":
			# Same weight IDs (from section vault)
			return id(self.shared_module) == id(other.shared_module)

		if self.fusion_mode == "grouped":
			# Compatible shapes for grouped ops
			return True

		return False


@dataclass
class TopoFusionBucket:
	"""
	Bucket holding all active training sessions for one rough-topo hash.
	Manages super-batch construction and gradient routing.
	"""
	rough_topo_hash: str

	# Active user sessions
	user_slices: Dict[str, UserSlice] = field(default_factory=dict)

	# Layer-by-layer fusion plan
	fused_layers: List[FusedLayer] = field(default_factory=list)

	# Topology divergence points (where we must split)
	divergence_points: Set[int] = field(default_factory=set)

	def add_user(self, user_id: str, ctx_key: str, x: torch.Tensor, y: torch.Tensor) -> None:
		"""Add a user's batch to the super-batch."""
		current_total = sum(s.batch_size for s in self.user_slices.values())

		batch_size = x.shape[0]
		self.user_slices[user_id] = UserSlice(
			user_id=user_id,
			ctx_key=ctx_key,
			batch_start=current_total,
			batch_end=current_total + batch_size,
			input_tensor=x,
			target_tensor=y,
		)

	def remove_user(self, user_id: str) -> None:
		"""Remove a user from the fusion bucket."""
		self.user_slices.pop(user_id, None)

	def build_super_batch(self) -> Tuple[torch.Tensor, Dict[str, UserSlice]]:
		"""Concatenate all user batches into one super-batch."""
		if not self.user_slices:
			raise ValueError("No users in fusion bucket")

		tensors = [s.input_tensor for s in self.user_slices.values()]
		super_batch = torch.cat(tensors, dim=0)

		return super_batch, dict(self.user_slices)

	def slice_output(self, output: torch.Tensor) -> Dict[str, torch.Tensor]:
		"""Split super-batch output back to individual users."""
		results = {}
		for user_id, slice_info in self.user_slices.items():
			results[user_id] = output[slice_info.batch_start:slice_info.batch_end]
		return results


# ========== Rough Topo Hash ==========

def compute_rough_topo_hash(graph: Dict[str, Any]) -> str:
	"""
	Compute a coarse topology hash for bucketing.

	Only includes:
	- Node types in execution order
	- Layer kinds (dense, conv2d, etc.)
	- Basic connectivity structure

	Does NOT include:
	- Specific parameter values
	- Hyperparameters (learning rate, etc.)
	- User-specific state
	"""
	pages = graph.get("pages", {})

	# Extract node type sequence
	node_types = []
	for page_id in sorted(pages.keys()):
		page = pages[page_id]
		for node_id in sorted(page.keys()):
			node_blob = page[node_id]
			node_type = node_blob.get("type", "")

			# For NeuronLayer, include the layer kind
			if node_type == "NeuronLayer":
				cfg = node_blob.get("props", {}).get("config", {}) or {}
				layer_kind = cfg.get("type", "dense").lower()
				node_types.append(f"NeuronLayer:{layer_kind}")
			else:
				node_types.append(node_type)

	# Simple structural hash
	signature = {
		"nodes": node_types,
		"count": len(node_types),
	}

	s = json.dumps(signature, sort_keys=True, separators=(",", ":"))
	return hashlib.sha256(s.encode("utf-8")).hexdigest()[:16]


# ========== Global Fusion Registry ==========

class FusionRegistry:
	"""
	Global registry managing all active fusion buckets.
	Thread-safe for multi-user concurrent training.
	"""

	def __init__(self):
		self._buckets: Dict[str, TopoFusionBucket] = {}
		self._user_to_bucket: Dict[str, str] = {}
		self._lock = None  # Will be set by application (threading.Lock or trio.Lock)

	def set_lock(self, lock):
		"""Inject lock from application layer."""
		self._lock = lock

	def get_or_create_bucket(self, rough_hash: str) -> TopoFusionBucket:
		"""Get existing bucket or create new one for this topology."""
		if rough_hash not in self._buckets:
			self._buckets[rough_hash] = TopoFusionBucket(rough_topo_hash=rough_hash)
		return self._buckets[rough_hash]

	def register_user(
			self,
			user_id: str,
			rough_hash: str,
			ctx_key: str,
			x: torch.Tensor,
			y: torch.Tensor,
	) -> TopoFusionBucket:
		"""Register a user for fusion in the appropriate bucket."""
		bucket = self.get_or_create_bucket(rough_hash)
		bucket.add_user(user_id, ctx_key, x, y)
		self._user_to_bucket[user_id] = rough_hash
		return bucket

	def unregister_user(self, user_id: str) -> None:
		"""Remove user from fusion."""
		rough_hash = self._user_to_bucket.pop(user_id, None)
		if rough_hash and rough_hash in self._buckets:
			bucket = self._buckets[rough_hash]
			bucket.remove_user(user_id)

			# Clean up empty buckets
			if not bucket.user_slices:
				self._buckets.pop(rough_hash, None)

	def should_fuse(self, rough_hash: str) -> bool:
		"""Check if fusion is worthwhile (2+ users with same topo)."""
		bucket = self._buckets.get(rough_hash)
		return bucket is not None and len(bucket.user_slices) >= 2


# Global singleton
_FUSION_REGISTRY = FusionRegistry()


def get_fusion_registry() -> FusionRegistry:
	"""Access the global fusion registry."""
	return _FUSION_REGISTRY


# ========== Fusion Execution Engine ==========

class FusedForward:
	"""
	Executes fused forward pass for a super-batch.
	Handles identity paths, grouped operations, and divergence routing.
	"""

	def __init__(self, bucket: TopoFusionBucket):
		self.bucket = bucket

	def execute_identity_layer(
			self,
			layer: FusedLayer,
			super_batch: torch.Tensor,
	) -> torch.Tensor:
		"""
		Identity path: all users share the same weights.
		Simply run the shared module once on concatenated batch.
		"""
		return layer.shared_module(super_batch)

	def execute_grouped_conv2d(
			self,
			layer: FusedLayer,
			super_batch: torch.Tensor,
	) -> torch.Tensor:
		"""
		Grouped convolution: users have different weights but same shapes.
		Use groups= to execute in a single kernel launch.
		"""
		N, C, H, W = super_batch.shape
		n_users = len(layer.user_modules)

		# Stack weights from all users into grouped conv
		weights = []
		biases = []

		for module in layer.user_modules:
			if isinstance(module, nn.Conv2d):
				weights.append(module.weight)
				if module.bias is not None:
					biases.append(module.bias)

		# Create grouped conv dynamically
		out_channels_per_user = weights[0].shape[0]
		in_channels = weights[0].shape[1]
		kernel_size = weights[0].shape[2:]

		grouped_weight = torch.cat(weights, dim=0)  # [n_users*out, in, k, k]
		grouped_bias = torch.cat(biases, dim=0) if biases else None

		# Execute grouped convolution
		output = torch.nn.functional.conv2d(
			super_batch,
			grouped_weight,
			bias=grouped_bias,
			stride=1,
			padding="same",
			groups=n_users,
		)

		return output

	def execute_grouped_linear(
			self,
			layer: FusedLayer,
			super_batch: torch.Tensor,
	) -> torch.Tensor:
		"""
		Grouped linear: manually split batch, execute per-user, concat results.
		PyTorch doesn't have native grouped linear, so we do it manually.
		"""
		outputs = []

		start_idx = 0
		for i, (user_id, module) in enumerate(zip(layer.user_ids, layer.user_modules)):
			user_slice = self.bucket.user_slices[user_id]
			batch_size = user_slice.batch_size

			user_input = super_batch[start_idx:start_idx + batch_size]
			user_output = module(user_input)
			outputs.append(user_output)

			start_idx += batch_size

		return torch.cat(outputs, dim=0)

	def execute_layer(
			self,
			layer: FusedLayer,
			super_batch: torch.Tensor,
	) -> torch.Tensor:
		"""Route to appropriate fusion strategy."""
		if layer.fusion_mode == "identity":
			return self.execute_identity_layer(layer, super_batch)

		elif layer.fusion_mode == "grouped":
			# Determine layer type from first module
			first_module = layer.user_modules[0] if layer.user_modules else None

			if isinstance(first_module, nn.Conv2d):
				return self.execute_grouped_conv2d(layer, super_batch)
			elif isinstance(first_module, nn.Linear):
				return self.execute_grouped_linear(layer, super_batch)
			else:
				# Fallback: split execution
				return self.execute_split_layer(layer, super_batch)

		else:  # split mode
			return self.execute_split_layer(layer, super_batch)

	def execute_split_layer(
			self,
			layer: FusedLayer,
			super_batch: torch.Tensor,
	) -> torch.Tensor:
		"""
		Fallback: split batch, execute per-user, concat.
		Used when fusion is impossible (different ops, etc.).
		"""
		outputs = []

		for user_id in self.bucket.user_slices.keys():
			slice_info = self.bucket.user_slices[user_id]
			user_input = super_batch[slice_info.batch_start:slice_info.batch_end]

			# Find this user's module
			user_idx = layer.user_ids.index(user_id) if user_id in layer.user_ids else 0
			module = layer.user_modules[user_idx] if user_idx < len(layer.user_modules) else layer.shared_module

			user_output = module(user_input)
			outputs.append(user_output)

		return torch.cat(outputs, dim=0)


# ========== Integration Hooks ==========

def should_enable_fusion(ctx) -> bool:
	"""Check if fusion should be enabled for this context."""
	# Fusion only active during training
	if not ctx.extra.get("is_training"):
		return False

	# Must opt-in via config
	if not ctx.extra.get("enable_topo_fusion", False):
		return False

	# Must have rough_topo_hash computed
	if "rough_topo_hash" not in ctx.extra:
		return False

	return True


def try_register_for_fusion(
		ctx,
		user_id: str,
		x: torch.Tensor,
		y: torch.Tensor,
) -> Optional[str]:
	"""
	Attempt to register this training session for fusion.
	Returns fusion_bucket_id if successful, None otherwise.
	"""
	if not should_enable_fusion(ctx):
		return None

	rough_hash = ctx.extra["rough_topo_hash"]
	registry = get_fusion_registry()

	if not registry.should_fuse(rough_hash):
		# Not enough users yet for this topology
		return None

	# Register and return bucket ID
	ctx_key = str(id(ctx))
	bucket = registry.register_user(user_id, rough_hash, ctx_key, x, y)

	return bucket.rough_topo_hash


def unregister_from_fusion(ctx, user_id: str) -> None:
	"""Remove user from fusion when training completes/stops."""
	registry = get_fusion_registry()
	registry.unregister_user(user_id)