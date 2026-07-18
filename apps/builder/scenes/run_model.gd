extends DynamicGraph

func _ready() -> void:
	super()
	for i in 5:
		add_unit({"text": "true"}, true)
