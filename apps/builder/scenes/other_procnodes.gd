extends ProceduralNodes

@export var naming = "list_unroll"
@export var one_d: bool = false
@export var two_d: bool = false

func _ready():
	initialize()
	glob.ref(self, naming)

func _get_nodes(args, kwargs = {}) -> Array[Node]:
	var output: Array[Node] = []
	var i: int = 0
	for _i in args:
		i += 1
		var new: BlockComponent = frozen_duplicate.duplicate()
		new.placeholder = false
		new.text = _i
		new.hint = _i
		if not one_d:
			new.metadata["content"] = args[_i]
		if two_d:
			new.hint = args[_i]
		
		output.append(new)
	
	return output
