import json
import zstandard as zstd
import websocket
import requests
import threading

HTTP_BASE = "http://127.0.0.1:8000"
WS_BASE   = "ws://127.0.0.1:8000"

LOGIN_ENDPOINT           = "/login"
DELETE_CTX_ENDPOINT      = "/delete_ctx"
CREATE_USER_ENDPOINT     = "/create_user"
TRAIN_WS                 = "/ws/train"

# ============================
# STATE
# ============================

STATE = {
	"session": None,      # requests.Session
	"user": None,         # username
	"pass": None,         # password
	"auth_headers": None  # Cookie header for WS
}

# ============================
# MULTI-TRAIN CONTROL
# ============================

STOP_EVENT = threading.Event()
ACTIVE_THREADS: list[threading.Thread] = []
ACTIVE_WS_LOCK = threading.Lock()
ACTIVE_WS: list[websocket.WebSocket] = []  # track sockets to force-close on Ctrl+C


# ============================
# HELPERS
# ============================

def compress_dict_zstd(data: dict) -> bytes:
	raw = json.dumps(data, separators=(",", ":")).encode("utf-8")
	return zstd.ZstdCompressor(level=3).compress(raw)


def cookie_header(session: requests.Session) -> dict:
	cookies = session.cookies.get_dict()
	return {
		"Cookie": "; ".join(f"{k}={v}" for k, v in cookies.items())
	}


def _register_ws(ws: websocket.WebSocket) -> None:
	with ACTIVE_WS_LOCK:
		ACTIVE_WS.append(ws)


def _unregister_ws(ws: websocket.WebSocket) -> None:
	with ACTIVE_WS_LOCK:
		try:
			ACTIVE_WS.remove(ws)
		except ValueError:
			pass


def _force_close_all_ws() -> None:
	with ACTIVE_WS_LOCK:
		socks = list(ACTIVE_WS)
	for ws in socks:
		try:
			ws.close()
		except Exception:
			pass


# ============================
# COMMANDS (HTTP)
# ============================

def cmd_create(user: str, pw: str):
	s = requests.Session()

	try:
		r = s.post(
			HTTP_BASE + CREATE_USER_ENDPOINT,
			json={
				"user": user,
				"pass": pw,
				"config": {"teacher": False}
			},
			timeout=5
		)
	except requests.RequestException:
		print("error: network")
		return

	try:
		j = r.json()
	except Exception:
		print("error: protocol")
		return

	match j.get("answer"):
		case "ok":
			print("ok: account created")
		case "exists":
			print("error: exists")
		case _:
			print("error: unknown")


def cmd_login(user: str, pw: str):
	s = requests.Session()

	r = s.post(
		HTTP_BASE + LOGIN_ENDPOINT,
		json={"user": user, "pass": pw},
		timeout=5
	)

	if r.status_code != 200:
		print("error: login failed")
		return

	STATE["session"] = s
	STATE["user"] = user
	STATE["pass"] = pw
	STATE["auth_headers"] = cookie_header(s)

	try:
		ans = r.json().get("answer")
	except Exception:
		ans = None

	print(f"ok: logged in as {user}" if ans == "ok" else "error: wrong user or pass")


def cmd_delete_ctx(user: str, pw: str, scene: str, ctx: str):
	s = requests.Session()

	r = s.post(
		HTTP_BASE + DELETE_CTX_ENDPOINT,
		json={"user": user, "pass": pw, "scene": scene, "contexts": [ctx]},
		timeout=5
	)

	try:
		ans = r.json().get("answer")
	except Exception:
		ans = None

	print("ok: ctx deleted" if ans == "ok" else "error: ctx not deleted")


# ============================
# TRAINING (WS)
# ============================

def _train_worker(user: str, pw: str, cfg: str, idx: int):
	"""
	Одна тренировка = один WS. Работает до закрытия сокета сервером или до STOP_EVENT.
	"""
	ws = None
	tag = f"train#{idx}:{user}"
	try:
		with open(cfg, "r", encoding="utf-8") as f:
			payload_dict = json.load(f)

		payload = compress_dict_zstd(payload_dict)

		ws = websocket.WebSocket()
		ws.connect(
			WS_BASE + TRAIN_WS,
			header=[
				f"user: {user}",
				f"pass: {pw}",
			],
			timeout=20
		)

		_register_ws(ws)

		print(f"[{tag}] connected → sending payload ({cfg})")
		ws.send(payload, opcode=websocket.ABNF.OPCODE_BINARY)

		# КРИТИЧНО: timeout, чтобы можно было корректно остановиться по Ctrl+C
		ws.settimeout(1.0)

		while not STOP_EVENT.is_set():
			try:
				msg = ws.recv()
				if msg is None:
					break
				print(f"[{tag}]", msg)
			except websocket.WebSocketTimeoutException:
				continue
			except websocket.WebSocketConnectionClosedException:
				print(f"[{tag}] closed by server")
				break

	except Exception as e:
		if not STOP_EVENT.is_set():
			print(f"[{tag}] error:", e)

	finally:
		if ws is not None:
			_unregister_ws(ws)
			try:
				ws.close()
			except Exception:
				pass
		print(f"[{tag}] stopped")


def cmd_train(user: str, pw: str, cfg: str):
	"""
	Одна тренировка (один пользователь).
	"""
	STOP_EVENT.clear()
	_force_close_all_ws()

	try:
		_train_worker(user, pw, cfg, 0)
	except KeyboardInterrupt:
		print("\ninterrupt received → stopping training")
		STOP_EVENT.set()
		_force_close_all_ws()


def cmd_trains(triples: list[tuple[str, str, str]]):
	"""
	Несколько тренировок на нескольких юзерах:
	trains user1 pass1 cfg1 user2 pass2 cfg2 ...
	"""
	if not triples:
		print("error: no trainings provided")
		return

	STOP_EVENT.clear()
	_force_close_all_ws()
	ACTIVE_THREADS.clear()

	for i, (user, pw, cfg) in enumerate(triples):
		t = threading.Thread(
			target=_train_worker,
			args=(user, pw, cfg, i),
			daemon=True
		)
		ACTIVE_THREADS.append(t)
		t.start()

	print(f"ok: started {len(triples)} trainings (Ctrl+C to stop)")

	try:
		for t in ACTIVE_THREADS:
			t.join()
	except KeyboardInterrupt:
		print("\ninterrupt received → stopping trainings")
		STOP_EVENT.set()
		_force_close_all_ws()
		for t in ACTIVE_THREADS:
			t.join()

	print("ok: all trainings stopped")
	ACTIVE_THREADS.clear()


def cmd_whoami():
	if STATE["user"]:
		print(f"user: {STATE['user']}")
	else:
		print("user: <none>")


# ============================
# REPL
# ============================

def _parse_trains_args(parts: list[str]) -> list[tuple[str, str, str]] | None:
	"""
	parts = ["trains", "u1", "p1", "cfg1", "u2", "p2", "cfg2", ...]
	"""
	args = parts[1:]
	if len(args) == 0:
		return []

	if len(args) % 3 != 0:
		return None

	out: list[tuple[str, str, str]] = []
	for i in range(0, len(args), 3):
		user = args[i]
		pw   = args[i + 1]
		cfg  = args[i + 2]
		out.append((user, pw, cfg))
	return out


def repl():
	print("Neuralese backend debugger")
	print("commands: create | login | train | trains | dctx | whoami | exit")
	print("trains usage: trains USER1 PASS1 CFG1 USER2 PASS2 CFG2 ...")

	while True:
		try:
			line = input("> ").strip()
		except EOFError:
			break
		except KeyboardInterrupt:
			# Ctrl+C в REPL: остановить активные тренировки и продолжить REPL
			print("\ninterrupt received → stopping any active trainings")
			STOP_EVENT.set()
			_force_close_all_ws()
			for t in list(ACTIVE_THREADS):
				try:
					t.join(timeout=0.2)
				except Exception:
					pass
			continue

		if not line:
			continue

		parts = line.split()
		cmd = parts[0]

		try:
			match cmd:
				case "create":
					if len(parts) != 3:
						print("usage: create USER PASS")
					else:
						cmd_create(parts[1], parts[2])

				case "login":
					if len(parts) != 3:
						print("usage: login USER PASS")
					else:
						cmd_login(parts[1], parts[2])

				case "dctx":
					if len(parts) != 5:
						print("usage: dctx USER PASS SCENE CTX")
					else:
						cmd_delete_ctx(parts[1], parts[2], parts[3], parts[4])

				case "train":
					if len(parts) != 4:
						print("usage: train USER PASS CFG")
					else:
						cmd_train(parts[1], parts[2], parts[3])

				case "trains":
					triples = _parse_trains_args(parts)
					if triples is None:
						print("usage: trains USER1 PASS1 CFG1 USER2 PASS2 CFG2 ...")
					else:
						cmd_trains(triples)

				case "whoami":
					cmd_whoami()

				case "exit" | "quit":
					break

				case _:
					print("unknown command")

		except Exception as e:
			print("internal error:", e)

	# shutdown on exit
	STOP_EVENT.set()
	_force_close_all_ws()
	for t in list(ACTIVE_THREADS):
		try:
			t.join(timeout=0.5)
		except Exception:
			pass

	print("bye.")


if __name__ == "__main__":
	repl()
