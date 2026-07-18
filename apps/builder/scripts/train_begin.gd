extends Graph

func get_training_data():
	#(not dataset_meta["name"] in glob._load)
	if get_ancestor() and get_ancestor().cfg["name"]:
		return {"epochs": epochs if epochs else 1, "dataset": get_ancestor().cfg["name"], "test_dataset": "", 
		"batch_size": 0, "local": not dataset_meta["name"] in glob._load}

@onready var clearbut = $train2

var dataset_meta: Dictionary = {}

func display_ds_meta():
	$ColorRect2/Control.push_cfg(dataset_meta)

func set_dataset_meta(meta: Dictionary):
	#(meta)
	var old_meta = dataset_meta
#	print(meta)
	dataset_meta = meta
	#(meta)
	display_ds_meta()
	var a 
	#(meta)
	#(graphs.simple_reach(self))
	for i in graphs.simple_reach(self):
		if graphs.is_node(i, "OutputMap"):
			i.push_meta(self, dataset_meta)
	#for i in graphs.get_cache("", self):
	#	i.push_meta(self, dataset_meta)
	#(dataset_meta)
	set_meta("input_features", dataset_meta.get("inputs", {}))
	if dataset_meta.get("inputs", {}).has("is_env"):
		dataset_meta = dataset_meta.duplicate()
		dataset_meta["inputs"] = {}
	await get_tree().process_frame
#	print(get_descendant())
#	print(get_descendant().input_keys[0].hint)
	if not graphs.loading and not "env" in old_meta and get_descendant() and not get_descendant()._is_suitable_other_conn(outputs[0], get_descendant().input_keys[0]):
		#(get_descendant()._is_suitable_conn(outputs[0], get_descendant().input_keys[0]))
		#await get_tree().process_frame
		#(dataset_meta["name"])
		#_stack()
		outputs[0].disconnect_all()

#func _just_attached(other_conn: Connection, my_conn: Connection):
		#set_dataset_meta({"name": "mnist", "outputs": [
		#{"label": "bbox", "length": 5, "dtype": "1d"}, {"label": "bbox", "length": 5, "dtype": "1d"}
	#]})

var scrolling = false
@onready var vbar = $ColorRect2/Control/ScrollContainer.get_v_scroll_bar()
func _ready() -> void:
	#vbar.value_changed.connect(func(): scrolling = true)
	super()
	#set_dataset_meta({"name": "mnist", "outputs": [
	#	{"label": "bbox", "length": 5, "dtype": "1d"}, {"label": "bbox", "length": 5, "dtype": "1d"}
	#]})
	graphs.spline_connected.connect(func(from: Connection, to: Connection):
		if to.parent_graph.server_typename == "OutputMap" and not to.virtual:
			var reached = graphs._reach_input(to.parent_graph, "TrainBegin")
			if reached and reached == self:
		#		print(reached)
				to.parent_graph.unpush_meta()
				#graphs.bind_cache(to.parent_graph, "", self)
				to.parent_graph.push_meta(self, dataset_meta, true))
		##else:
			##var reached = graphs._reach_input(to.parent_graph, "TrainBegin")
			##if reached and reached == self:
				##graphs.bind_cache(to.parent_graph, "", self)
			###	to.parent_graph.push_meta(self, dataset_meta)
				##to.parent_graph.set_meta("input_features", dataset_meta.get("inputs", {}))
				##to.parent_graph.set_meta("inputs_owner", self)
			#)
	#graphs.spline_disconnected.connect(func(from: Connection, to: Connection):
		#if to.parent_graph.server_typename == "OutputMap" and not to.virtual:
			#if to.parent_graph.meta_owner == self:
				##graphs.uncache(to.parent_graph, "", self)
				#to.parent_graph.unpush_meta()
		#elif to.parent_graph.get_meta("input_owner") == self:
			#
			#to.parent_graph.set_meta("input_features", {})
			#to.parent_graph.set_meta("inputs_owner", null)
				#
			##var reached = graphs._reach_input(to.parent_graph, "TrainBegin")
			##if reached and reached == self and not to.virtual:
			##	to.parent_graph.push_meta(dataset_meta["outputs"])

	

func get_training_head():
	var r = []
	var def_call = func(from: Connection, to: Connection, branch_cache: Dictionary):
		if graphs.is_node(to.parent_graph, "TrainInput"):
			r.append(to.parent_graph)
	graphs.reach(self, def_call)
	return r[0] if r else null

func _can_train() -> bool:
	var res = true
	return res

func additional_call(dict):
	if training:
		if dict["phase"] == "state":
			#(dict)
			if "epoch" in dict["data"] and $YY.text.is_valid_int():
				var new_text = max(0, int(dict["data"].get("left", 0))-1)
				$YY.set_line(str(new_text) if new_text else "")
		if dict["phase"] == "done":
			train_stop(true)

var epochs: int = 0

var training: bool = false
var delaying: bool = false
func train_stop(force: bool = false, send: bool = true):
	#$ColorRect2.alive = false
	if training and (not delaying or force) and _can_train():
		$YY.editable = true
		var a = func():
			delaying = true
			await glob.wait(2)
			delaying = false
		training = false
		train.text = "Train!"
		if old_head:
			old_head.train_stop()
			if send:
				nn.stop_train(old_head)
		if send:
			a.call()
		if int($YY.text) <= 1:
			$YY.set_line("")

func vbox_focus():
	#($ColorRect2/Control/ScrollContainer.get_v_scroll_bar().get_global_rect().has_point(get_global_mouse_position()))
	#if scrolling:
	#	return true
	return vbox_vis() and glob.mouse_pressed and $ColorRect2/Control/ScrollContainer.get_v_scroll_bar().get_global_rect().has_point(get_global_mouse_position())

func vbox_vis():
	return $ColorRect2/Control/ScrollContainer.get_v_scroll_bar().visible

func _can_drag() -> bool:
	return not train.is_mouse_inside() and not ui.is_focus($YY) and not vbox_focus() and not clearbut.is_mouse_inside()

func _stopped_processing():
	glob.set_scroll_possible(self)

func _process(delta: float) -> void:
	#if glob.space_just_pressed:
	#	print(get_training_data())
	super(delta)
	if $ColorRect2.get_global_rect().has_point(get_global_mouse_position()) and vbox_vis():
		glob.set_scroll_impossible(self)
	else:
		glob.set_scroll_possible(self)
	#(func(): scrolling = false).call_deferred()
		

func _proceed_hold() -> bool:
	#if glob.space_just_pressed:
	#	set_dataset_meta({"outputs": [{"label": "hii"}]})
	return ui.is_focus($YY) or vbox_focus()

var old_head = null
func train_start():
	#timing_offset = -$ColorRect2.get_time()
	if not training and not delaying:
		$YY.editable = false
		training = true
		match glob.get_lang():
			"kz":
				train.text = "Тоқта"
			"ru":
				train.text = "Стоп"
			_:
				train.text = "Stop"
		old_head = get_training_head()
		#(old_head)
		if not $YY.text: $YY.set_line("1"); epochs = 1
		else: epochs = int($YY.text)
		if old_head:
			#("AA")
			old_head.train_start()
			if not await nn.start_train(old_head, additional_call, train):
				hold_for_frame()
				train_stop(false, false)
		#($YY.text)

@onready var train = $train
func _on_train_released() -> void:
	if training:
		train_stop()
	else:
		events.event_ping("train", {"id": graph_id, })
		train_start()


func _on_train_2_released() -> void:
	var anc = null

	for i in graphs.simple_reach(self):
		if graphs.is_node(i, "RunModel"):
			var active_name: String = i.name_graph
			if active_name == "":
				active_name = glob.DEFAULT_MODEL_NAME

			anc = graphs.get_input_graph_by_name(active_name)

		if graphs.is_node(i, "TrainInput"):
			i.clear()

	if is_instance_valid(anc):
		nn.delete_ctx(anc.context_id)
		#await web.POST("delete_ctx", {"user": cookies.user(), "pass": cookies.pwd(), "scene": str(glob.get_project_id()), "contexts": [str(anc.context_id)]})
