# topofuse/sync.py
"""
Synchronization primitives for coordinating multiple users in fusion buckets.

In a real deployment, this would use:
- Distributed barriers (Redis, etcd, or custom protocol)
- WebSocket coordination for step synchronization
- Shared memory for GPU tensor exchange (NCCL, NVSHMEM)

This implementation provides the coordination structure.
"""

from __future__ import annotations
from typing import Dict, Set, Optional, Callable, Any
from dataclasses import dataclass, field
import asyncio
import time
import threading


# ========== Sync Primitives ==========

@dataclass
class StepBarrier:
	"""
	Coordination barrier for synchronizing users at each training step.
	All users must reach the barrier before fusion can proceed.
	"""
	bucket_id: str
	expected_users: Set[str] = field(default_factory=set)
	arrived_users: Set[str] = field(default_factory=set)
	step_number: int = 0

	# Event for signaling all users arrived
	_ready_event: Optional[asyncio.Event] = None
	_lock: Optional[asyncio.Lock] = None

	def __post_init__(self):
		self._ready_event = asyncio.Event()
		self._lock = asyncio.Lock()

	async def wait_for_users(self, user_id: str, timeout: float = 5.0) -> bool:
		"""
		User arrives at barrier and waits for others.

		Returns:
			True if all users arrived, False if timeout
		"""
		async with self._lock:
			self.arrived_users.add(user_id)

			if self.arrived_users >= self.expected_users:
				# Everyone's here, signal ready
				self._ready_event.set()

		# Wait for all users with timeout
		try:
			await asyncio.wait_for(self._ready_event.wait(), timeout=timeout)
			return True
		except asyncio.TimeoutError:
			return False

	async def reset_for_next_step(self) -> None:
		"""Reset barrier for next training step."""
		async with self._lock:
			self.arrived_users.clear()
			self.step_number += 1
			self._ready_event.clear()


@dataclass
class FusionSession:
	"""
	Tracks a multi-user fusion session across training steps.
	Manages synchronization, tensor exchange, and result distribution.
	"""
	bucket_id: str
	user_ids: Set[str] = field(default_factory=set)

	# Per-step barriers
	barriers: Dict[int, StepBarrier] = field(default_factory=dict)

	# Tensor exchange buffers (in production: GPU shared memory)
	input_buffers: Dict[str, Any] = field(default_factory=dict)
	output_buffers: Dict[str, Any] = field(default_factory=dict)

	# Session state
	active: bool = True
	created_at: float = field(default_factory=time.time)

	def get_barrier(self, step: int) -> StepBarrier:
		"""Get or create barrier for specific training step."""
		if step not in self.barriers:
			barrier = StepBarrier(
				bucket_id=self.bucket_id,
				expected_users=set(self.user_ids),
				step_number=step,
			)
			self.barriers[step] = barrier
		return self.barriers[step]

	def add_user(self, user_id: str) -> None:
		"""Add user to fusion session."""
		self.user_ids.add(user_id)

		# Update existing barriers
		for barrier in self.barriers.values():
			barrier.expected_users.add(user_id)

	def remove_user(self, user_id: str) -> None:
		"""Remove user from fusion session."""
		self.user_ids.discard(user_id)

		# Update existing barriers
		for barrier in self.barriers.values():
			barrier.expected_users.discard(user_id)

			# If user was blocking barrier, signal ready anyway
			if user_id in barrier.arrived_users:
				barrier.arrived_users.discard(user_id)
				if barrier.arrived_users >= barrier.expected_users:
					if barrier._ready_event:
						barrier._ready_event.set()


# ========== Session Registry ==========

class FusionSessionRegistry:
	"""
	Global registry of active fusion sessions.
	Thread-safe for concurrent access.
	"""

	def __init__(self):
		self._sessions: Dict[str, FusionSession] = {}
		self._lock = threading.Lock()

	def get_or_create_session(self, bucket_id: str) -> FusionSession:
		"""Get existing session or create new one."""
		with self._lock:
			if bucket_id not in self._sessions:
				self._sessions[bucket_id] = FusionSession(bucket_id=bucket_id)
			return self._sessions[bucket_id]

	def remove_session(self, bucket_id: str) -> None:
		"""Remove session (when all users leave)."""
		with self._lock:
			session = self._sessions.pop(bucket_id, None)
			if session:
				session.active = False

	def cleanup_stale_sessions(self, max_age: float = 3600.0) -> int:
		"""Remove sessions older than max_age seconds."""
		now = time.time()
		removed = 0

		with self._lock:
			stale = [
				bid for bid, session in self._sessions.items()
				if (now - session.created_at) > max_age
			]

			for bid in stale:
				self._sessions.pop(bid, None)
				removed += 1

		return removed


# Global singleton
_SESSION_REGISTRY = FusionSessionRegistry()


def get_session_registry() -> FusionSessionRegistry:
	"""Access global session registry."""
	return _SESSION_REGISTRY


# ========== Async Coordination API ==========

async def coordinate_fused_step(
		bucket_id: str,
		user_id: str,
		step_number: int,
		timeout: float = 5.0,
) -> bool:
	"""
	Coordinate one training step across all users in fusion bucket.

	Args:
		bucket_id: Fusion bucket identifier
		user_id: This user's identifier
		step_number: Current training step number
		timeout: Max seconds to wait for other users

	Returns:
		True if coordination succeeded, False if timeout/error
	"""
	registry = get_session_registry()
	session = registry.get_or_create_session(bucket_id)

	if not session.active:
		return False

	# Get barrier for this step
	barrier = session.get_barrier(step_number)

	# Wait for all users to arrive
	success = await barrier.wait_for_users(user_id, timeout=timeout)

	if success:
		# All users ready, proceed with fusion
		return True
	else:
		# Timeout - proceed without fusion
		print(f"[TOPO_FUSION] Step {step_number} timeout for user {user_id}")
		return False


async def exchange_tensors(
		bucket_id: str,
		user_id: str,
		input_tensor: Any,
) -> Dict[str, Any]:
	"""
	Exchange input tensors with other users in fusion bucket.

	In production, this would:
	1. Upload tensor to shared GPU memory (NCCL)
	2. Signal other users via distributed queue
	3. Download other users' tensors

	Args:
		bucket_id: Fusion bucket identifier
		user_id: This user's identifier
		input_tensor: This user's input batch

	Returns:
		Dict[user_id -> tensor] for all users in bucket
	"""
	registry = get_session_registry()
	session = registry.get_or_create_session(bucket_id)

	# Store this user's tensor
	session.input_buffers[user_id] = input_tensor

	# Wait for all users to upload (simplified - in production use barriers)
	max_wait = 100  # 10 seconds
	wait_count = 0

	while len(session.input_buffers) < len(session.user_ids):
		await asyncio.sleep(0.1)
		wait_count += 1
		if wait_count > max_wait:
			break

	# Return all tensors
	return dict(session.input_buffers)


async def distribute_results(
		bucket_id: str,
		user_id: str,
		results: Dict[str, Any],
) -> Any:
	"""
	Distribute fusion results back to individual users.

	Args:
		bucket_id: Fusion bucket identifier
		user_id: This user's identifier
		results: Dict[user_id -> result] for all users

	Returns:
		This user's specific result
	"""
	registry = get_session_registry()
	session = registry.get_or_create_session(bucket_id)

	# Store results
	for uid, result in results.items():
		session.output_buffers[uid] = result

	# Return this user's result
	return session.output_buffers.get(user_id)


# ========== Cleanup Hooks ==========

def register_user_for_sync(bucket_id: str, user_id: str) -> None:
	"""Register user in sync session."""
	registry = get_session_registry()
	session = registry.get_or_create_session(bucket_id)
	session.add_user(user_id)


def unregister_user_from_sync(bucket_id: str, user_id: str) -> None:
	"""Remove user from sync session."""
	registry = get_session_registry()
	session = registry.get_or_create_session(bucket_id)
	session.remove_user(user_id)

	# If no users left, remove session
	if not session.user_ids:
		registry.remove_session(bucket_id)


# ========== Monitoring ==========

def get_sync_stats(bucket_id: str) -> Optional[Dict[str, Any]]:
	"""Get synchronization statistics for monitoring."""
	registry = get_session_registry()
	session = registry.get_or_create_session(bucket_id)

	if not session:
		return None

	return {
		"bucket_id": bucket_id,
		"n_users": len(session.user_ids),
		"user_ids": list(session.user_ids),
		"n_barriers": len(session.barriers),
		"active": session.active,
		"age_seconds": time.time() - session.created_at,
	}