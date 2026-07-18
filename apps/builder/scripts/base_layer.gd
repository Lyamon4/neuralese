extends DynamicGraph
class_name BaseNeuronLayer

@export var layer_name: String = ""


var neurons_fixed: bool = false:
	set(v):
		neurons_fixed = v
		_neurons_fix_set(v)

func _neurons_fix_set(v: bool):
	pass
