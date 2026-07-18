from __future__ import annotations
import time
from typing import Any, Dict, Callable
import nns.model_core as nodes
import traceback
import os
import nns.onnx_exporter as onnx_exporter
from google import genai
from google.genai import types
import yolks.packer as appify
from contextlib import suppress

Emit = Callable[[Dict[str, Any]], None]


def load_graph(**arguments):
	nodes.execute_graph(arguments["graph"], arguments["context"])
	if "train_graph" in arguments:
		nodes.execute_graph(arguments["train_graph"], arguments["context"].nested)
	nodes.load_model(arguments["context"], arguments["load_from"])

def save_graph_model(**arguments):
	nodes.save_model(arguments["context"], arguments["save_into"])



from faster_whisper import WhisperModel


MODEL = None

def init_whisper():
    global MODEL
    if MODEL: return MODEL
    MODEL = WhisperModel("small", device="cuda", compute_type="int8_float16")
    # warm-up on silence
    dummy = np.zeros((16000 * 2, 1), dtype=np.float32)
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    write(tmp.name, 16000, (dummy * 32767).astype("int16"))
    MODEL.transcribe(tmp.name, beam_size=1, vad_filter=True)
    print("[I] whisper ready")
    return MODEL


import numpy as np
import tempfile

from scipy.io.wavfile import write



def is_silent(audio: np.ndarray, sr: int) -> bool:
    if audio.size == 0 or not np.isfinite(audio).all():
        return True
    if len(audio) < sr * 0.5:
	    return False

    frame_len = int(0.05 * sr)
    hop = int(0.025 * sr)
    if len(audio) < frame_len:
        return np.sqrt(np.mean(audio ** 2)) < 1e-4

    rms_vals = []
    for i in range(0, len(audio) - frame_len, hop):
        frame = audio[i : i + frame_len]
        rms_vals.append(np.sqrt(np.mean(frame ** 2)))

    rms_vals = np.array(rms_vals)
    if rms_vals.size == 0:
        return True

    noise_floor = np.percentile(rms_vals, 20)
    noise_db = 20 * np.log10(noise_floor + 1e-9)

    thresh_db = noise_db + 10.0
    overall_rms_db = 20 * np.log10(np.sqrt(np.mean(audio ** 2)) + 1e-9)

    return overall_rms_db < thresh_db


def transcribe_batch_task(emit, recv, arguments):
	model = init_whisper()  # your warm preloaded singleton
	out = []
	for item in arguments["batch"]:
		audio = item["audio"]
		sr = int(item["sample_rate"])
		# Guard against bad inputs
		if audio is None or audio.size == 0:
		    out.append({"text": "", "lang": "en"})
		    continue
		#if is_silent(audio, sr):
		#    out.append({"text": "", "lang": "en"})
		#    continue
		# Faster-Whisper supports raw arrays + sample_rate
		use_vad = True
		if len(audio) < 16000 * 5:  # <3 seconds
			use_vad = False
		segments, info = model.transcribe(
		    audio=audio,
		    language=None,                 # let it auto-detect
		    beam_size=5,
		    patience=0.1,
		    temperature=0.3,
		    vad_filter=use_vad,
			vad_parameters=dict(
				threshold=0.5,  # default is safer for short audio
				min_speech_duration_ms=100,  # allow very short words/grunts/commands
				min_silence_duration_ms=200,  # detect boundaries faster
			),
		    word_timestamps=False,
		    condition_on_previous_text=False,  # avoid bias across segments
		    initial_prompt="МНИСТ распознавать цифр собрать модель датасет тренировка оптимизатор граф",
		)
		text = "".join(s.text for s in segments) if segments else ""
		out.append({"text": text.strip(), "lang": getattr(info, "language", "en") or "en"})

	return {"batch": out}



def decode_column(encoded: bytes, meta: dict) -> list:
    """Decode one column from adaptive RAW/RLE stream with numeric bias."""
    payload = rle_decode_adaptive(encoded)
    dtype = meta["dtype"]

    if dtype == "num":
        mn = int(meta.get("min", 0))
        bits = int(meta.get("bits", 0))  # 8,16,32 preferred; 0 => infer or bit-packed fallback
        if bits in (8, 16, 32):
            step = bits // 8
            if step == 0:
                raise ValueError("invalid bits for numeric column")
            if len(payload) % step != 0:
                raise ValueError("numeric column payload size mismatch")

            out = []
            if step == 1:
                # single byte offsets
                out = [mn + b for b in payload]
            elif step == 2:
                # big-endian 16-bit
                n = len(payload)
                out = [mn + ((payload[i] << 8) | payload[i + 1]) for i in range(0, n, 2)]
            else:
                # big-endian 32-bit
                n = len(payload)
                out = [mn + ((payload[i] << 24) | (payload[i + 1] << 16) | (payload[i + 2] << 8) | payload[i + 3])
                       for i in range(0, n, 4)]
            return out

        # Fallback: legacy bit-packed (rare in your new builds)
        packed_bits = int(meta.get("packed_bits", 0)) or int(meta.get("bits", 0))
        if packed_bits > 0:
            cnt = int(meta.get("_rows", 0))
            offsets = bit_unpack(payload, packed_bits, cnt)
            return [mn + v for v in offsets]

        # Heuristic inference if neither bits nor packed_bits present
        cnt = int(meta.get("_rows", 0))
        if cnt > 0:
            if len(payload) == cnt:
                return [mn + b for b in payload]
            elif len(payload) == cnt * 2:
                out = []
                for i in range(0, len(payload), 2):
                    out.append(mn + ((payload[i] << 8) | payload[i + 1]))
                return out
            elif len(payload) == cnt * 4:
                out = []
                for i in range(0, len(payload), 4):
                    out.append(mn + ((payload[i] << 24) | (payload[i + 1] << 16) | (payload[i + 2] << 8) | payload[i + 3]))
                return out

        # Last ditch fallback
        raise ValueError("cannot infer numeric decoding parameters")

    elif dtype == "float":
        return dequantize_float_column(payload)

    elif dtype == "image":
        pixels = int(meta["pixels"])  # expect provided in header for images
        return decode_image_column(payload, pixels)

    elif dtype == "text":
        chunks = payload.split(b"\x00")
        return [c.decode("utf-8", errors="ignore") for c in chunks if c]

    else:
        raise ValueError(f"Unknown dtype: {dtype}")


def decode_image_column(byte_stream: bytes, pixels_per_image: int):
    if len(byte_stream) % pixels_per_image != 0:
        raise ValueError("image column size mismatch")

    rows = len(byte_stream) // pixels_per_image
    out = []

    idx = 0
    for _ in range(rows):
        img = byte_stream[idx: idx + pixels_per_image]
        out.append(list(img))
        idx += pixels_per_image

    return out



def bit_unpack(data: bytes, bits: int, count: int) -> list[int]:
    """Unpack `count` integers packed with `bits` bits each."""
    out = []
    total_bits = len(data) * 8

    bit_pos = 0
    mask = (1 << bits) - 1

    for _ in range(count):
        if bit_pos + bits > total_bits:
            raise ValueError("bit-packed integer column truncated")

        value = 0
        for b in range(bits):
            byte_i = (bit_pos + b) >> 3
            bit_i  = 7 - ((bit_pos + b) & 7)
            bit = (data[byte_i] >> bit_i) & 1
            value = (value << 1) | bit

        out.append(value)
        bit_pos += bits

    return out


def rle_decode(data: bytes) -> bytes:
    out = bytearray()
    i = 0
    n = len(data)

    while i < n:
        if i + 2 >= n:
            raise ValueError("RLE corrupted: truncated run header")

        run_len = (data[i] << 8) | data[i+1]
        value = data[i+2]
        i += 3

        out.extend([value] * run_len)

    return bytes(out)


def rle_decode_adaptive(data: bytes) -> bytes:
    if not data:
        return b""

    flag = data[0]
    payload = data[1:]

    if flag == 0:
        # Raw
        return payload
    elif flag == 1:
        return rle_decode(payload)
    else:
        raise ValueError(f"Invalid RLE flag byte: {flag}")


def dequantize_float_column(byte_stream: bytes) -> list[float]:
    return [b / 255.0 for b in byte_stream]


from ds_decompressor import decompress_dataset as rust_decompress_dataset


def decompress_dataset(packet: dict):

	print(packet)
	return rust_decompress_dataset(packet)
	"""
	Decode dataset from either legacy single-column blobs or
	new block-based structure (list of RLE blocks per column).
	"""
	header = packet["header"]
	data_inputs, data_outputs = packet["data"]

	rows = header["rows"]
	inputs_count = header["inputs_count"]
	outputs_count = header["outputs_count"]
	col_meta = header["columns"]

	# inject row count for convenience
	for c in col_meta.values():
	    c["_rows"] = rows

	# ---- helper to flatten & decode one column ----
	def _decode_col(maybe_blocks, meta):
	    """
		maybe_blocks can be:
		  - bytes/bytearray: legacy single-stream (one adaptive header total)
		  - list[bytes]: block mode (each block has its own adaptive header)
		"""
	    if isinstance(maybe_blocks, (bytes, bytearray)):
		    return decode_column(bytes(maybe_blocks), meta)

	    if isinstance(maybe_blocks, list):
		    col = []
		    for blk in maybe_blocks:
			    if not blk:
				    continue
			    part = decode_column(blk, meta)  # decode per block
			    # part is a list of row values (num/float/text/image-row)
			    col.extend(part)
		    return col

	    raise TypeError(f"Unexpected column format: {type(maybe_blocks)}")

	# ---- decode all inputs ----
	decoded_inputs = []
	for c in range(inputs_count):
	    col_key = str(c)
	    decoded_inputs.append(_decode_col(data_inputs[c], col_meta[col_key]))

	# ---- decode all outputs ----
	decoded_outputs = []
	for c in range(outputs_count):
	    col_key = str(c + inputs_count)
	    decoded_outputs.append(_decode_col(data_outputs[c], col_meta[col_key]))

	# ---- build dataset row tuples ----
	dataset = []
	for r in range(rows):
	    inp_vec = [decoded_inputs[i][r] for i in range(inputs_count)]
	    out_vec = [decoded_outputs[j][r] for j in range(outputs_count)]
	    dataset.append((inp_vec, out_vec))

	#print(dataset[:50])
	return dataset









def make_tools(client: google.genai.Client, *funcs: Callable) -> List[types.Tool]:
	fdecls = [types.FunctionDeclaration.from_callable(client=client, callable=f) for f in funcs]
	return [types.Tool(function_declarations=fdecls)]


import traceback
import json

def ds_load_task(emit, recv, arguments):
	"""
	Runs in a Pebble worker.
	Receives streamed dataset parts, assembles cache, and decompresses dataset.
	"""
	try:
	    user_id = arguments["user_id"]
	    dataset_id = arguments["dataset_id"]
	    client_hashes = arguments["client_hashes"]
	    hash_algo = arguments["hash_algo"]
	    header = arguments["header"]
	    frames = arguments["frames"]  # list of binary messages

	    app_ctx = arguments["app_ctx"]
	    cache_root = app_ctx.ds_cache.setdefault(user_id, {})
	    ds_entry = cache_root.setdefault(dataset_id, {
	        "inputs": [], "outputs": [], "header": {}, "hashes": {"inputs": [], "outputs": []}
	    })
	    ds_entry["header"] = header
	    ds_entry["hash_algo"] = hash_algo

	    # --- apply incoming frames ---
	    for msg in frames:
	        header_len = int.from_bytes(msg[:2], "big")
	        #print(msg[2:2 + header_len])
	        meta = json.loads(msg[2:2 + header_len])
	        payload = msg[2 + header_len:]

	        side, col, blk = meta["side"], int(meta["col"]), int(meta["blk"])
	        client_hash = client_hashes[side][col][blk]

	        while len(ds_entry[side]) <= col:
	            ds_entry[side].append([])
	            ds_entry["hashes"][side].append([])

	        cols_blocks = ds_entry[side]
	        cols_hashes = ds_entry["hashes"][side]
	        while len(cols_blocks[col]) <= blk:
	            cols_blocks[col].append(b"")
	            cols_hashes[col].append("")

	        cols_blocks[col][blk] = payload
	        cols_hashes[col][blk] = client_hash

	    # --- persist updated entry ---
	    cache_root[dataset_id] = ds_entry

	    # --- decompress (heavy) ---
	    packet = {"header": header, "data": [ds_entry["inputs"], ds_entry["outputs"]]}
	    dataset = decompress_dataset(packet)

	    return {"status": "ok", "rows": len(dataset), "preview": dataset[:10], "dataset": dataset}
	except Exception as e:
		traceback.print_exc()
		return {"status": "error", "error": str(e), "trace": traceback.format_exc(), "dataset": ""}






from axon.genai_helpers import run_with_tools


def world_state(what: str) -> str:
	return "### WORLD STATE\nWhat follows is **current, live** world state:\n```{world_state}```\n\n".replace("{world_state}", str(what))


mnist_text =  """
<change_nodes>
[
  {"tag": "model_mnist_cnn", "type": "model_name", "config": {"name": "mnist_cnn"}},
  {"tag": "input_image_small_0", "type": "input_image_small", "config": {}},
  {"tag": "activation_relu_1", "type": "activation", "config": {"activ": "relu"}},
  {"tag": "conv2d_layer_1", "type": "conv2d_layer", "config": {"filters": 32, "window": 3, "stride": 1}},
  {"tag": "maxpool_layer_1", "type": "maxpool_layer", "config": {"group": 2}},
  {"tag": "activation_relu_2", "type": "activation", "config": {"activ": "relu"}},
  {"tag": "conv2d_layer_2", "type": "conv2d_layer", "config": {"filters": 64, "window": 3, "stride": 1}},
  {"tag": "maxpool_layer_2", "type": "maxpool_layer", "config": {"group": 2}},
  {"tag": "flatten_1", "type": "flatten", "config": {}},
  {"tag": "activation_relu_3", "type": "activation", "config": {"activ": "relu"}},
  {"tag": "dense_layer_128", "type": "dense_layer", "config": {"neuron_amount": 128}},
  {"tag": "dense_layer_10", "type": "dense_layer", "config": {"neuron_amount": 10}},
  {"tag": "softmax_1", "type": "softmax", "config": {}},
  {"tag": "out_labels_digits", "type": "out_labels", "config": {"label_names": ["0","1","2","3","4","5","6","7","8","9"], "title": "digits"}},
  {"tag": "load_dataset_mnist", "type": "load_dataset", "config": {"dataset_name": "mnist"}},
  {"tag": "train_begin_0", "type": "train_begin", "config": {}},
  {"tag": "run_model_0", "type": "run_model", "config": {"branches": {"digits": "cross_entropy"}, "mapped": {"digits": "digit"}}},
  {"tag": "output_map_0", "type": "output_map", "config": {}},
  {"tag": "train_step_0", "type": "train_step", "config": {"optimizer": "adam", "lr": 1, "momentum": 0.0, "weight_decay": 0}}
]
</change_nodes>


<connect_ports>
[
  {"from": {"tag": "model_mnist_cnn", "port": 0}, "to": {"tag": "input_image_small_0", "port": 0}},
  {"from": {"tag": "input_image_small_0", "port": 0}, "to": {"tag": "conv2d_layer_1", "port": 1}},
  {"from": {"tag": "activation_relu_1", "port": 0}, "to": {"tag": "conv2d_layer_1", "port": 0}},
  {"from": {"tag": "conv2d_layer_1", "port": 0}, "to": {"tag": "maxpool_layer_1", "port": 0}},
  {"from": {"tag": "maxpool_layer_1", "port": 0}, "to": {"tag": "conv2d_layer_2", "port": 1}},
  {"from": {"tag": "activation_relu_2", "port": 0}, "to": {"tag": "conv2d_layer_2", "port": 0}},
  {"from": {"tag": "conv2d_layer_2", "port": 0}, "to": {"tag": "maxpool_layer_2", "port": 0}},
  {"from": {"tag": "maxpool_layer_2", "port": 0}, "to": {"tag": "flatten_1", "port": 0}},
  {"from": {"tag": "flatten_1", "port": 0}, "to": {"tag": "dense_layer_128", "port": 1}},
  {"from": {"tag": "activation_relu_3", "port": 0}, "to": {"tag": "dense_layer_128", "port": 0}},
  {"from": {"tag": "dense_layer_128", "port": 0}, "to": {"tag": "dense_layer_10", "port": 1}},
  {"from": {"tag": "dense_layer_10", "port": 0}, "to": {"tag": "softmax_1", "port": 0}},
  {"from": {"tag": "softmax_1", "port": 0}, "to": {"tag": "out_labels_digits", "port": 0}},
  {"from": {"tag": "load_dataset_mnist", "port": 0}, "to": {"tag": "train_begin_0", "port": 0}},
  {"from": {"tag": "train_begin_0", "port": 0}, "to": {"tag": "run_model_0", "port": 0}},
  {"from": {"tag": "model_mnist_cnn", "port": 0}, "to": {"tag": "run_model_0", "port": 1}},
  {"from": {"tag": "run_model_0", "port": 0}, "to": {"tag": "output_map_0", "port": 0}},
  {"from": {"tag": "output_map_0", "port": 0}, "to": {"tag": "train_step_0", "port": 0}}
]
</connect_ports>

<delete_nodes>
[]
</delete_nodes>

<disconnect_ports>
[]
</disconnect_ports>

"""


def talk_task(emit, recv, arguments):
	result = {"status": "error", "text": ""}
	killed = False
	func_called = False

	def _on_kill():
		nonlocal killed
		killed = True
		emit({"phase": "stopped"})

	recv.on_kill(_on_kill)

	try:
		narrator_summary: dict = arguments["summary"].setdefault("nodes", {})
		builder_summary: dict[str, dict] = {"nodes": narrator_summary.copy(), "edges": arguments["summary"].setdefault("edges", {})}
		for node in builder_summary["nodes"]:
			if "outputs" in builder_summary["nodes"][node]:
				orig = builder_summary["nodes"][node].copy()
				orig.pop("outputs")
				builder_summary["nodes"][node] = orig

		client = arguments["client"]
		contents = arguments["content"]
		system_text = arguments.get("system", "") + world_state(narrator_summary)
		builder_text = arguments.get("for_builder", "") + world_state(builder_summary)

		def emit_wrapper(emit_what: dict):
			if killed or recv.closed:
				return
			if emit_what.get("phase", "") == "text":
				result["text"] += emit_what["text"]
				print(emit_what["text"], end="")
			emit(emit_what)

		builder_debounce = {"locked": False, "pending_plan": None}
		auto_debounce = {"pending": ""}

		def build_graph(plan: str):
			if killed or recv.closed:
				return '{"status": "aborted"}'
			nonlocal func_called
			if func_called:
				return '{"status": "already_called"}'
			func_called = True
			builder_debounce["pending_plan"] = plan
			return '{"status": "Build complete!"}'

		def build_graph_digit_2_conv():
			if killed or recv.closed:
				return '{"status": "aborted"}'
			nonlocal func_called
			if func_called:
				return '{"status": "already_called"}'
			func_called = True
			auto_debounce["pending"] = mnist_text
			return '{"status": "Build complete!"}'

		if killed or recv.closed:
			emit({"phase": "stopped"})
			return {"status": "stopped"}

		tool_registry = {"build_graph": build_graph, "build_graph_digit_2_conv": build_graph_digit_2_conv}

		# run streaming orchestrator
		ran_result = run_with_tools(
			client=client,
			model="gemini-2.5-flash",
			history=contents,
			tool_registry=tool_registry,
			emit=emit_wrapper,
			system_text=system_text,
			max_tool_rounds=1,
			should_stop=lambda: killed or recv.closed,
		)

		if builder_debounce["pending_plan"] and not killed and not recv.closed:
			plan = builder_debounce["pending_plan"]
			run_with_tools(
				client=client,
				model="gemini-2.5-flash",
				history=[f"PLAN: {plan}", "BUILDER:"],
				tool_registry={},  # no nested tools
				emit=emit_wrapper,
				system_text=builder_text,
				should_stop=lambda: killed or recv.closed,
			)
		#print(auto_debounce)
		if auto_debounce["pending"]:
			print("runnin...")
			emit_wrapper({"text": auto_debounce["pending"], "phase": "text"})
			time.sleep(3)

		#if result["text"].count("<thinking>") != result["text"].count("</thinking>"):
		#	result["text"] += "</thinking>"

		if not killed and not recv.closed:
			result["status"] = "ok"
		else:
			result["status"] = "stopped"

	except Exception as e:
		print("\n".join(traceback.format_exception(e)))
	finally:
		if not killed:
			emit({"phase": "end", "text": ""})
		else:
			emit({"phase": "stopped"})
	result["func_called"] = func_called
	#if result["text"].count("</thinking>") > 1:
	result["text"]
	if result["text"].count("</thinking>") != result["text"].count("<thinking>"):
		#print("zohran")
		emit_wrapper({"phase": "text", "text": "</thinking>"})
	#print(result["text"])
	time.sleep(0.5)
	return result


def load_graph_task(emit: Emit, recv: Receiver, arguments: Dict[str, Any]) -> Dict[str, Any]:
	load_graph(graph=arguments["graph"], load_from=arguments["load_from"], context=arguments["context"])


from time import perf_counter

import io
