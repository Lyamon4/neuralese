extends Graph

func _can_drag() -> bool:
#	print(run)
	return not run.is_mouse_inside()

func _config_field(field: StringName, value: Variant):
	if field == "name":
		if not upd:
			if not value: value = "[none]"
			$LabelAutoResize.text = value
			$LabelAutoResize.resize()
	if field == "meta":
		push_meta(value)

var upd: bool = false


func _on_line_edit_changed() -> void:
	upd = true
	update_config({"name": $LineEdit.text})
	upd = false

func _just_connected(who: Connection, to: Connection):
	push_meta(saved_meta)

var saved_meta: Dictionary = {}

func push_meta(meta: Dictionary):
	saved_meta = meta
	saved_meta.merge({"name": "", "outputs": [], "inputs": {}}, false)
	if get_descendant():
		get_descendant().set_dataset_meta(saved_meta)

func unpush_meta():
	if get_descendant():
		get_descendant().set_dataset_meta({"name": "", "outputs": [], "inputs": {}})

func _just_disconnected(who: Connection, to: Connection):
	to.parent_graph.set_dataset_meta({"name": "", "outputs": []})

@onready var run = $run
func _on_run_released() -> void:
	run.block_input()
	var res = await ui.splash_and_get_result("select_dataset", run, null, false, {"with_who": cfg["name"], "env": true})
	hold_for_frame()
	if res:
		update_config({"name": res["ds"]})
		update_config({"meta": res["meta"]})
	await get_tree().process_frame
	hold_for_frame()
	var m = func(): return glob.mouse_pressed
	while m.call():
		await get_tree().process_frame
	run.unblock_input()
