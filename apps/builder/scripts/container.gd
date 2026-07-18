# BubbleUnit.gd
extends Control
class_name BubbleUnit

enum UnitType {Radio, Text, Checkbox, Next}

@export var static_size: bool = false
@export var unit_type = UnitType.Text
@export var abstract: bool = false
@export var root: Control = null

var passed_data = {}

signal toggled(a: bool)

var text_dtypes = glob.to_set([UnitType.Text, UnitType.Checkbox, UnitType.Radio])
var check_dtypes = glob.to_set([UnitType.Checkbox, UnitType.Radio])
var press_dtypes = glob.to_set([UnitType.Checkbox, UnitType.Radio, UnitType.Next])

@onready var next = $next

var indexed: Array = []
var persistent: bool = false
var _last_size_x: float = -1.0

func _enter_tree() -> void:
	if unit_type == UnitType.Next:
		if not abstract:
			$next.placeholder = false

func _ready() -> void:
	if not passed_data:
		return

	match unit_type:
		UnitType.Text:
			$text.text = passed_data.text

		UnitType.Next:
			next._create_scaler_wrapper.call_deferred()
			next.released.connect(func(): toggled.emit(true))

		UnitType.Checkbox, UnitType.Radio:
			
			$CheckBox.modulate = Color.WHITE * 0.6
			$text.text = passed_data.text
			$CheckBox.toggled.connect(func(a): 
				if a:
					$ColorRect.modulate = Color.WHITE * 1.18
					$CheckBox.modulate = Color.WHITE * 1
				else:
					$ColorRect.modulate = Color.WHITE * 1
					$CheckBox.modulate = Color.WHITE * 0.6
				toggled.emit(a))

	item_rect_changed.connect(rect_change)

	for child in get_children():
		indexed.append(child)
		if child is ColorRect and not child is BlockComponent: continue
		if not child is BlockComponent:
			child.material = get_parent().material
		else:
			indexed.append(child.label)
			child.label.material = get_parent().material

	reinit()


func rect_change():
	_last_size_x = size.x

	if unit_type in check_dtypes:
		$CheckBox.position.y = size.y / 2 - $CheckBox.size.y * $CheckBox.scale.y / 2
		$text.size.x = (size.x) / $text.scale.x - 70
	elif unit_type == UnitType.Next:
		next._wrapped_in.position.x = lerp(0.0, size.x, 0.83)
	else:
		$text.size.x = (size.x) / $text.scale.x



func set_persistent(val: bool):
	# keep API for caller, but no expansion behavior
	persistent = val

enum AnsType {RightSelection, WrongSelection, WasCorrect, Default}

var corr = preload("res://game_assets/icons/check_on.png")
var inc = preload("res://game_assets/icons/check_wrong.png")
var corr_radio = preload("res://game_assets/icons/radio_on.png")
func set_valid(valid: int):
	$CheckBox.remove_theme_icon_override("unchecked")
	$CheckBox.remove_theme_icon_override("checked")
	$CheckBox.remove_theme_icon_override("radio_unchecked")
	await get_tree().process_frame
	match valid:
		AnsType.RightSelection:
			$CheckBox.modulate = Color.GREEN
		AnsType.WrongSelection:
			$CheckBox.modulate = Color.RED
			if unit_type == UnitType.Radio:
				$CheckBox.add_theme_icon_override("checked", corr_radio)
			else:
				$CheckBox.add_theme_icon_override("checked", inc)
		AnsType.WasCorrect:
			if unit_type == UnitType.Radio:
				$CheckBox.add_theme_icon_override("radio_unchecked", corr_radio)
			else:
				$CheckBox.add_theme_icon_override("unchecked", corr)
			$CheckBox.modulate = Color.WHITE * 0.8
		AnsType.Default:
			$CheckBox.modulate = Color.WHITE * 0.6

func block_input():
	if unit_type == UnitType.Next:
		next.freeze_input()
func unblock_input():
	if unit_type == UnitType.Next:
		next.unfreeze_input()


func reinit():
	if not passed_data:
		return

	# force refresh
	size.y += 1
	size.y -= 1

	if unit_type in text_dtypes:
		# content height works reliably once width is set by parent/layout()
		$text.size.y = $text.get_content_height()

	count_size()
	rect_change()
	if unit_type in check_dtypes:
		if $text.get_line_count() == 1:
			$text.position.y = 11
		else:
			$text.position.y = 7


func count_size() -> float:
	if static_size:
		return size.y

	var max_y = size.y
	for c in get_children():
		if not c is Control or not c.visible:
			continue
		var bottom = c.position.y + c.size.y
		max_y = max(max_y, bottom)

	size.y = max_y
	return max_y
