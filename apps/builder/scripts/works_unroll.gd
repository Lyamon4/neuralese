extends ProceduralNodes

func _ready():
	initialize()
	if not easy:
		glob.ref(self, "works_unroll")

func re():
	unroll()

func _get_nodes(args, kwargs = {}) -> Array[Node]:
	if easy:
		return parent_easy.call(parent_call, frozen_duplicate, args, kwargs)
	var output: Array[Node] = []
	var i: int = 0
	#var untitled_text = "Untitled"
	for _i in args:
		i += 1
		var new: BlockComponent = frozen_duplicate.duplicate()
		new.placeholder = false
		new.text = args[_i]["name"]
		var text_name = "Untitled"
		if glob.get_lang() == "ru":
			text_name = "Безымянный"
		elif glob.get_lang() == "kz":
			text_name = "Атаусыз"
		if not new.text: 
			(func():
				new.text = text_name; new.label.self_modulate = Color(0.6,0.6,0.6,1)).call_deferred()
		#("a")
		new.hint = str(_i)
		new.metadata["project_id"] = int(_i)
		output.append(new)
	
	return output
