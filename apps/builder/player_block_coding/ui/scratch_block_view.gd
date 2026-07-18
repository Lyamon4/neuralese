extends Control
class_name ScratchBlockView

signal palette_block_pressed(block_id: StringName)
signal edit_requested(block: BlockInstance)
signal delete_requested(block: BlockInstance)
signal moved(block: BlockInstance, new_position: Vector2)
signal drag_ended(block: BlockInstance, new_position: Vector2)
signal selected(block: BlockInstance)

const BlockDefinitionClass = preload("res://player_block_coding/core/block_definition.gd")
const BlockInstanceClass = preload("res://player_block_coding/core/block_instance.gd")

const HEADER_HEIGHT: float = 38.0
const STATEMENT_HEIGHT: float = 38.0
const VALUE_HEIGHT: float = 32.0
const ENTRY_HAT_RISE: float = 10.0
const FOOTER_HEIGHT: float = 17.0
const ELSE_HEADER_HEIGHT: float = 28.0
const EMPTY_MOUTH_HEIGHT: float = 34.0
const CHILD_GAP: float = 3.0
const INNER_X: float = 34.0
const INNER_RIGHT: float = 14.0
const CONNECTOR_X: float = 24.0
const CONNECTOR_WIDTH: float = 42.0
const CONNECTOR_HEIGHT: float = 11.0

@export var palette_mode: bool = false
@export var draggable: bool = true
@export var show_delete_button: bool = true
@export var background_color: Color = Color(0.11, 0.11, 0.11, 1.0)

var definition: BlockDefinition = null
var block: BlockInstance = null
var is_selected: bool = false

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _delete_rect: Rect2 = Rect2()
var _tokens_cache: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_size()

func set_definition(p_definition: BlockDefinition, p_palette_mode: bool = false) -> void:
	definition = p_definition
	block = null
	palette_mode = p_palette_mode
	show_delete_button = not palette_mode
	_tokens_cache = _build_tokens()
	_update_size()
	queue_redraw()

func set_block(p_block: BlockInstance, p_palette_mode: bool = false) -> void:
	block = p_block
	definition = p_block.definition if p_block != null else null
	palette_mode = p_palette_mode
	show_delete_button = not palette_mode
	_tokens_cache = _build_tokens()
	_update_size()
	queue_redraw()

func refresh_from_block() -> void:
	_tokens_cache = _build_tokens()
	_update_size()
	queue_redraw()

func set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()

func is_container_block() -> bool:
	if definition == null:
		return false
	if definition.kind == BlockDefinition.BlockKind.CONTROL:
		return true
	if definition.kind == BlockDefinition.BlockKind.ENTRY:
		return true
	return false

func has_else_mouth() -> bool:
	if definition == null:
		return false
	var id_text: String = String(definition.id)
	return id_text == "if_else" or id_text == "if_elseif_else"

func get_top_snap_local() -> Vector2:
	return Vector2(CONNECTOR_X + CONNECTOR_WIDTH * 0.5, _body_start_y())

func get_bottom_snap_local() -> Vector2:
	return Vector2(CONNECTOR_X + CONNECTOR_WIDTH * 0.5, max(size.y - CONNECTOR_HEIGHT * 0.5, 0.0))

func get_main_mouth_rect() -> Rect2:
	if not is_container_block():
		return Rect2()
	var y: float = _header_bottom_y()
	var h: float = _main_body_height()
	return Rect2(INNER_X, y, max(size.x - INNER_X - INNER_RIGHT, 80.0), h)

func get_else_mouth_rect() -> Rect2:
	if not has_else_mouth():
		return Rect2()
	var y: float = _header_bottom_y() + _main_body_height() + FOOTER_HEIGHT + ELSE_HEADER_HEIGHT
	var h: float = _else_body_height()
	return Rect2(INNER_X, y, max(size.x - INNER_X - INNER_RIGHT, 80.0), h)

func get_visual_height_for_block(p_block: BlockInstance) -> float:
	return _calculate_block_height_for_instance(p_block)

func _gui_input(event: InputEvent) -> void:
	if definition == null:
		return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				if palette_mode:
					palette_block_pressed.emit(definition.id)
					accept_event()
					return

				if show_delete_button and _delete_rect.has_point(mouse_event.position):
					delete_requested.emit(block)
					accept_event()
					return

				if mouse_event.double_click:
					edit_requested.emit(block)
					accept_event()
					return

				selected.emit(block)
				if draggable:
					_dragging = true
					_drag_offset = mouse_event.position
					move_to_front()
					accept_event()
			else:
				if _dragging:
					_dragging = false
					drag_ended.emit(block, position)
					accept_event()

		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed and not palette_mode:
			edit_requested.emit(block)
			accept_event()

	elif event is InputEventMouseMotion:
		if _dragging and draggable and not palette_mode:
			var motion_event: InputEventMouseMotion = event
			position += motion_event.relative
			moved.emit(block, position)
			accept_event()

func _draw() -> void:
	if definition == null:
		return

	var body_color: Color = definition.color
	if body_color.a <= 0.01:
		body_color = _fallback_color_for_kind(definition.kind)

	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	_draw_shadow(rect)
	_draw_block_body(rect, body_color)
	_draw_tokens(body_color)
	_draw_selection(rect)
	_draw_delete_button()

func _draw_shadow(rect: Rect2) -> void:
	var shadow: StyleBoxFlat = StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.30)
	shadow.set_corner_radius_all(12)
	shadow.draw(get_canvas_item(), Rect2(rect.position + Vector2(2, 3), rect.size))

func _draw_block_body(rect: Rect2, body_color: Color) -> void:
	if definition.kind == BlockDefinition.BlockKind.VALUE:
		_draw_value_body(rect, body_color)
		return

	var body_y: float = _body_start_y()
	var body: StyleBoxFlat = StyleBoxFlat.new()
	body.bg_color = body_color
	body.set_corner_radius_all(10)
	body.draw(get_canvas_item(), Rect2(0, body_y, rect.size.x, max(rect.size.y - body_y - 4.0, 1.0)))

	if definition.kind == BlockDefinition.BlockKind.ENTRY:
		_draw_hat(rect, body_color)

	if definition.kind != BlockDefinition.BlockKind.ENTRY:
		var cut: StyleBoxFlat = StyleBoxFlat.new()
		cut.bg_color = background_color
		cut.set_corner_radius_all(5)
		cut.draw(get_canvas_item(), Rect2(CONNECTOR_X, body_y - 1.0, CONNECTOR_WIDTH, 10.0))

	var bump: StyleBoxFlat = StyleBoxFlat.new()
	bump.bg_color = body_color
	bump.set_corner_radius_all(5)
	bump.draw(get_canvas_item(), Rect2(CONNECTOR_X, rect.size.y - CONNECTOR_HEIGHT, CONNECTOR_WIDTH, CONNECTOR_HEIGHT))

	if is_container_block():
		_draw_mouths(body_color)

func _draw_hat(rect: Rect2, body_color: Color) -> void:
	var hat: PackedVector2Array = PackedVector2Array([
		Vector2(9, ENTRY_HAT_RISE),
		Vector2(31, 0),
		Vector2(rect.size.x - 15, 0),
		Vector2(rect.size.x, ENTRY_HAT_RISE + 4),
		Vector2(rect.size.x, ENTRY_HAT_RISE + 21),
		Vector2(0, ENTRY_HAT_RISE + 21),
		Vector2(0, ENTRY_HAT_RISE + 8),
	])
	draw_colored_polygon(hat, body_color)

func _draw_value_body(rect: Rect2, body_color: Color) -> void:
	var body: StyleBoxFlat = StyleBoxFlat.new()
	body.bg_color = body_color
	body.set_corner_radius_all(int(rect.size.y * 0.5))
	body.draw(get_canvas_item(), rect)

func _draw_mouths(body_color: Color) -> void:
	var main_rect: Rect2 = get_main_mouth_rect()
	_draw_single_mouth(main_rect, body_color, "drop statements here", block == null or block.children.is_empty())

	if has_else_mouth():
		var font: Font = get_theme_font("font", "Label")
		var font_size: int = max(get_theme_font_size("font_size", "Label"), 14)
		var else_y: float = _header_bottom_y() + _main_body_height() + FOOTER_HEIGHT + 19.0
		draw_string(font, Vector2(16, else_y), "else", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.96))
		var else_rect: Rect2 = get_else_mouth_rect()
		_draw_single_mouth(else_rect, body_color, "drop else statements here", block == null or block.else_children.is_empty())

func _draw_single_mouth(mouth_rect: Rect2, body_color: Color, placeholder: String, is_empty: bool) -> void:
	var mouth: StyleBoxFlat = StyleBoxFlat.new()
	mouth.bg_color = background_color
	mouth.set_corner_radius_all(8)
	mouth.draw(get_canvas_item(), mouth_rect)

	var lip: StyleBoxFlat = StyleBoxFlat.new()
	lip.bg_color = body_color
	lip.set_corner_radius_all(6)
	lip.draw(get_canvas_item(), Rect2(CONNECTOR_X, mouth_rect.position.y + mouth_rect.size.y - 4.0, CONNECTOR_WIDTH, 10.0))

	if is_empty:
		var font: Font = get_theme_font("font", "Label")
		draw_string(font, mouth_rect.position + Vector2(13, 22), placeholder, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.38))

func _draw_tokens(body_color: Color) -> void:
	var font: Font = get_theme_font("font", "Label")
	var font_size: int = max(get_theme_font_size("font_size", "Label"), 15)
	var x: float = 15.0
	var baseline: float = _label_baseline_y()

	for token in _tokens_cache:
		var token_type: String = str(token.get("type", "text"))
		var text: String = str(token.get("text", ""))
		if text == "":
			continue

		if token_type == "input":
			var input_width: float = max(_text_size(font, text, font_size).x + 18.0, 34.0)
			var input_rect: Rect2 = Rect2(Vector2(x, baseline - 18.0), Vector2(input_width, 24.0))
			var input_style: StyleBoxFlat = StyleBoxFlat.new()
			input_style.bg_color = body_color.lightened(0.23)
			input_style.border_color = Color(1, 1, 1, 0.26)
			input_style.set_border_width_all(1)
			input_style.set_corner_radius_all(10)
			input_style.draw(get_canvas_item(), input_rect)
			draw_string(font, Vector2(x + 9.0, baseline - 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.98))
			x += input_rect.size.x + 6.0
		else:
			draw_string(font, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.96))
			x += _text_size(font, text, font_size).x + 2.0

func _draw_selection(rect: Rect2) -> void:
	if not is_selected:
		return
	var selection: StyleBoxFlat = StyleBoxFlat.new()
	selection.bg_color = Color(0, 0, 0, 0)
	selection.border_color = Color(1.0, 1.0, 1.0, 0.78)
	selection.set_border_width_all(2)
	selection.set_corner_radius_all(12)
	selection.draw(get_canvas_item(), rect.grow(2))

func _draw_delete_button() -> void:
	_delete_rect = Rect2()
	if not show_delete_button or palette_mode:
		return
	_delete_rect = Rect2(size.x - 27.0, _body_start_y() + 7.0, 19.0, 19.0)
	var close_style: StyleBoxFlat = StyleBoxFlat.new()
	close_style.bg_color = Color(0, 0, 0, 0.25)
	close_style.set_corner_radius_all(9)
	close_style.draw(get_canvas_item(), _delete_rect)
	var font: Font = get_theme_font("font", "Label")
	draw_string(font, _delete_rect.position + Vector2(5, 14), "×", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.82))

func _build_tokens() -> Array[Dictionary]:
	var tokens: Array[Dictionary] = []
	if definition == null:
		return tokens

	var label: String = definition.label
	var cursor: int = 0
	while cursor < label.length():
		var open_index: int = label.find("{", cursor)
		if open_index == -1:
			var remaining: String = label.substr(cursor)
			if remaining != "":
				tokens.append({"type": "text", "text": remaining})
			break

		if open_index > cursor:
			var prefix: String = label.substr(cursor, open_index - cursor)
			tokens.append({"type": "text", "text": prefix})

		var close_index: int = label.find("}", open_index + 1)
		if close_index == -1:
			tokens.append({"type": "text", "text": label.substr(open_index)})
			break

		var key_text: String = label.substr(open_index + 1, close_index - open_index - 1)
		var value_text: String = _argument_display_text(StringName(key_text))
		tokens.append({"type": "input", "name": key_text, "text": value_text})
		cursor = close_index + 1

	return tokens

func _argument_display_text(name: StringName) -> String:
	var value: Variant = null
	if block != null:
		value = block.get_argument(name, null)
	if value == null and definition != null:
		value = definition.defaults.get(name, String(name))
	if value is BlockInstance:
		return _short_text(value.definition.label if value.definition != null else "value", 18)
	return _short_text(str(value), 24)

func _short_text(text: String, max_len: int) -> String:
	if text.length() <= max_len:
		return text
	return text.substr(0, max_len - 1) + "…"

func _update_size() -> void:
	var wanted: Vector2 = _calculate_size()
	custom_minimum_size = wanted
	size = wanted
	update_minimum_size()

func _calculate_size() -> Vector2:
	if definition == null:
		return Vector2(120, STATEMENT_HEIGHT)

	var width: float = _calculate_label_width()
	if not palette_mode:
		width += 28.0

	if is_container_block():
		width = max(width, 230.0)
		if block != null:
			width = max(width, INNER_X + _calculate_chain_width(block.children) + INNER_RIGHT)
			if has_else_mouth():
				width = max(width, INNER_X + _calculate_chain_width(block.else_children) + INNER_RIGHT)

	var height: float = STATEMENT_HEIGHT
	if definition.kind == BlockDefinition.BlockKind.VALUE:
		height = VALUE_HEIGHT
	elif is_container_block():
		height = _body_start_y() + HEADER_HEIGHT + _main_body_height() + FOOTER_HEIGHT
		if has_else_mouth():
			height += ELSE_HEADER_HEIGHT + _else_body_height() + FOOTER_HEIGHT

	return Vector2(clamp(width, 110.0, 760.0), height)

func _calculate_label_width() -> float:
	var font: Font = get_theme_font("font", "Label")
	var font_size: int = max(get_theme_font_size("font_size", "Label"), 15)
	var width: float = 30.0
	for token in _tokens_cache:
		var text: String = str(token.get("text", ""))
		if str(token.get("type", "text")) == "input":
			width += max(_text_size(font, text, font_size).x + 18.0, 34.0) + 6.0
		else:
			width += _text_size(font, text, font_size).x + 2.0
	return width

func _calculate_chain_width(children: Array) -> float:
	var max_width: float = 150.0
	for child in children:
		if child is BlockInstance:
			max_width = max(max_width, _calculate_block_width_for_instance(child))
	return max_width

func _calculate_block_width_for_instance(p_block: BlockInstance) -> float:
	if p_block == null or p_block.definition == null:
		return 150.0
	var old_definition: BlockDefinition = definition
	var old_block: BlockInstance = block
	var old_tokens: Array[Dictionary] = _tokens_cache
	definition = p_block.definition
	block = p_block
	_tokens_cache = _build_tokens()
	var result: float = _calculate_label_width()
	if is_container_block():
		result = max(result, 230.0)
		result = max(result, INNER_X + _calculate_chain_width(p_block.children) + INNER_RIGHT)
		if has_else_mouth():
			result = max(result, INNER_X + _calculate_chain_width(p_block.else_children) + INNER_RIGHT)
	definition = old_definition
	block = old_block
	_tokens_cache = old_tokens
	return clamp(result, 110.0, 760.0)

func _calculate_block_height_for_instance(p_block: BlockInstance) -> float:
	if p_block == null or p_block.definition == null:
		return STATEMENT_HEIGHT
	if p_block.definition.kind == BlockDefinition.BlockKind.VALUE:
		return VALUE_HEIGHT
	var container: bool = p_block.definition.kind == BlockDefinition.BlockKind.CONTROL or p_block.definition.kind == BlockDefinition.BlockKind.ENTRY
	if not container:
		return STATEMENT_HEIGHT
	var height: float = 0.0
	if p_block.definition.kind == BlockDefinition.BlockKind.ENTRY:
		height += ENTRY_HAT_RISE
	height += HEADER_HEIGHT
	height += max(EMPTY_MOUTH_HEIGHT, _calculate_chain_height(p_block.children))
	height += FOOTER_HEIGHT
	var id_text: String = String(p_block.definition.id)
	if id_text == "if_else" or id_text == "if_elseif_else":
		height += ELSE_HEADER_HEIGHT
		height += max(EMPTY_MOUTH_HEIGHT, _calculate_chain_height(p_block.else_children))
		height += FOOTER_HEIGHT
	return height

func _calculate_chain_height(children: Array) -> float:
	if children.is_empty():
		return EMPTY_MOUTH_HEIGHT
	var total: float = 0.0
	for child in children:
		if child is BlockInstance:
			if total > 0.0:
				total += CHILD_GAP
			total += _calculate_block_height_for_instance(child)
	return max(total, EMPTY_MOUTH_HEIGHT)

func _main_body_height() -> float:
	if block == null:
		return EMPTY_MOUTH_HEIGHT
	return max(EMPTY_MOUTH_HEIGHT, _calculate_chain_height(block.children))

func _else_body_height() -> float:
	if block == null:
		return EMPTY_MOUTH_HEIGHT
	return max(EMPTY_MOUTH_HEIGHT, _calculate_chain_height(block.else_children))

func _body_start_y() -> float:
	if definition != null and definition.kind == BlockDefinition.BlockKind.ENTRY:
		return ENTRY_HAT_RISE
	return 0.0

func _header_bottom_y() -> float:
	return _body_start_y() + HEADER_HEIGHT

func _label_baseline_y() -> float:
	if definition == null:
		return 25.0
	if definition.kind == BlockDefinition.BlockKind.VALUE:
		return 21.0
	if definition.kind == BlockDefinition.BlockKind.ENTRY:
		return _body_start_y() + 25.0
	return 25.0

func _text_size(font: Font, text: String, font_size: int) -> Vector2:
	if font == null:
		return Vector2(float(text.length() * font_size) * 0.55, float(font_size))
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

func _fallback_color_for_kind(kind: int) -> Color:
	match kind:
		BlockDefinition.BlockKind.ENTRY:
			return Color(0.95, 0.68, 0.16)
		BlockDefinition.BlockKind.CONTROL:
			return Color(0.93, 0.52, 0.15)
		BlockDefinition.BlockKind.VALUE:
			return Color(0.42, 0.42, 0.88)
		_:
			return Color(0.18, 0.55, 0.95)
