extends ColorRect

# Color(0.49, 0.627, 0.831)
# Color(0.49, 0.83, 0.614)

func appear():
	target_lerps = null
	show()
	get_parent().workslist_but.color = Color(0.49, 0.83, 0.614)
	glob.space_begin.y = get_parent().size.y + get_parent().position.y + size.y - 1

func dissapear():
	target_lerps = null
	get_parent().workslist_but.color = Color(0.49, 0.627, 0.831)
	glob.space_begin.y = get_parent().size.y + get_parent().position.y
	hide()

func _ready():
	glob.language_changed.connect(re_data)

func _enter_tree():
	ui.lesson_bar = self

func _process(delta: float) -> void:
	if not visible: return
	sizing_tick()
	#update_data({classroom_name = "Math 10A", step_index = (glob.ticks / 100) % 10 + 1, step_shorthand = "Create LoadDataset node",
	#lesson_index = 1, lesson_name = "Your First ML Model: MNIST digit classifier", total_steps = 10})
	re_data()
	if first_point and !is_equal_approx($actual.points[-1].x, target_lerps.x):
		var last_point = lerp($actual.points[-1], target_lerps, delta * 10.0)
		$actual.points = PackedVector2Array([Vector2(first_point, 0), last_point])

func sizing_tick():
	$Label2.size.x = glob.get_label_text_size($Label2).x
	$Label2.position.x = size.x - $Label2.size.x * $Label2.scale.x - 10

func re_data():
	if last_data:
		update_data(last_data)

var last_data = {}
func update_data(packet: Dictionary, force: bool = false, lerper: bool = false):
	last_data = packet
	$Label.text = str(packet["lesson_index"]) + ". " + packet["lesson_name"]
	var max_size: int = clamp(size.x / 30, 13, 99)
	#(size.x)
	if max_size < 40 and len($Label.text) > max_size:
		$Label.text = $Label.text.substr(0,max_size) + ".."
	
	var step_text = " - Step "
	if glob.curr_lang == "kz":
		step_text = " - Кезең "
	elif glob.curr_lang == "ru":
		step_text = " - Шаг "
	$Label2.text = packet["step_shorthand"] + step_text + str(packet["step_index"]) + " / " + str(int(packet["total_steps"]))

	first_point = $Label.size.x * $Label.scale.x + 50
	var last_point = $Label2.position.x - 40
	if lerper and target_lerps != null:
		print("call once")
		sizing_tick()
		var temp_target_lerps = Vector2(lerpf(first_point, last_point, (float(packet["step_index"])-1) / packet["total_steps"]), 0)
		$actual.points = PackedVector2Array([Vector2(first_point, 0), temp_target_lerps])
	$backline.points = PackedVector2Array([Vector2(first_point, 0), Vector2(last_point, 0)])
	target_lerps = Vector2(lerpf(first_point, last_point, float(packet["step_index"]) / packet["total_steps"]), 0)
	if force:
		await get_tree().process_frame
		$actual.points = PackedVector2Array([Vector2(first_point, 0), target_lerps])

var first_point = null
var target_lerps = null
