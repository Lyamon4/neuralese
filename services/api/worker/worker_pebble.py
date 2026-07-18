import uuid, threading, inspect, traceback, queue
from typing import Any, Callable, Dict, Tuple, Optional, List, AsyncIterator
from pebble import ThreadPool
import asyncio

Progress = Dict[str, Any]
OnDone = Callable[[str, Optional[Any], Optional[BaseException]], Any]

_pool = ThreadPool(max_workers=4)
_lock = threading.Lock()

_progress: Dict[str, "asyncio.Queue[Progress]"] = {}
_done: Dict[str, bool] = {}
_results: Dict[str, Any] = {}
_errors: Dict[str, Dict[str, Any]] = {}
_done_ev: Dict[str, threading.Event] = {}
_on_done: Dict[str, List[OnDone]] = {}

_inboxes: Dict[str, "queue.Queue[Any]"] = {}
_preinbox: Dict[str, "queue.Queue[Any]"] = {}
_CLOSE = object()

_loop_call_soon_threadsafe: Optional[Callable[[Callable, Any], None]] = None


def job_exists(job_id: str) -> bool:
	with _lock:
		return (job_id in _progress or job_id in _done_ev or
		        job_id in _done or job_id in _results or job_id in _errors)

def job_active(job_id: str) -> bool:
	with _lock:
		# job is considered active if we've created it and not marked done yet
		if job_id not in _done:
			return False
		return not _done.get(job_id, False)

def progress_queue(job_id: str) -> "asyncio.Queue[Progress]":
	with _lock:
		ch = _progress.get(job_id)
	if ch is None:
		raise KeyError(f"unknown job_id: {job_id}")
	return ch

def bind_loop_callsoon(call_soon_threadsafe):
	global _loop_call_soon_threadsafe
	_loop_call_soon_threadsafe = call_soon_threadsafe

def _emit_for(job_id: str):
	def emit(payload: Progress):
		payload = dict(payload)
		payload.setdefault("job_id", job_id)
		with _lock:
			ch = _progress.get(job_id)
		if ch and _loop_call_soon_threadsafe:
			_loop_call_soon_threadsafe(asyncio.create_task, ch.put(payload))
	return emit

def on_done(job_id: str, cb: OnDone) -> None:
	with _lock:
		_on_done.setdefault(job_id, []).append(cb)

def _fire_on_done(job_id: str, result: Any, exc: Optional[BaseException]) -> None:
	with _lock:
		callbacks = list(_on_done.get(job_id, []))
		_on_done.pop(job_id, None)
	for cb in callbacks:
		try:
			ret = cb(job_id, result, exc)
			if inspect.isawaitable(ret) and _loop_call_soon_threadsafe:
				_loop_call_soon_threadsafe(_run_coro, ret)
		except Exception:
			pass

def _run_coro(coro):
	asyncio.create_task(coro)


# ---------------- Receiver: object-style ingress ----------------

class Receiver:
	"""
	Per-job inbound data buffer with:
	  - any(): bool  -> check if data is available (non-blocking)
	  - poll(): Optional[Any] -> get immediately or None (non-blocking)
	  - pop(timeout=None): Any -> blocking sync get (raises EOFError on close)
	  - frame(): await Any -> await next frame (raises EOFError on close)
	  - inputs(): async iterator over frames until closed
	  - closed: bool -> input stream closed
	Callable: recv() returns self, so `recv().frame()` is valid.
	Truthiness: bool(recv) == recv.any()
	"""
	def __init__(self, q: "queue.Queue[Any]"):
		self._q = q
		self._closed = False

	def on_kill(self, fn: Callable[[], None]):
		self._on_kill = fn
		_on_kill_hooks[self._job_id] = fn

	def __call__(self) -> "Receiver":
		return self

	def __bool__(self) -> bool:
		return self.any()

	@property
	def closed(self) -> bool:
		return self._closed

	def any(self) -> bool:
		# Non-destructive availability check. Never consumes.
		return not self._q.empty()

	def poll(self) -> Optional[Any]:
		# Non-blocking get; returns None if empty.
		try:
			item = self._q.get_nowait()
		except queue.Empty:
			return None
		if item is _CLOSE:
			self._closed = True
			# keep sentinel available for any other waiter
			self._q.put_nowait(_CLOSE)
			raise EOFError("input closed")
		return item

	def pop(self, timeout: Optional[float] = None) -> Any:
		# Blocking get; raises EOFError if closed. No data is lost: queue buffers.
		item = self._q.get(timeout=timeout)
		if item is _CLOSE:
			self._closed = True
			# put it back so other consumers (if any) see closure too
			self._q.put_nowait(_CLOSE)
			raise EOFError("input closed")
		return item

	async def frame(self) -> Any:
		# Await one frame without losing anything.
		loop = asyncio.get_running_loop()
		return await loop.run_in_executor(None, self.pop)

	async def inputs(self) -> AsyncIterator[Any]:
		# Async stream until closed.
		while True:
			try:
				val = await self.frame()
			except EOFError:
				break
			else:
				yield val


# ---------------- External API to push/close input ----------------

def send(job_id: str, value: Any) -> bool:
    with _lock:
        inbox = _inboxes.get(job_id) or _preinbox.get(job_id)
    if inbox is None:
        return False
    inbox.put_nowait(value)
    return True


def close_input(job_id: str) -> None:
	with _lock:
		inbox = _inboxes.get(job_id)
	if inbox is not None:
		inbox.put_nowait(_CLOSE)


# ---------------- Submit/runner wiring ----------------

def submit(fn: Callable, *args, **kwargs) -> str:
	job_id = uuid.uuid4().hex
	with _lock:
		_progress[job_id] = asyncio.Queue()
		_done[job_id] = False
		_done_ev[job_id] = threading.Event()
		_inboxes[job_id] = queue.Queue()
		_preinbox[job_id] = queue.Queue()	# <— NEW

	def _runner():
		emit = _emit_for(job_id)
		# drain preinbox if any
		with _lock:
			pre = _preinbox.pop(job_id, None)
			inbox = _inboxes[job_id]
		if pre is not None:
			while not pre.empty():
				inbox.put_nowait(pre.get_nowait())

		recv = Receiver(inbox)
		recv._job_id = job_id

		try:
			result = fn(emit, recv, *args, **kwargs)
		except Exception as e:
			print("\n".join(traceback.format_exception(e)))
		if inspect.isawaitable(result):
			return asyncio.run(result)
		return result

	fut = _pool.schedule(_runner)

	def _on_done_f(f):
		exc = f.exception()
		if exc is None:
			try:
				res = f.result()
			except BaseException as e:
				_store_error(job_id, e)
				_emit_for(job_id)({"phase": "error", **_errors[job_id]})
				_mark_done(job_id)
				_fire_on_done(job_id, None, e)
				return
			with _lock:
				_results[job_id] = res
			_emit_for(job_id)({"phase": "done"})
			_mark_done(job_id)
			_fire_on_done(job_id, res, None)
		else:
			_store_error(job_id, exc)
			_emit_for(job_id)({"phase": "error", **_errors[job_id]})
			_mark_done(job_id)
			_fire_on_done(job_id, None, exc)

	fut.add_done_callback(_on_done_f)
	return job_id



def _store_error(job_id: str, exc: BaseException) -> None:
	err = {
		"type": exc.__class__.__name__,
		"message": str(exc),
		"traceback": "".join(traceback.format_exception(type(exc), exc, exc.__traceback__)),
	}
	with _lock:
		_errors[job_id] = err

def _mark_done(job_id: str) -> None:
	with _lock:
		_done[job_id] = True
		ev = _done_ev.get(job_id)
		inbox = _inboxes.pop(job_id, None)
	# if someone’s waiting, make sure they can exit promptly
	if inbox is not None:
		try:
			inbox.put_nowait(_CLOSE)
		except Exception:
			pass
	if ev:
		ev.set()

def poll_result(job_id: str) -> Tuple[bool, Optional[Any], Optional[Dict[str, Any]]]:
	with _lock:
		if not _done.get(job_id, False):
			return False, None, None
		err = _errors.get(job_id)
		if err:
			return True, None, err
		return True, _results.get(job_id), None

async def wait_done(job_id: str, timeout: Optional[float] = None) -> Tuple[bool, Optional[Any], Optional[Dict[str, Any]]]:
	with _lock:
		ev = _done_ev.get(job_id)
	if ev is None:
		# already finished or never existed
		return True, _results.get(job_id), _errors.get(job_id)

	# wait in executor so it doesn’t block the event loop
	loop = asyncio.get_running_loop()
	ok = await loop.run_in_executor(None, ev.wait, timeout)
	if not ok:
		return False, None, None

	with _lock:
		return True, _results.get(job_id), _errors.get(job_id)


_on_kill_hooks = {}
results = {}

def kill(job_id: str) -> bool:
	with _lock:
		inbox = _inboxes.get(job_id)
		ev = _done_ev.get(job_id)
		done = _done.get(job_id, False)

	if done:
		return False

	if inbox:
		inbox.put_nowait(_CLOSE)

	with _lock:
		_done[job_id] = True
	if ev:
		ev.set()

	hook = _on_kill_hooks.pop(job_id, None)
	if hook:
		try:
			hook()
		except Exception:
			traceback.print_exc()

	_emit_for(job_id)({"phase": "stopped"})
	return True

from contextlib import suppress
def stop(job_id: str, timeout = None) -> bool:
	with _lock:
		done = _done.get(job_id, False)
		ev = _done_ev.get(job_id)
		inbox = _inboxes.get(job_id)
		hook = _on_kill_hooks.pop(job_id, None)

	if done:
		return True

	if inbox is not None:
		try:
			inbox.put_nowait(_CLOSE)
		except Exception:
			pass

	if hook is not None:
		try:
			hook()
		except Exception:
			traceback.print_exc()

	try:
		_emit_for(job_id)({"phase": "stopping"})
	except Exception:
		pass

	if ev is None:
		return True

	ok = ev.wait(timeout=timeout)
	return bool(ok)