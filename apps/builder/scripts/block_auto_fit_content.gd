@tool
extends Node
class_name BlockAutoFitContent

@export var content_path: NodePath
@export var minimum_height: float = 0.0
@export var maximum_height: float = 0.0
@export var extra_height: float = 0.0
@export var update_containing_menu: bool = true
@export var live_update: bool = true

var _block: BlockComponent
var _content: Control
var _last_width: float = -1.0
var _last_height: float = -1.0
var _last_text: String = ""
var _rearrange_scheduled: bool = false

func _ready() -> void:
	_bind.call_deferred()

func _process(_delta: float) -> void:
	if live_update:
		_fit_if_needed()

func _bind() -> void:
	_block = _find_block()
	if not _block:
		push_warning("BlockAutoFitContent must be placed under a BlockComponent.")
		return
	_content = _resolve_content()
	if not _content:
		push_warning("BlockAutoFitContent could not find a Control to measure.")
		return
	_content.resized.connect(_fit_if_needed)
	_fit_if_needed()
	await get_tree().process_frame
	_fit_if_needed()

func _find_block() -> BlockComponent:
	var node := get_parent()
	while node:
		if node is BlockComponent:
			return node
		node = node.get_parent()
	return null

func _resolve_content() -> Control:
	if content_path != NodePath():
		var explicit := _block.get_node_or_null(content_path)
		if explicit is Control:
			return explicit
	var found := _find_content(_block, true)
	if found:
		return found
	return _find_content(_block, false)

func _find_content(root: Node, rich_only: bool) -> Control:
	for child in root.get_children():
		if child == self:
			continue
		if child is RichTextLabel:
			return child
		if not rich_only and child is Label and child.name != "Label":
			return child
	for child in root.get_children():
		if child == self:
			continue
		var found := _find_content(child, rich_only)
		if found:
			return found
	return null

func _fit_if_needed() -> void:
	if not is_instance_valid(_block) or not is_instance_valid(_content):
		return
	var width := _content.size.x
	var text := _get_content_text()
	if is_equal_approx(width, _last_width) and text == _last_text:
		return
	var required := _required_block_height()
	if is_equal_approx(required, _last_height):
		_last_width = width
		_last_text = text
		return
	_last_width = width
	_last_text = text
	_last_height = required
	_apply_height(required)

func _get_content_text() -> String:
	if _content is RichTextLabel:
		return (_content as RichTextLabel).text
	if _content is Label:
		return (_content as Label).text
	return ""

func _required_block_height() -> float:
	var content_height := _measure_content_height()
	var top := _content.position.y
	var bottom := _infer_bottom_padding()
	var required = ceil(top + content_height + bottom + extra_height)
	if minimum_height > 0.0:
		required = max(required, minimum_height)
	if maximum_height > 0.0:
		required = min(required, maximum_height)
	return required

func _measure_content_height() -> float:
	if _content is RichTextLabel:
		return float((_content as RichTextLabel).get_content_height())
	return _content.get_combined_minimum_size().y

func _infer_bottom_padding() -> float:
	if is_equal_approx(_content.anchor_bottom, 1.0) and _content.offset_bottom < 0.0:
		return -_content.offset_bottom
	if _content.get_parent() is Control:
		var parent_control := _content.get_parent() as Control
		var bottom := parent_control.size.y - (_content.position.y + _content.size.y)
		return max(bottom, 0.0)
	return 0.0

func _apply_height(height: float) -> void:
	var new_size := Vector2(_block.base_size.x, height)
	_block.custom_minimum_size.y = height
	_block.resize(new_size)
	if Engine.is_editor_hint():
		_block.custom_minimum_size = new_size
	if update_containing_menu and _block.is_contained:
		_schedule_containing_menu_rearrange(_block.is_contained)

func _schedule_containing_menu_rearrange(menu: BlockComponent) -> void:
	if _rearrange_scheduled:
		return
	_rearrange_scheduled = true
	_rearrange_containing_menu.call_deferred(menu)

func _rearrange_containing_menu(menu: BlockComponent) -> void:
	_rearrange_scheduled = false
	if not is_instance_valid(menu):
		return
	_reset_menu_scroll_height(menu)
	menu.arrange()
	menu.update_children_reveal.call_deferred()

func _reset_menu_scroll_height(menu: BlockComponent) -> void:
	if not menu.scroll:
		return
	var viewport_height: float = menu.expanded_size
	if menu.max_size:
		viewport_height = float(menu.max_size) - menu.base_size.y - 10.0
	menu.scroll.size.y = max(viewport_height, 0.0)
