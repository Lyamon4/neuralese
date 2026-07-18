# BubbleUnit.gd
extends Control

enum UnitType {Radio, Text, Checkbox, Next}

@export var static_size: bool = false
@export var unit_type = UnitType.Text
@export var abstract: bool = false
@export var root: Control = null

@export var height_lerp_speed: float = 22.0
@export var snap_eps: float = 0.35

var passed_data = {}

signal toggled(a: bool)

var text_dtypes = glob.to_set([UnitType.Text, UnitType.Checkbox, UnitType.Radio])
var check_dtypes = glob.to_set([UnitType.Checkbox, UnitType.Radio])
var press_dtypes = glob.to_set([UnitType.Checkbox, UnitType.Radio, UnitType.Next])

@onready var next = $next

var indexed = []

var init_size: float = 0.0
var expand_mode: bool = false
var persistent: bool = false
var mouse_is_in: bool = false

var _collapsed_h: float = 0.0
var _expanded_h: float = 0.0
var _last_size_x: float = -1.0

# hover-only overlay state (NO layout impact)
var _hover_expanded: bool = false

# alpha targets (preview_a, text_a)
var tg_mods: Vector2 = Vector2(0, 1)


func _ready() -> void:
	if not passed_data:
		return

	match unit_type:
		UnitType.Text:
			$text.text = passed_data.text

		UnitType.Next:
			next.released.connect(func(): toggled.emit(true))

		UnitType.Checkbox, UnitType.Radio:
			$text.text = passed_data.text
			$text.size.y = $text.get_content_height()

			# Decide whether we need "preview" mode
			if $text.get_line_count() > 1:
				expand_mode = true

				$preview.text = passed_data.text
				$preview.size.y = $preview.get_line_height(0)

				# keep both visible; we fade via modulate (overlay needs this)
				$preview.visible = true
				$text.visible = true

				# initial = collapsed preview
				$preview.modulate.a = 1.0
				$text.modulate.a = 0.0
				tg_mods = Vector2(1, 0)
			else:
				expand_mode = false
				$preview.visible = false
				$text.visible = true
				$text.modulate.a = 1.0

			$CheckBox.toggled.connect(func(a): toggled.emit(a))

	item_rect_changed.connect(rect_change)

	for child in get_children():
		indexed.append(child)
		if not child is BlockComponent:
			child.material = get_parent().material
		else:
			indexed.append(child.label)
			child.label.material = get_parent().material

	reinit()

	init_size = size.y
	_recalc_heights()
	size.y = _collapsed_h


func _process(delta: float) -> void:
	if static_size:
		return

	# Layout expansion is ONLY for persistent (click), never for hover.
	var target_h = _expanded_h if (persistent and expand_mode and unit_type in check_dtypes) else _collapsed_h
	var t = clamp(height_lerp_speed * delta, 0.0, 1.0)

	size.y = lerp(size.y, target_h, t)
	if abs(size.y - target_h) <= snap_eps:
		size.y = target_h

	# Overlay alpha (hover) + persistent full-text
	if unit_type in check_dtypes and expand_mode:
		var want_full = persistent or (_hover_expanded and mouse_is_in)
		tg_mods = Vector2(0, 1) if want_full else Vector2(1, 0)

		$text.modulate.a = lerpf($text.modulate.a, tg_mods.y, delta * height_lerp_speed)
		$preview.modulate.a = 1.0 - $text.modulate.a

		# Keep hovered (overlay) above the list; collapse back when not needed.
		if want_full:
			z_as_relative = false
			z_index = 100
		elif not persistent:
			z_index = 0


func rect_change():
	# Only respond to width changes.
	if is_equal_approx(_last_size_x, size.x):
		return
	_last_size_x = size.x

	if unit_type in check_dtypes:
		$text.size.x = (size.x) / $text.scale.x - 40
		$preview.size.x = (size.x) / $preview.scale.x - 40
	elif unit_type == UnitType.Next:
		next._wrapped_in.position.x = lerp(0.0, size.x, 0.76)
	else:
		$text.size.x = (size.x) / $text.scale.x

	_recalc_heights()


func set_persistent(val: bool):
	persistent = val

	# click -> persistent expansion (layout), unclick -> collapse (layout)
	# hover overlay should not "stick" after unselect unless mouse is still in
	if persistent:
		_hover_expanded = true
	else:
		if not mouse_is_in:
			_hover_expanded = false
		mouse_out()


func mouse_in():
	mouse_is_in = true
	if unit_type in check_dtypes and expand_mode:
		root.expand_target(self)


func expand():
	# hover-triggered overlay (NO layout)
	if unit_type in check_dtypes and expand_mode:
		_hover_expanded = true


func mouse_out():
	mouse_is_in = false
	if unit_type in check_dtypes and expand_mode and not persistent:
		_hover_expanded = false


func reinit():
	if not passed_data:
		return

	# force refresh
	size.y += 1
	size.y -= 1

	if unit_type in text_dtypes:
		$text.size.y = $text.get_content_height()

	init_size = size.y
	_recalc_heights()


func _recalc_heights() -> void:
	if static_size:
		_collapsed_h = size.y
		_expanded_h = size.y
		return

	if not (unit_type in check_dtypes) or not expand_mode:
		_collapsed_h = count_size_for_current_visibility()
		_expanded_h = _collapsed_h
		return

	# Measure collapsed (preview-only)
	var prev_text_vis = $text.visible
	var prev_prev_vis = $preview.visible

	$text.hide()
	$preview.show()
	_collapsed_h = count_size_for_current_visibility()

	# Measure expanded (full text)
	$preview.hide()
	$text.show()
	_expanded_h = count_size_for_current_visibility()

	# Restore visibility for overlay mode (both visible; we use alpha)
	$text.visible = true
	$preview.visible = true

	# Preserve whatever visibility existed for non-expand items (defensive)
	if not expand_mode:
		$text.visible = prev_text_vis
		$preview.visible = prev_prev_vis


func count_size_for_current_visibility() -> float:
	var max_y = size.y
	for c in get_children():
		if not c is Control or not c.visible:
			continue
		var bottom = c.position.y + c.size.y
		max_y = max(max_y, bottom)
	return max_y


# Used by QuestBubble to mask underlying items via shader extents.
func overlay_start_y() -> float:
	return get_global_rect().end.y


func overlay_cut_y() -> float:
	# Only meaningful when we're showing full text as an overlay (hover), not when persistent expanded.
	if not (unit_type in check_dtypes and expand_mode):
		return 0.0
	if persistent:
		return 0.0
	if not (_hover_expanded and mouse_is_in):
		return 0.0
	if $text.modulate.a <= 0.02:
		return 0.0

	# Full text can extend past our collapsed row; cut until its end.
	return max(get_global_rect().end.y, $text.get_global_rect().end.y)
