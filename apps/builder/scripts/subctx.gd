extends ProceduralNodes

func _ready():
	initialize()
	if not easy:
		glob.ref(self, "subctx")

func _get_nodes(args, kwargs = {}) -> Array[Node]:
	if easy:
		return parent_easy.call(parent_call, frozen_duplicate, args, kwargs)
	
	var output: Array[Node] = []
	var i: int = 0
	for _i in args:
		i += 1
		var new: BlockComponent = frozen_duplicate.duplicate()
		new.placeholder = false
		new.text = _i
		output.append(new)
	
	return output
