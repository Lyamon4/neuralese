class_name DSLRegistry
extends Node

#Event types (events.is_event):
# train
# ui_mouse_middle


var compile: DSLCompile
var runtime: DSLRuntime
var graph: DSLGraphUtils

var require: Dictionary
var step_directives: Dictionary
var action: Dictionary


func _ready() -> void:
	graph = DSLGraphUtils.new()
	compile = DSLCompile.new()
	runtime = DSLRuntime.new()

	compile.reg = self
	compile.graph = graph

	runtime.reg = self
	runtime.graph = graph

	# ============================================================
	# REQUIRE TYPES
	# ============================================================
	require = {
		"node": {
			"type": "node",
			"compile": compile.compile_req_node,
			"runtime": runtime.check_node,
		},
		"connection": {
			"type": "connection",
			"compile": compile.compile_req_connection,
			"runtime": runtime.check_connection,
		},
		"config": {
			"type": "config",
			"compile": compile.compile_req_config,
			"runtime": runtime.check_config,
		},
		"topology": {
			"type": "topology_graph",
			"compile": compile.compile_req_topology,
			"runtime": runtime.check_topology_graph,
		},
		"wait": {
			"type": "wait",
			"compile": compile.compile_req_wait,
			"runtime": runtime.check_wait,
		},
		"event": {
			"type": "event",
			"compile": compile.compile_req_event,
			"runtime": runtime.check_event,
		},
		"teacher_lock": {
			"type": "teacher_lock",
			"compile": compile.compile_req_lock,
			"runtime": runtime.check_lock,
		},
	}

	# ============================================================
	# STEP DIRECTIVES
	# ============================================================
	step_directives = {
		"create":  { "compile": compile.step_apply_create },
		"require": { "compile": compile.step_apply_require },
		"actions": { "compile": compile.step_apply_actions },
	}

	# ============================================================
	# ACTION TYPES
	# ============================================================
	action = {
		"explain": {
			"compile": compile.compile_action_explain,
			"runtime": runtime.run_action_explain,
		},
		"hide_arrows": {
			"compile": compile.compile_action_hide_arrows,
			"runtime": runtime.run_action_hide_arrows,
		},
		"arrow": {
			"compile": compile.compile_action_arrow,
			"runtime": runtime.run_action_arrow,
		},

		"require": {
			"compile": compile.compile_action_require,
			"runtime": runtime.run_action_require,
		},
		"create": {
			"compile": compile.compile_action_create,
			"runtime": runtime.run_action_create,
		},
		"explain_button": {
			"compile": compile.compile_action_explain_button,
			"runtime": runtime.run_action_explain_button,
		},
		"explain_next": {
			"compile": compile.compile_action_explain_next,
			"runtime": runtime.run_action_explain_next,
		},
		"confetti": {
			"compile": compile.compile_action_confetti,
			"runtime": runtime.run_action_confetti,
		},
		"select": {
			"compile": compile.compile_action_select,
			"runtime": runtime.run_action_select,
		},
		"highlight": {
			"compile": compile.compile_action_highlight,
			"runtime": runtime.run_action_highlight,
		},
		"ask": {
			"compile": compile.compile_action_ask,
			"runtime": runtime.run_action_ask,
		},
		"multi_input": {
			"compile": compile.compile_action_multi_input,
			"runtime": runtime.run_action_multi_input,
		},
		"prohibit_deletion": {
			"compile": compile.compile_action_prohibit_deletion,
			"runtime": runtime.run_action_prohibit_deletion,
		},
		"allow_deletion": {
			"compile": compile.compile_action_allow_deletion,
			"runtime": runtime.run_action_allow_deletion,
		},
	}


func build_runtime_map_by_type() -> Dictionary:
	var out: Dictionary = {}
	for yaml_key in require.keys():
		var spec: Dictionary = require[yaml_key]
		out[str(spec["type"])] = spec["runtime"]
	return out
