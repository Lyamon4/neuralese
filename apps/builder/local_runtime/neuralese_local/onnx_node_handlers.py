from __future__ import annotations

from math import ceil
from typing import Any, Callable, Dict, List

import numpy as np
from onnx import TensorProto, helper


NodeHandler = Callable[[Any, str, str, Dict[str, Any], Dict[str, Any], Dict[str, Any]], None]
LayerHandler = Callable[[Any, str, Dict[str, Any], Dict[str, Any]], None]

_NODE_HANDLERS: Dict[str, NodeHandler] = {}
_LAYER_HANDLERS: Dict[str, LayerHandler] = {}


def handles(*node_types: str) -> Callable[[NodeHandler], NodeHandler]:
    def decorator(func: NodeHandler) -> NodeHandler:
        for node_type in node_types:
            _NODE_HANDLERS[node_type] = func
        return func
    return decorator


def handles_layer(*layer_types: str) -> Callable[[LayerHandler], LayerHandler]:
    def decorator(func: LayerHandler) -> LayerHandler:
        for layer_type in layer_types:
            _LAYER_HANDLERS[layer_type] = func
        return func
    return decorator


def get_handler(node_type: str) -> NodeHandler | None:
    return _NODE_HANDLERS.get(str(node_type))


def _as_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except Exception:
        return int(default)


def _as_str(value: Any, default: str = "") -> str:
    if value is None:
        return default
    return str(value)


@handles("InputNode", "input_1d", "input_2d")
def compile_input(ctx, nid: str, ntype: str, props: Dict[str, Any], config: Dict[str, Any], emit: Dict[str, Any]) -> None:
    shape_val = _as_int(props.get("shape", config.get("shape", 784)), 784)
    rows = _as_int(config.get("rows", -1), -1)
    cols = _as_int(config.get("columns", -1), -1)
    current_shape: List[Any] = ["batch_size", shape_val]
    if rows > 0 and cols > 0:
        current_shape = ["batch_size", 1, rows, cols]
    if not any(info.name == "input" for info in ctx.inputs):
        ctx.inputs.append(helper.make_tensor_value_info("input", TensorProto.FLOAT, current_shape))
    ctx.tensor_routing.setdefault(nid, {})["input_out"] = "input"
    ctx.tensor_shapes["input"] = current_shape


@handles("NeuronLayer", "layer", "dense_layer")
def compile_neuron_layer(ctx, nid: str, ntype: str, props: Dict[str, Any], config: Dict[str, Any], emit: Dict[str, Any]) -> None:
    layer_type = _as_str(config.get("type", props.get("type", "dense")), "dense").lower()
    handler = _LAYER_HANDLERS.get(layer_type) or (_LAYER_HANDLERS.get("dense") if layer_type == "" else None)
    if handler is None:
        raise ValueError(f"Unsupported NeuronLayer type '{layer_type}' on node {nid}")
    handler(ctx, nid, props, config)


@handles_layer("dense", "linear", "")
def compile_dense_layer(ctx, nid: str, props: Dict[str, Any], config: Dict[str, Any]) -> None:
    incoming_tensor = ctx.first_input(nid, "layer_in", "model_in")
    incoming_shape = ctx.tensor_shapes.get(incoming_tensor, ["batch_size", 784])
    in_features = _as_int(incoming_shape[-1], 784)
    out_features = _as_int(config.get("units", props.get("neuron_count", props.get("neuron_amount", 64))), 64)
    w_name = f"w_{nid}"
    b_name = f"b_{nid}"
    output_name = f"tensor_{nid}_layer_out"
    limit = np.sqrt(6.0 / max(1, in_features + out_features))
    w_vals = np.random.uniform(-limit, limit, [out_features, in_features]).astype(np.float32)
    b_vals = np.zeros([out_features], dtype=np.float32)
    ctx.initializers.append(helper.make_tensor(w_name, TensorProto.FLOAT, [out_features, in_features], w_vals.flatten().tolist()))
    ctx.initializers.append(helper.make_tensor(b_name, TensorProto.FLOAT, [out_features], b_vals.tolist()))
    ctx.trainable_params.extend([w_name, b_name])
    ctx.onnx_nodes.append(helper.make_node("Gemm", inputs=[incoming_tensor, w_name, b_name], outputs=[output_name], transB=1, name=f"dense_{nid}"))
    current_shape = [incoming_shape[0], out_features]
    ctx.tensor_shapes[output_name] = current_shape
    ctx.tensor_routing.setdefault(nid, {})["layer_out"] = ctx.add_activation(nid, output_name, current_shape, config.get("activation", config.get("activ", "none")))


@handles_layer("conv2d", "convolution2d")
def compile_conv2d_layer(ctx, nid: str, props: Dict[str, Any], config: Dict[str, Any]) -> None:
    incoming_tensor = ctx.first_input(nid, "layer_in", "model_in")
    incoming_shape = ctx.tensor_shapes.get(incoming_tensor, ["batch_size", 784])
    if len(incoming_shape) == 2:
        features = _as_int(incoming_shape[1], 784)
        side = int(features ** 0.5)
        if side * side != features:
            raise ValueError(f"Conv2D node {nid} received flat feature count {features}, which is not square")
        reshape_out = f"tensor_{nid}_conv_in_reshape"
        shape_tensor = f"shape_tensor_{nid}_conv_in"
        ctx.initializers.append(helper.make_tensor(shape_tensor, TensorProto.INT64, [4], [0, 1, side, side]))
        ctx.onnx_nodes.append(helper.make_node("Reshape", inputs=[incoming_tensor, shape_tensor], outputs=[reshape_out], name=f"reshape_conv_in_{nid}"))
        incoming_tensor = reshape_out
        incoming_shape = ["batch_size", 1, side, side]
        ctx.tensor_shapes[incoming_tensor] = incoming_shape

    in_channels = _as_int(incoming_shape[1], 1)
    out_channels = _as_int(config.get("filters", 16), 16)
    kernel = _as_int(config.get("window", 3), 3)
    stride = _as_int(config.get("stride", config.get("step", 1)), 1)
    keep_size = bool(config.get("keep_size", True))
    w_name = f"w_{nid}"
    b_name = f"b_{nid}"
    output_name = f"tensor_{nid}_layer_out"
    w_shape = [out_channels, in_channels, kernel, kernel]
    limit = np.sqrt(6.0 / max(1, in_channels * kernel * kernel + out_channels * kernel * kernel))
    ctx.initializers.append(helper.make_tensor(w_name, TensorProto.FLOAT, w_shape, np.random.uniform(-limit, limit, w_shape).astype(np.float32).flatten().tolist()))
    ctx.initializers.append(helper.make_tensor(b_name, TensorProto.FLOAT, [out_channels], np.zeros([out_channels], dtype=np.float32).tolist()))
    ctx.trainable_params.extend([w_name, b_name])
    conv_attrs = {"kernel_shape": [kernel, kernel], "strides": [stride, stride]}
    if keep_size:
        conv_attrs["auto_pad"] = "SAME_UPPER"
    else:
        conv_attrs["pads"] = [0, 0, 0, 0]
    ctx.onnx_nodes.append(helper.make_node("Conv", inputs=[incoming_tensor, w_name, b_name], outputs=[output_name], name=f"conv_{nid}", **conv_attrs))
    h_in = _as_int(incoming_shape[2], 1)
    w_in = _as_int(incoming_shape[3], 1)
    if keep_size:
        h_out = int(ceil(h_in / max(1, stride)))
        w_out = int(ceil(w_in / max(1, stride)))
    else:
        h_out = int((h_in - kernel) // max(1, stride) + 1)
        w_out = int((w_in - kernel) // max(1, stride) + 1)
    current_shape = [incoming_shape[0], out_channels, h_out, w_out]
    ctx.tensor_shapes[output_name] = current_shape
    ctx.tensor_routing.setdefault(nid, {})["layer_out"] = ctx.add_activation(nid, output_name, current_shape, config.get("activation", "none"))


@handles_layer("maxpool2d")
def compile_maxpool2d_layer(ctx, nid: str, props: Dict[str, Any], config: Dict[str, Any]) -> None:
    incoming_tensor = ctx.first_input(nid, "layer_in")
    incoming_shape = ctx.tensor_shapes.get(incoming_tensor, ["batch_size", 1, 28, 28])
    if len(incoming_shape) != 4:
        raise ValueError(f"MaxPool2D node {nid} expected a 4D tensor, got {incoming_shape}")
    kernel = _as_int(config.get("group", 2), 2)
    output_name = f"tensor_{nid}_layer_out"
    ctx.onnx_nodes.append(helper.make_node("MaxPool", inputs=[incoming_tensor], outputs=[output_name], kernel_shape=[kernel, kernel], strides=[kernel, kernel], name=f"maxpool_{nid}"))
    current_shape = [incoming_shape[0], incoming_shape[1], _as_int(incoming_shape[2], 1) // kernel, _as_int(incoming_shape[3], 1) // kernel]
    ctx.tensor_shapes[output_name] = current_shape
    ctx.tensor_routing.setdefault(nid, {})["layer_out"] = output_name


@handles_layer("dropout")
def compile_dropout_layer(ctx, nid: str, props: Dict[str, Any], config: Dict[str, Any]) -> None:
    incoming_tensor = ctx.first_input(nid, "layer_in", "model_in")
    incoming_shape = ctx.tensor_shapes.get(incoming_tensor, ["batch_size", 784])
    p = float(config.get("p", 0.5))
    output_name = f"tensor_{nid}_layer_out"
    ratio_name = f"ratio_{nid}"
    ctx.initializers.append(helper.make_tensor(ratio_name, TensorProto.FLOAT, [], [p]))
    ctx.onnx_nodes.append(helper.make_node("Dropout", inputs=[incoming_tensor, ratio_name], outputs=[output_name], name=f"dropout_{nid}"))
    ctx.tensor_shapes[output_name] = incoming_shape
    ctx.tensor_routing.setdefault(nid, {})["layer_out"] = output_name


@handles("SoftmaxNode", "softmax")
def compile_softmax(ctx, nid: str, ntype: str, props: Dict[str, Any], config: Dict[str, Any], emit: Dict[str, Any]) -> None:
    incoming_tensor = ctx.first_input(nid, "layer_in", "model_in")
    if nid in ctx.disabled_softmax_nodes:
        ctx.tensor_shapes[incoming_tensor] = ctx.tensor_shapes.get(incoming_tensor, ["batch_size", 10])
        ctx.tensor_routing.setdefault(nid, {})["soft_out"] = incoming_tensor
        ctx.tensor_routing.setdefault(nid, {})["layer_out"] = incoming_tensor
        return
    output_name = f"tensor_{nid}_soft_out"
    ctx.onnx_nodes.append(helper.make_node("Softmax", inputs=[incoming_tensor], outputs=[output_name], axis=1, name=f"softmax_{nid}"))
    ctx.tensor_shapes[output_name] = ctx.tensor_shapes.get(incoming_tensor, ["batch_size", 10])
    ctx.tensor_routing.setdefault(nid, {})["soft_out"] = output_name
    ctx.tensor_routing.setdefault(nid, {})["layer_out"] = output_name


@handles("Flatten", "flatten")
def compile_flatten(ctx, nid: str, ntype: str, props: Dict[str, Any], config: Dict[str, Any], emit: Dict[str, Any]) -> None:
    incoming_tensor = ctx.first_input(nid, "layer_in", "model_in")
    incoming_shape = ctx.tensor_shapes.get(incoming_tensor, ["batch_size", 1, 28, 28])
    output_name = f"tensor_{nid}_layer_out"
    ctx.onnx_nodes.append(helper.make_node("Flatten", inputs=[incoming_tensor], outputs=[output_name], axis=1, name=f"flatten_{nid}"))
    ctx.tensor_shapes[output_name] = [incoming_shape[0], int(np.prod(incoming_shape[1:]))]
    ctx.tensor_routing.setdefault(nid, {})["layer_out"] = output_name


@handles("Reshape2D", "reshape2d")
def compile_reshape2d(ctx, nid: str, ntype: str, props: Dict[str, Any], config: Dict[str, Any], emit: Dict[str, Any]) -> None:
    incoming_tensor = ctx.first_input(nid, "layer_in", "model_in")
    incoming_shape = ctx.tensor_shapes.get(incoming_tensor, ["batch_size", 784])
    rows = _as_int(config.get("rows", -1), -1)
    cols = _as_int(config.get("columns", -1), -1)
    features = _as_int(incoming_shape[1] if len(incoming_shape) == 2 else int(np.prod(incoming_shape[1:])), 784)
    if rows <= 0 and cols <= 0:
        rows = int(features ** 0.5)
        cols = features // max(1, rows)
    elif rows <= 0:
        rows = features // max(1, cols)
    elif cols <= 0:
        cols = features // max(1, rows)
    elif rows * cols != features:
        raise ValueError(f"Reshape2D node {nid} cannot reshape {features} features to {rows}x{cols}")
    output_name = f"tensor_{nid}_layer_out"
    shape_name = f"shape_tensor_{nid}"
    ctx.initializers.append(helper.make_tensor(shape_name, TensorProto.INT64, [4], [0, 1, rows, cols]))
    ctx.onnx_nodes.append(helper.make_node("Reshape", inputs=[incoming_tensor, shape_name], outputs=[output_name], name=f"reshape_{nid}"))
    ctx.tensor_shapes[output_name] = ["batch_size", 1, rows, cols]
    ctx.tensor_routing.setdefault(nid, {})["layer_out"] = output_name


@handles("Concat", "concat")
def compile_concat(ctx, nid: str, ntype: str, props: Dict[str, Any], config: Dict[str, Any], emit: Dict[str, Any]) -> None:
    ordered_tensors: List[str] = []
    concat_order = config.get("concat_order", [])
    if concat_order:
        for port_name in concat_order:
            ordered_tensors.extend(ctx.inputs_for(nid, str(port_name)))
    else:
        for port_name in sorted(ctx.input_deliveries.get(nid, {}).keys()):
            ordered_tensors.extend(ctx.inputs_for(nid, port_name))
    if not ordered_tensors:
        raise ValueError(f"Concat node {nid} has no inputs")
    output_name = f"tensor_{nid}_layer_out"
    ctx.onnx_nodes.append(helper.make_node("Concat", inputs=ordered_tensors, outputs=[output_name], axis=1, name=f"concat_{nid}"))
    base_shape = ctx.tensor_shapes.get(ordered_tensors[0], ["batch_size", 0])
    channels = sum(_as_int(ctx.tensor_shapes.get(t, ["batch_size", 0])[1], 0) for t in ordered_tensors)
    ctx.tensor_shapes[output_name] = [base_shape[0], channels, *base_shape[2:]] if len(base_shape) == 4 else [base_shape[0], channels]
    ctx.tensor_routing.setdefault(nid, {})["layer_out"] = output_name


@handles("Add", "add", "AddNode", "add_node")
def compile_add(ctx, nid: str, ntype: str, props: Dict[str, Any], config: Dict[str, Any], emit: Dict[str, Any]) -> None:
    incoming_tensors: List[str] = []
    for port_name in sorted(ctx.input_deliveries.get(nid, {}).keys()):
        incoming_tensors.extend(ctx.inputs_for(nid, port_name))
    if not incoming_tensors:
        raise ValueError(f"Add node {nid} has no inputs")
    if len(incoming_tensors) == 1:
        ctx.tensor_routing.setdefault(nid, {})["layer_out"] = incoming_tensors[0]
        return
    output_name = f"tensor_{nid}_layer_out"
    current_tensor = incoming_tensors[0]
    for idx, next_tensor in enumerate(incoming_tensors[1:]):
        step_output = output_name if idx == len(incoming_tensors) - 2 else f"tensor_{nid}_add_step_{idx}"
        ctx.onnx_nodes.append(helper.make_node("Add", inputs=[current_tensor, next_tensor], outputs=[step_output], name=f"add_{nid}_{idx}"))
        current_tensor = step_output
    ctx.tensor_shapes[output_name] = ctx.tensor_shapes.get(incoming_tensors[0], ["batch_size", 64])
    ctx.tensor_routing.setdefault(nid, {})["layer_out"] = output_name


@handles("OutputMap", "output_map", "ClassifierNode", "RunModel", "train_run_model")
def compile_passthrough(ctx, nid: str, ntype: str, props: Dict[str, Any], config: Dict[str, Any], emit: Dict[str, Any]) -> None:
    incoming_tensor = ctx.first_input(nid, "model_in", "layer_in", "pred_in")
    ctx.tensor_routing.setdefault(nid, {})["model_out"] = incoming_tensor
    ctx.tensor_routing.setdefault(nid, {})["layer_out"] = incoming_tensor


@handles("TrainInput", "TrainBegin", "DatasetName", "ModelName")
def compile_ignored_training_node(ctx, nid: str, ntype: str, props: Dict[str, Any], config: Dict[str, Any], emit: Dict[str, Any]) -> None:
    return
