
from onnxconverter_common.float16 import convert_float_to_float16 as quantize_fp16_model
from onnxruntime.quantization import quantize_dynamic, QuantType
import io
import torch
import tensorrt as trt
import torch.nn as nn
import traceback
from typing import Any, Dict, List, Optional, Union, Tuple
from .graph_core import Context, execute_graph
from .utils import pick_device, to_tensor
from .optim import _modules
import onnxruntime as ort
import onnx
import tempfile
import os

import numpy as np
import onnxruntime as ort

import tensorrt as trt
def export_to_tensorrt(
	graph: Dict[str, Any],
	ctx: Context,
	input_shape: Tuple[int, ...],
	output_branches: Optional[List[str]] = None,
	quantization: str = "none",
	precision: str = "fp16",
	max_workspace_size: int = 1 << 30,  # 1 GB
	fp16: bool = True,
	int8: bool = False,
	input_names: Optional[List[str]] = None,
	output_names: Optional[List[str]] = None,
	metadata: Optional[Dict[str, str]] = None,
	verbose: bool = False,
	**kwargs
) -> Dict[str, Any]:

	device = pick_device(ctx)

	# 1. Export to ONNX in-memory
	onnx_result = export_to_onnx(
		graph,
		ctx,
		input_shape,
		output_branches=output_branches,
		quantization="none",
		metadata=metadata,
	)
	if not onnx_result.get("success", False):
		return {"success": False, "error": "ONNX export failed", "details": onnx_result}
	wrapper = ONNXExportWrapper(graph, ctx, output_branches)

	onnx_bytes = (
		onnx_result["bytes"].getvalue()
		if isinstance(onnx_result["bytes"], io.BytesIO)
		else onnx_result["bytes"]
	)
	output_mapping = onnx_result.get("output_mapping", {})
	output_branches = onnx_result.get("output_branches", [])
	output_names = onnx_result.get("output_names", [])
	input_names = onnx_result.get("input_names", [])

	# 2. TensorRT build (TRT 9+ API)
	logger = trt.Logger(trt.Logger.VERBOSE if verbose else trt.Logger.WARNING)
	builder = trt.Builder(logger)
	flags = 1 << int(trt.NetworkDefinitionCreationFlag.EXPLICIT_BATCH)
	network = builder.create_network(flags)
	parser = trt.OnnxParser(network, logger)

	if not parser.parse(onnx_bytes):
		errors = "\n".join(str(parser.get_error(i)) for i in range(parser.num_errors))
		return {"success": False, "error": "ONNX parse failed", "details": errors}

	config = builder.create_builder_config()
	config.set_memory_pool_limit(trt.MemoryPoolType.WORKSPACE, max_workspace_size)

	if fp16 and builder.platform_has_fast_fp16:
		config.set_flag(trt.BuilderFlag.FP16)
	if int8 and builder.platform_has_fast_int8:
		config.set_flag(trt.BuilderFlag.INT8)

	try:
		serialized = builder.build_serialized_network(network, config)
		if serialized is None:
			return {"success": False, "error": "TensorRT engine build failed"}
		engine_bytes = io.BytesIO(serialized)
	except Exception as e:
		return {"success": False, "error": str(e), "traceback": traceback.format_exc()}
	finally:
		finalize_export(ctx, wrapper)

	return {
		"success": True,
		"bytes": engine_bytes,
		"input_shape": input_shape,
		"input_names": input_names,
		"output_names": output_names,
		"output_branches": output_branches,
		"output_mapping": output_mapping,
		"precision": "fp16" if fp16 else "fp32",
		"quantization": quantization,
		"backend": "tensorrt",
		"metadata": metadata or {},
	}


#import tensorrt as trt

class ONNXExportWrapper(nn.Module):
	def __init__(self, graph: Dict[str, Any], ctx: Context, output_branches: Optional[List[str]] = None):
		super().__init__()
		self.graph = graph
		self.ctx = ctx
		self.output_branches = output_branches
		module_cache = _modules(ctx)
		for key, module in module_cache.items():
			safe_key = key.replace("|", "_").replace("=", "_").replace(" ", "_").replace(":", "_")
			self.add_module(safe_key, module)

	def forward(self, x: torch.Tensor) -> Union[torch.Tensor, Tuple[torch.Tensor, ...]]:
		pages = self.graph.get("pages", {})
		if not pages:
			raise ValueError("Graph has no pages")
		page_keys = sorted(pages.keys(), key=lambda k: int(k) if k.isdigit() else k)
		first_page = pages[page_keys[0]]
		input_node_id = None
		for node_id, node_data in first_page.items():
			if node_data.get("type") == "InputNode":
				input_node_id = node_id
				break
		if input_node_id is None:
			raise ValueError("No InputNode found in graph")
		first_page[input_node_id]["props"]["raw_values"] = x
		# warmup run
		execute_graph(self.graph, self.ctx)
		result = execute_graph(self.graph, self.ctx)
		outputs = []
		output_node_ids = []
		if self.output_branches:
			for branch_id in self.output_branches:
				if branch_id in result.branch_heads:
					tensor = self._extract_tensor_from_branch(result.branch_heads[branch_id])
					if tensor is not None:
						outputs.append(tensor)
						output_node_ids.append(branch_id)
		else:
			for branch_id, branch_data in result.branch_heads.items():
				tensor = self._extract_tensor_from_branch(branch_data)
				if tensor is not None:
					outputs.append(tensor)
					output_node_ids.append(branch_id)
		if not outputs:
			raise ValueError(f"No valid outputs found. Branch heads: {list(result.branch_heads.keys())}")
		self._last_output_mapping = output_node_ids
		return outputs[0] if len(outputs) == 1 else tuple(outputs)

	def _extract_tensor_from_branch(self, branch_data: Dict[str, Any]) -> Optional[torch.Tensor]:
		if not branch_data:
			return None
		for port_name, port_data in branch_data.items():
			if isinstance(port_data, list):
				for item in port_data:
					if isinstance(item, dict) and "tensor" in item:
						return item["tensor"]
			elif isinstance(port_data, dict):
				if "tensor" in port_data:
					return port_data["tensor"]
		return None


def quantize_onnx_model(
	model_bytes: io.BytesIO,
	mode: str = "none"
) -> Dict[str, Any]:
	if mode is None or str(mode).lower() == "none" or str(mode) == "":
		return {"success": True, "quantization": "none", "bytes": model_bytes}

	mode = str(mode).lower()
	try:
		model_bytes.seek(0)
		model = onnx.load_model_from_string(model_bytes.read())
		out_buffer = io.BytesIO()

		if mode == "float16":
			model_fp16 = quantize_fp16_model(model)
			onnx.save_model(model_fp16, out_buffer)
			out_buffer.seek(0)
			return {"success": True, "quantization": mode, "bytes": out_buffer}

		elif mode == "int8" or mode == "int16":
			with tempfile.TemporaryDirectory() as tmpdir:
				in_path = os.path.join(tmpdir, "in.onnx")
				out_path = os.path.join(tmpdir, "out.onnx")
				onnx.save_model(model, in_path)
				qtype = QuantType.QInt8 if mode == "int8" else QuantType.QInt16

				quantize_dynamic(
					model_input=in_path,
					model_output=out_path,
					weight_type=qtype
				)
				with open(out_path, "rb") as f:
					out_buffer.write(f.read())

			out_buffer.seek(0)
			return {"success": True, "quantization": mode, "bytes": out_buffer}

		else:
			return {"success": False, "error": f"Unsupported quantization mode: {mode}"}

	except Exception as e:
		return {"success": False, "error": str(e), "traceback": traceback.format_exc()}



def export_to_onnx(
	graph: Dict[str, Any],
	ctx: Context,
	input_shape: Tuple[int, ...],
	output_branches: Optional[List[str]] = None,
	opset_version: int = 14,
	input_names: Optional[List[str]] = None,
	output_names: Optional[List[str]] = None,
	dynamic_axes: Optional[Dict[str, Dict[int, str]]] = None,
	verbose: bool = False,
	quantization: str = "none",
	metadata: Optional[Dict[str, str]] = None,
	**export_kwargs
) -> Dict[str, Any]:
	device = pick_device(ctx)
	wrapper = ONNXExportWrapper(graph, ctx, output_branches)
	wrapper.eval()
	wrapper.to(device)
	ctx.extra["exporting"] = True
	dummy_input = torch.randn(*input_shape, device=device)
	try:
		with torch.no_grad():
			_ = wrapper(dummy_input)
		actual_branches = wrapper._last_output_mapping
		num_outputs = len(actual_branches) if hasattr(actual_branches, "__len__") else 1
	except Exception as e:
		finalize_export(ctx, wrapper)
		return {"success": False, "error": f"Forward pass failed: {str(e)}", "input_shape": input_shape}
	if input_names is None:
		input_names = ["input"]
	if output_names is None:
		if num_outputs == 1:
			output_names = ["output"]
		else:
			output_names = [f"output_{i}" for i in range(num_outputs)]
	if len(output_names) != num_outputs:
		output_names = [f"output_{i}" for i in range(num_outputs)]
	buffer = io.BytesIO()
	try:
		wrapper.eval()
		for p in wrapper.parameters():
			p.requires_grad = False
		torch.onnx.export(
			wrapper,
			dummy_input,
			buffer,
			input_names=input_names,
			output_names=output_names,
			dynamic_axes=dynamic_axes,
			opset_version=opset_version,
			export_params=True,
			do_constant_folding=True,
			verbose=verbose,
			**export_kwargs
		)
		buffer.seek(0)
		if metadata:
			model = onnx.load_model_from_string(buffer.read())
			for key, value in metadata.items():
				meta = model.metadata_props.add()
				meta.key = key
				meta.value = str(value)
			modified_buffer = io.BytesIO()
			onnx.save_model(model, modified_buffer)
			modified_buffer.seek(0)
			buffer = modified_buffer
		q_result = {"success": True, "bytes": buffer}
		if quantization and str(quantization).lower() != "none":
			q_result = quantize_onnx_model(buffer, quantization)
		output_mapping = {name: node_id for name, node_id in zip(output_names, actual_branches)}
		finalize_export(ctx, wrapper)
		return {
			"success": True,
			"bytes": q_result.get("bytes", buffer),
			"output_branches": actual_branches,
			"output_mapping": output_mapping,
			"input_shape": input_shape,
			"input_names": input_names,
			"output_names": output_names,
			"opset_version": opset_version,
			"num_outputs": num_outputs,
			"quantization": quantization,
			"quantization_result": q_result,
			"metadata": metadata or {}
		}
	except Exception as e:

		return {"success": False, "error": str(e), "traceback": traceback.format_exc()}




def finalize_export(ctx: Context, wrapper):
	wrapper.eval()
	for i in wrapper.parameters():
		i.requires_grad = True

	ctx.extra["exporting"] = False



def validate_onnx_export(
	model_bytes: io.BytesIO,
	graph: Dict[str, Any],
	ctx: Context,
	input_shape: Tuple[int, ...],
	tolerance: float = 1e-5,
	test_inputs: Optional[List[torch.Tensor]] = None
) -> Dict[str, Any]:
	device = pick_device(ctx)
	if test_inputs is None:
		test_inputs = [torch.randn(*input_shape, device=device)]

	try:
		model_bytes.seek(0)
		session = ort.InferenceSession(model_bytes.read())

		all_max_diffs, all_mean_diffs = [], []

		for test_input in test_inputs:
			pages = graph.get("pages", {})
			page_keys = sorted(pages.keys(), key=lambda k: int(k) if k.isdigit() else k)
			first_page = pages[page_keys[0]]

			for node_id, node_data in first_page.items():
				if node_data.get("type") == "InputNode":
					first_page[node_id]["props"]["raw_values"] = test_input
					break

			result = execute_graph(graph, ctx)
			pt_outputs = []
			for branch_id, branch_data in result.branch_heads.items():
				for port_name, port_data in branch_data.items():
					if isinstance(port_data, list):
						for item in port_data:
							if isinstance(item, dict) and "tensor" in item:
								pt_outputs.append(item["tensor"].detach().cpu().numpy())
								break
					elif isinstance(port_data, dict) and "tensor" in port_data:
						pt_outputs.append(port_data["tensor"].detach().cpu().numpy())

			ort_inputs = {session.get_inputs()[0].name: test_input.cpu().numpy()}
			ort_outputs = session.run(None, ort_inputs)

			if len(pt_outputs) != len(ort_outputs):
				return {
					"success": False,
					"error": f"Output count mismatch: PyTorch={len(pt_outputs)}, ONNX={len(ort_outputs)}"
				}

			max_diffs, mean_diffs = [], []
			for pt_out, onnx_out in zip(pt_outputs, ort_outputs):
				abs_diff = np.abs(pt_out - onnx_out)
				max_diffs.append(float(abs_diff.max()))
				mean_diffs.append(float(abs_diff.mean()))

			all_max_diffs.append(max_diffs)
			all_mean_diffs.append(mean_diffs)

		max_of_max = [max(diffs[i] for diffs in all_max_diffs) for i in range(len(all_max_diffs[0]))]
		mean_of_mean = [np.mean([diffs[i] for diffs in all_mean_diffs]) for i in range(len(all_mean_diffs[0]))]
		all_close = all(d <= tolerance for d in max_of_max)

		return {
			"success": all_close,
			"max_differences": max_of_max,
			"mean_differences": mean_of_mean,
			"tolerance": tolerance,
			"num_outputs": len(pt_outputs),
			"num_test_inputs": len(test_inputs)
		}

	except Exception as e:
		return {"success": False, "error": str(e), "traceback": traceback.format_exc()}