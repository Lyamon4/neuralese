extends Graph

func _useful_properties() -> Dictionary:
	var is_output: bool = false
	var desc = get_first_descendants()
	is_output = desc.size() == 0
	for i in desc:
		if i.is_head:
			is_output = true
	return {"config":{
		"role": "output" if is_output else "none"}}

func _get_x() -> Variant:
	return holding

var holding: int = 0

func _just_attached(other_conn: Connection, my_conn: Connection):
	pass
	#upd(holding)

func upd(count: int):
	holding = count
	graphs.push_1d(count, self)
