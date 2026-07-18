extends Node2D

func _enter_tree() -> void:
	glob.base_node = self

#var graph_types = {
	#"io": preload("res://scenes/io_graph.tscn"),
	#"neuron": preload("res://scenes/neuron.tscn"),
	#"loop": preload("res://scenes/loop.tscn"),
	#"base": preload("res://scenes/base_graph.tscn"),
	#"input": preload("res://scenes/input_graph.tscn"),
	#"layer": preload("res://scenes/layer.tscn"),
	#"train_input": preload("res://scenes/train_input.tscn"),
	#"softmax": preload("res://scenes/softmax.tscn"),
	#"reshape2d": preload("res://scenes/reshape.tscn"),
	#"flatten": preload("res://scenes/flatten.tscn"),
	#"conv2d": preload("res://scenes/conv2d.tscn"),
	#"maxpool": preload("res://scenes/maxpool.tscn"),
	#"classifier": preload("res://scenes/classifier_graph.tscn"),
	#"train_begin": preload("res://scenes/train_begin.tscn"),
	#"model_name": preload("res://scenes/netname.tscn"),
	#"dataset": preload("res://scenes/dataset.tscn"),
	#"run_model": preload("res://scenes/run_model.tscn")
#}

@export var importance_chain: Array[StringName] = []

func _ready() -> void:
	var c = glob.to_set(importance_chain)
	for i in graphs.graph_types:
		if not i in c:
			importance_chain.append(i)



func _process(delta: float) -> void:
	pass
	#if Input.is_action_just_pressed("ui_accept"):
		#var compressed = glob.compress_dict_gzip({"train": 1, 
		#"session": "neriqward", 
		#"graph": graphs.get_syntax_tree(graphs._input_origin_graph)})
		##("fjfjf")
		#var a = sockets.connect_to("ws/train", train_state_received)
			#
		#a.connected.connect(func():
			#a.send(compressed))
		#a.closed.connect(print)
		
