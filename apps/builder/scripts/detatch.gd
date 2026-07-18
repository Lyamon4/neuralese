extends ProceduralNodes

func _ready():
	initialize()
	if not easy:
		glob.ref(self, "detatch_unroll")

func _get_nodes(args, kwargs = {}) -> Array[Node]:
	if easy:
		return parent_easy.call(parent_call, frozen_duplicate, args, kwargs)
	
	var output: Array[Node] = []
	var lines = []
	var i: int = 0
	var pref = "Spline"
	match glob.get_lang():
		"kz":
			pref = "Сызық"
		"ru":
			pref = "Связь"
	for _i in args:
		i += 1
		var new: BlockComponent = frozen_duplicate.duplicate()
		new.placeholder = false
		new.text = pref + " %s"%i
		var line = _i if _i is Spline else args[_i]
		new.metadata["inst"] = line
		new.metadata["all"] = false
		lines.append(line)
		output.append(new)
	if len(args) >= 3:
		var new: BlockComponent = frozen_duplicate.duplicate()
		new.placeholder = false
		new.text = "All"
		new.metadata["all"] = true
		new.metadata["inst"] = lines
		output.insert(0, new)
	
	return output
