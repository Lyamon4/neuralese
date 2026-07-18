extends ProceduralNodes

func _ready():
	initialize()
	glob.ref(self, "list_unroll1")

func _get_nodes(args, kwargs = {}) -> Array[Node]:
	var output: Array[Node] = []
	var i: int = 0
	for _i in args:
		i += 1
		var new: BlockComponent = frozen_duplicate.duplicate()
		new.placeholder = false
		new.text = _i
		new.hint = _i
		new.metadata["content"] = args[_i]
		output.append(new)
	
	return output
