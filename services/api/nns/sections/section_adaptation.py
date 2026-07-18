from __future__ import annotations
import torch
import math


def _fan_in(t: torch.Tensor) -> int:
	if t.dim() == 2:
		return t.shape[1]
	if t.dim() == 4:
		return t.shape[1] * t.shape[2] * t.shape[3]
	return max(1, t.numel())


def _variance_preserving_noise_like(t: torch.Tensor):
	fin = _fan_in(t)
	std = math.sqrt(2.0 / fin)
	return torch.randn_like(t) * std


def adapt_dense_weight(old_w: torch.Tensor, new_shape: tuple):
	out_new, in_new = new_shape
	out_old, in_old = old_w.shape

	new_w = torch.zeros(out_new, in_new, device=old_w.device)

	o = min(out_old, out_new)
	i = min(in_old, in_new)

	new_w[:o, :i] = old_w[:o, :i]

	if in_new > in_old:
		noise = _variance_preserving_noise_like(new_w[:o, in_old:in_new])
		new_w[:o, in_old:in_new] = noise

	if out_new > out_old:
		base = new_w[:out_old, :i]
		idx = torch.randint(0, out_old, (out_new - out_old,))
		new_w[out_old:, :i] = base[idx]

	return new_w


def adapt_conv_weight(old_w: torch.Tensor, new_shape: tuple):
	out_new, in_new, kh, kw = new_shape
	out_old, in_old, _, _ = old_w.shape

	new_w = torch.zeros(out_new, in_new, kh, kw, device=old_w.device)

	o = min(out_old, out_new)
	i = min(in_old, in_new)

	new_w[:o, :i] = old_w[:o, :i]

	if in_new > in_old:
		noise = _variance_preserving_noise_like(new_w[:o, in_old:])
		new_w[:o, in_old:] = noise

	if out_new > out_old:
		idx = torch.randint(0, out_old, (out_new - out_old,))
		new_w[out_old:] = new_w[idx]

	return new_w

def within_ratio(a, b, lo, hi):
	r = b / a
	return lo <= r <= hi

MAX_DENSE_EXPANSION_RATIO = 2.0      # e.g. 128 → 256 allowed, 128 → 1028 blocked
MAX_DENSE_REDUCTION_RATIO = 0.5      # e.g. 256 → 128 allowed

MAX_CONV_FILTER_EXPANSION = 2.0
MAX_CONV_CHANNEL_EXPANSION = 2.0

MAX_KERNEL_CHANGE = 0                # kernel size must match

def dense_shapes_compatible(old_shape, new_shape):

	out_old, in_old = old_shape
	out_new, in_new = new_shape

	out_ratio = out_new / out_old
	in_ratio = in_new / in_old

	if out_ratio > MAX_DENSE_EXPANSION_RATIO:
		return False

	if in_ratio > MAX_DENSE_EXPANSION_RATIO:
		return False

	if out_ratio < MAX_DENSE_REDUCTION_RATIO:
		return False

	if in_ratio < MAX_DENSE_REDUCTION_RATIO:
		return False

	return True


def conv_shapes_compatible(old_shape, new_shape):

	out_old, in_old, kh_old, kw_old = old_shape
	out_new, in_new, kh_new, kw_new = new_shape

	if abs(kh_old - kh_new) > MAX_KERNEL_CHANGE:
		return False

	if abs(kw_old - kw_new) > MAX_KERNEL_CHANGE:
		return False

	if (out_new / out_old) > MAX_CONV_FILTER_EXPANSION:
		return False

	if (in_new / in_old) > MAX_CONV_CHANNEL_EXPANSION:
		return False

	return True

def adapt_state_dict(old_sd, new_sd):
	new_state = {}

	for k, v in new_sd.items():

		if k not in old_sd:
			new_state[k] = v
			continue

		old = old_sd[k]

		if not isinstance(old, torch.Tensor):
			new_state[k] = v
			continue

		if old.shape == v.shape:
			new_state[k] = old
			continue

		if old.dim() == 2:
			if not dense_shapes_compatible(old.shape, v.shape):
				return None
			new_state[k] = adapt_dense_weight(old, v.shape)

		elif old.dim() == 4:
			if not conv_shapes_compatible(old.shape, v.shape):
				return None
			new_state[k] = adapt_conv_weight(old, v.shape)

		else:
			new_state[k] = v

	return new_state