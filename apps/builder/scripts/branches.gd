extends DynamicGraph

var name_graph: String = ""

var unit_keys = {}
func _useful_properties() -> Dictionary:
	return {}



func _request_save():
	pass
	#set_name_graph(name_graph)

func dis():
	$Label2.hide()


var manually: bool = false


func _map_properties(pack: Dictionary):
	pass


	#set_loss_type(str(node.graph_id), "mse")
	#("A!")


func get_label(who: Control):
	return unit_labels[who]



func _process(delta: float) -> void:
	super(delta)
	#if glob.space_just_pressed:
		#(_useful_properties())

func _just_attached(other_conn: Connection, my_conn: Connection):
	pass
	if my_conn.virtual:
		var rgb = Color(1,1,1)*1.4
		var who = my_conn.get_parent().get_node("ColorRect")
		rgb.a = who.modulate.a
		who.modulate = rgb


func _just_deattached(other_conn: Connection, my_conn: Connection):
	pass
	if my_conn.virtual:
		def(my_conn.get_parent())
	else:
		unpush_meta()
		#my_conn.get_parent().modulate = Color.WHITE * 1 #.get_node("ColorRect")

func def(who):
	who = who.get_node("ColorRect")
	var rgb = Color(1,1,1)*0.7
	rgb.a = who.modulate.a
	who.modulate = rgb


func set_pellets(pellets):
	hold_for_frame()
	for unit in len(units):
		remove_unit(0)
	for pellet in pellets:
		add_unit(pellet, true)
	hold_for_frame()
	#(prev_branches)
	#(old_units)
	#(prev_branches)
	#(unit_keys)
	#for j in branch_ends:
	#	var title = j.get_title()
	#	var loss = prev_by_title.get(title, "mse")
	#	set_loss_type(str(j.graph_id), loss)



func _get_unit(kw: Dictionary) -> Control: #virtual
	var dup = _unit.duplicate()
	dup.get_node("i").hint = randf_range(0,999999)
	dup.get_node("i").repoll_accepted()
	#(dup.get_node("i")._accepted_datatypes)
	dup.get_node("i").dynamic = false
	dup.get_node("i").set_meta("kw", kw)
	unit_labels[dup] = kw["text"]
	dup.set_meta("label", kw["text"])
	dup.get_node("Control/Label").text = kw["text"].to_pascal_case()
	var vec = str(int(kw["x"])) if kw["datatype"] != "2d" else str(int(kw["x"])) + "," + str(int(kw["y"]))

	dup.get_node("Control/Label2").text = kw["datatype"] + "(" + vec + ")"
	dup.show()
	dup.modulate.a = 0.0
	appear_units[dup] = true
	#update_config_subfield({"branches/%s"%})
	def(dup)
	return dup

var unit_labels = {}
func _unit_removal(id: int):
	units[id].get_node("i").queue_free()
	unit_labels.erase(units[id])

var old_ds = ""
var meta_owner: Graph = null
func aw():
	await get_tree().process_frame
	hold_for_frame()

func get_label_name(who: Control):
	return who.get_parent().get_meta("label")

func push_meta(who: Graph, data: Dictionary, force: bool = false):
	#(data)
	#var f = func()
	#get_tree().process_frame.connect()
	aw()
	if "name" in data and not force:
		if old_ds == data["name"]: return
		old_ds = data["name"]
	meta_owner = who
	#_stack()
	#await get_tree().process_frame
	if not data:
		return
	if not who or data.name == "":
		$ColorRect/root/Label.position.y = 9
		set_pellets([])
		$ColorRect/root/dataset.text = ""
		return
	else:
		$ColorRect/root/Label.position.y = 3
	var gathered = []
	for i in data["outputs"]:
		#(i)
		gathered.append({"text": i.label, "datatype": i.datatype, "x": i.x, "y": i.get("y", 0)})
	set_pellets(gathered)
	$ColorRect/root/dataset.text = data["name"]

func unpush_meta():
	#meta_owner = null
	push_meta(null, {})


func _ready() -> void:
	super()
	unpush_meta()
