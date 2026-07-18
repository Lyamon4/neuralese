extends Graph

@export var fade_speed: float = 10.0
@export var size_lerp_speed: float = 12.0

func _useful_properties() -> Dictionary:
	return {
		"config":{
			"optimizer":"adam", "lr": 1e-3
		}
	}

func _exit_tree() -> void:
	super()

func _after_ready():
	super()
	graphs._training_head = self
	for k in optimizers:
		var n: CanvasItem = optimizers[k]
		_set_alpha(n, 0.0)
		n.hide()
		_fade_targets[n] = 0.0
	select_optimizer(current_optimizer)
	is_training = true
	_target_size_y = base_size + tab_size_adds.get(current_optimizer, 0.0)

func _after_process(delta: float):
	for n in _fade_targets.keys():
		var target_a: float = _fade_targets[n]
		var curr_a: float = n.modulate.a
		if target_a > curr_a and not n.visible:
			n.show()
		var next_a: float = lerp(curr_a, target_a, delta * fade_speed)
		_set_alpha(n, next_a)
		hold_for_frame()
		if target_a < 0.5 and next_a < 0.02 and n.visible:
			n.hide()

	var sz = $ColorRect.size
	sz.y = lerp(sz.y, _target_size_y, delta * size_lerp_speed)
	$ColorRect.size = sz
	
	if $ColorRect2.alive:
		$ColorRect2/time_passed.text = str(glob.cap($ColorRect2.get_time() + timing_offset, 1)) + "s"
		if abs($ColorRect2.get_last_value()*100) > 1000:
			$ColorRect2/acc.text = str(glob.compact($ColorRect2.get_last_value()*100)) + "%"
		else:
			$ColorRect2/acc.text = str(glob.cap($ColorRect2.get_last_value()*100, 1)) + "%"

var learning_rates = {"adam": ["1e-2", "1e-3", "1e-4"], "sgd": ["1e-1","1e-2","1e-3"]}

@onready var base_size: float = $ColorRect.size.y
@export var tab_size_adds: Dictionary[StringName, float] = {"adam": 0.0, "sgd": 10.0}

var is_training: bool = false
func _proceed_hold() -> bool:
	return training

func _can_drag() -> bool:
	return not ui.is_focus($sgd_tab/Label4/HSlider) and not ui.is_focus($YY)

@onready var optimizer = $optimizer
func _opt_selected(opt: StringName):
	_target_size_y = base_size + tab_size_adds.get(opt, 0.0)

	current_optimizer = opt
	optimizer.text = optimizer.button_by_hint[opt].text

	for o in optimizers:
		_set_fade_target(optimizers[o], 0.0)
	_set_fade_target(optimizers[opt], 1.0)

	if opt == "sgd" or opt == "adam":
		var idx: int = -1
		for i in lr._contained:
			idx += 1
			i.text = learning_rates[opt][idx]
		#lr.text = lr.button_by_hint["1"].text
		update_config({"lr": 1})

@onready var lr = $lr
func select_lr(index: int):
	lr.text = learning_rates[current_optimizer][index]

@onready var optimizers = {"sgd": $sgd_tab, "adam": $adam_tab}
var current_optimizer: StringName = "adam"
func select_optimizer(name: StringName):
	_opt_selected(name)

func _on_optimizer_child_button_release(button: BlockComponent) -> void:
	open_undo_redo()
	update_config({"optimizer": button.hint})
	close_undo_redo()
	button.is_contained.menu_hide()

func _on_loss_child_button_release(button: BlockComponent) -> void:
	pass

func push_acceptance(acc: float, time: float):
	$ColorRect2.push_input(time, acc, $ColorRect2._window_end)

func _on_lr_child_button_release(button: BlockComponent) -> void:
	open_undo_redo()
	update_config({"lr": int(button.hint)})
	close_undo_redo()
	button.is_contained.menu_hide()




func _map_properties(pack: Dictionary):
	update_config({"lr": cfg["lr"]})

func _config_field(field: StringName, value: Variant):
	match field:
		"momentum":
			#(value)
			$sgd_tab/Label4/HSlider.value = float(value) * (100.0 / 0.9)
			$sgd_tab/n.text = str(glob.cap(value, 1))
			#if $sgd_tab/n.text != "0.0":
			#$sgd_tab/n.text = $sgd_tab/n.text.trim_prefix('0')
		"lr":
			select_lr(int(value))
		"optimizer":
			select_optimizer(value)

func train_stop():
	if 1:#training:
		training = false
		$ColorRect2.alive = false
		hold_for_frame()
	#train.text = "Train!"
	#nn.stop_train(self)
var training: bool = false
func train_start():
	if 1:#not training:
		training = true
		timing_offset = -$ColorRect2.get_time()
		$ColorRect2.alive = true
		hold_for_frame()
		$ColorRect2/time_passed.text = "0.0s"
	#train.text = "Stop"
	#nn.start_train(self, {"additional_call": additional_call})

var timing_offset: float = 0.0

	#graphs.train()

var _fade_targets: Dictionary = {}
var _target_size_y: float = 0.0

func _set_fade_target(n: CanvasItem, a: float) -> void:
	_fade_targets[n] = clamp(a, 0.0, 1.0)
	if a > 0.0 and not n.visible and n.modulate.a <= 0.02:
		n.show()

func _set_alpha(n: CanvasItem, a: float) -> void:
	var c: Color = n.modulate
	c.a = clamp(a, 0.0, 1.0)
	n.modulate = c


func _on_h_slider_value_changed(value: float) -> void:
	open_undo_redo()
	
	update_config({"momentum": value / (100.0 / 0.9)})
	close_undo_redo()
