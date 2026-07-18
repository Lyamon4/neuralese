extends Control
class_name ScratchWorkspace

signal block_edit_requested(block: BlockInstance)
signal block_delete_requested(block: BlockInstance)
signal workspace_changed
signal order_changed

const BlockProgramClass = preload("res://player_block_coding/core/block_program.gd")
const BlockInstanceClass = preload("res://player_block_coding/core/block_instance.gd")
const ScratchBlockViewClass = preload("res://player_block_coding/ui/scratch_block_view.gd")

@export var canvas_min_size: Vector2 = Vector2(1800, 1200)
@export var background_color: Color = Color(0.105, 0.105, 0.105, 1.0)
@export var grid_color: Color = Color(1, 1, 1, 0.035)
@export var snap_x: float = 32.0
@export var snap_gap: float = 0.0
@export var connector_snap_distance: float = 34.0
@export var mouth_snap_inset: float = 14.0

var program: BlockProgram = null
var selected_view: ScratchBlockView = null
var _empty_label: Label = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = canvas_min_size
	size = canvas_min_size
	_create_empty_label()

func set_program(p_program: BlockProgram) -> void:
	program = p_program
	_render_program()

func add_visual_for_block(block: BlockInstance, position_hint: Vector2 = Vector2.INF) -> void:
	if program == null or block == null:
		return
	if position_hint == Vector2.INF:
		position_hint = _next_block_position()
	_set_block_position(block, position_hint)
	if not program.roots.has(block):
		program.roots.append(block)
	_render_program()
	_update_empty_state()
	_sort_all_sequences_by_visual_y()
	workspace_changed.emit()

func remove_visual_for_block(block: BlockInstance) -> void:
	remove_block_from_program(block)

func remove_block_from_program(block: BlockInstance) -> bool:
	if program == null or block == null:
		return false
	var info: Dictionary = _find_parent_info(block)
	if info.is_empty():
		return false
	var sequence: Array = _sequence_from_info(info)
	var index: int = int(info.get("index", -1))
	if index >= 0 and index < sequence.size():
		sequence.remove_at(index)
	_forget_subtree_positions(block)
	_render_program()
	_update_empty_state()
	order_changed.emit()
	workspace_changed.emit()
	return true

func refresh_visual_text() -> void:
	for child in get_children():
		if child is ScratchBlockView:
			child.refresh_from_block()
	_layout_program_from_tree(false)
	queue_redraw()

func sort_program_by_layout() -> void:
	_sort_all_sequences_by_visual_y()

func _render_program() -> void:
	for child in get_children():
		if child != _empty_label:
			remove_child(child)
			child.queue_free()
	if program == null:
		_update_empty_state()
		return

	var index: int = 0
	for block in program.roots:
		var pos: Vector2 = _get_block_position(block, Vector2(snap_x, 32.0 + index * 58.0))
		_set_block_position(block, pos)
		_create_block_tree_views(block, pos)
		index += 1

	_layout_program_from_tree(false)
	_update_empty_state()
	queue_redraw()

func _create_block_tree_views(block: BlockInstance, at_position: Vector2) -> ScratchBlockView:
	var view: ScratchBlockView = _create_block_view(block, at_position)
	for child in block.children:
		if child is BlockInstance:
			_create_block_tree_views(child, _get_block_position(child, at_position + Vector2(34, 44)))
	for child in block.else_children:
		if child is BlockInstance:
			_create_block_tree_views(child, _get_block_position(child, at_position + Vector2(34, 88)))
	return view

func _create_block_view(block: BlockInstance, at_position: Vector2) -> ScratchBlockView:
	var view: ScratchBlockView = ScratchBlockViewClass.new()
	view.background_color = background_color
	view.palette_mode = false
	view.draggable = true
	view.set_block(block, false)
	view.position = at_position
	view.moved.connect(_on_block_view_moved)
	view.drag_ended.connect(_on_block_view_drag_ended)
	view.edit_requested.connect(_on_block_edit_requested)
	view.delete_requested.connect(_on_block_delete_requested)
	view.selected.connect(_on_block_selected)
	add_child(view)
	return view

func _on_block_view_moved(block: BlockInstance, new_position: Vector2) -> void:
	if block == null:
		return
	var old_position: Vector2 = _get_block_position(block, new_position)
	var clamped_position: Vector2 = Vector2(max(new_position.x, 4.0), max(new_position.y, 4.0))
	var delta: Vector2 = clamped_position - old_position
	_set_block_position(block, clamped_position)
	if delta.length_squared() > 0.0:
		_move_descendant_views(block, delta)
	_expand_canvas_to_fit(clamped_position)
	workspace_changed.emit()

func _on_block_view_drag_ended(block: BlockInstance, new_position: Vector2) -> void:
	if program == null or block == null:
		return

	var view: ScratchBlockView = _view_for_block(block)
	if view == null:
		return

	var clamped_position: Vector2 = Vector2(max(new_position.x, 4.0), max(new_position.y, 4.0))
	_set_block_position(block, clamped_position)
	view.position = clamped_position

	var snap_result: Dictionary = _find_best_snap(block, view)
	if snap_result.is_empty():
		_detach_to_roots(block)
		_set_block_position(block, clamped_position)
	else:
		_apply_snap(block, snap_result)

	_sort_all_sequences_by_visual_y()
	_layout_program_from_tree(true)
	order_changed.emit()
	workspace_changed.emit()

func _find_best_snap(block: BlockInstance, view: ScratchBlockView) -> Dictionary:
	var top_point: Vector2 = view.position + view.get_top_snap_local()
	var center_point: Vector2 = view.position + view.size * 0.5
	var best: Dictionary = {}
	var best_score: float = INF

	for child in get_children():
		if not (child is ScratchBlockView):
			continue
		var candidate: ScratchBlockView = child
		if candidate.block == block:
			continue
		if _is_ancestor(block, candidate.block):
			continue

		if candidate.is_container_block():
			var main_rect: Rect2 = candidate.get_main_mouth_rect().grow(mouth_snap_inset)
			main_rect.position += candidate.position
			if main_rect.has_point(top_point) or main_rect.has_point(center_point):
				var score: float = top_point.distance_to(main_rect.get_center())
				if score < best_score:
					best_score = score
					best = {"type": "mouth", "target": candidate.block, "branch": "children"}

			if candidate.has_else_mouth():
				var else_rect: Rect2 = candidate.get_else_mouth_rect().grow(mouth_snap_inset)
				else_rect.position += candidate.position
				if else_rect.has_point(top_point) or else_rect.has_point(center_point):
					var else_score: float = top_point.distance_to(else_rect.get_center())
					if else_score < best_score:
						best_score = else_score
						best = {"type": "mouth", "target": candidate.block, "branch": "else_children"}

		if _can_snap_after(block, candidate.block):
			var target_bottom: Vector2 = candidate.position + candidate.get_bottom_snap_local()
			var dist: float = top_point.distance_to(target_bottom)
			if dist < connector_snap_distance and dist < best_score:
				best_score = dist
				best = {"type": "after", "target": candidate.block}

	return best

func _apply_snap(block: BlockInstance, snap_result: Dictionary) -> void:
	var snap_type: String = str(snap_result.get("type", ""))
	var target: BlockInstance = snap_result.get("target", null)
	if target == null:
		return

	if snap_type == "mouth":
		var branch: String = str(snap_result.get("branch", "children"))
		_append_to_container(block, target, branch)
		return

	if snap_type == "after":
		_insert_after(block, target)

func _append_to_container(block: BlockInstance, target: BlockInstance, branch: String) -> void:
	if block == null or target == null or block == target:
		return
	if _is_ancestor(block, target):
		return
	_remove_from_current_sequence(block)
	if branch == "else_children":
		if not target.else_children.has(block):
			target.else_children.append(block)
	else:
		if not target.children.has(block):
			target.children.append(block)

func _insert_after(block: BlockInstance, target: BlockInstance) -> void:
	if block == null or target == null or block == target:
		return
	if _is_ancestor(block, target):
		return
	var target_info: Dictionary = _find_parent_info(target)
	if target_info.is_empty():
		return
	_remove_from_current_sequence(block)
	target_info = _find_parent_info(target)
	if target_info.is_empty():
		return
	var sequence: Array = _sequence_from_info(target_info)
	var target_index: int = int(target_info.get("index", -1))
	sequence.insert(target_index + 1, block)
	var target_view: ScratchBlockView = _view_for_block(target)
	if target_view != null:
		_set_block_position(block, target_view.position + Vector2(0.0, max(target_view.size.y - 5.0, 0.0)))

func _detach_to_roots(block: BlockInstance) -> void:
	if program == null or block == null:
		return
	var info: Dictionary = _find_parent_info(block)
	if info.is_empty():
		program.roots.append(block)
		return
	if info.get("owner", null) == null and str(info.get("branch", "")) == "roots":
		return
	_remove_from_current_sequence(block)
	program.roots.append(block)

func _can_snap_after(block: BlockInstance, target: BlockInstance) -> bool:
	if block == null or block.definition == null:
		return false
	if target == null or target.definition == null:
		return false
	if block.definition.kind == BlockDefinition.BlockKind.VALUE:
		return false
	if block.definition.kind == BlockDefinition.BlockKind.ENTRY:
		return false
	if target.definition.kind == BlockDefinition.BlockKind.VALUE:
		return false
	return true

func _layout_program_from_tree(animate: bool) -> void:
	if program == null:
		return
	var max_extent: Vector2 = canvas_min_size
	for root in program.roots:
		var root_pos: Vector2 = _get_block_position(root, Vector2(snap_x, 32.0))
		var extent: Vector2 = _layout_subtree(root, root_pos, animate)
		max_extent.x = max(max_extent.x, extent.x + 700.0)
		max_extent.y = max(max_extent.y, extent.y + 300.0)
	custom_minimum_size = max_extent
	size = max_extent
	queue_redraw()

func _layout_subtree(block: BlockInstance, desired_pos: Vector2, animate: bool) -> Vector2:
	var view: ScratchBlockView = _view_for_block(block)
	if view == null:
		return desired_pos

	view.refresh_from_block()
	_place_view(view, desired_pos, animate)
	_set_block_position(block, desired_pos)

	var extent: Vector2 = desired_pos + view.size
	if view.is_container_block():
		var main_rect: Rect2 = view.get_main_mouth_rect()
		var child_pos: Vector2 = desired_pos + main_rect.position + Vector2(0.0, 3.0)
		extent = _layout_sequence(block.children, child_pos, animate, extent)
		if view.has_else_mouth():
			var else_rect: Rect2 = view.get_else_mouth_rect()
			var else_pos: Vector2 = desired_pos + else_rect.position + Vector2(0.0, 3.0)
			extent = _layout_sequence(block.else_children, else_pos, animate, extent)
	return extent

func _layout_sequence(sequence: Array, start_pos: Vector2, animate: bool, current_extent: Vector2) -> Vector2:
	var cursor_y: float = start_pos.y
	var extent: Vector2 = current_extent
	for item in sequence:
		if not (item is BlockInstance):
			continue
		var child_block: BlockInstance = item
		var child_pos: Vector2 = Vector2(start_pos.x, cursor_y)
		var child_extent: Vector2 = _layout_subtree(child_block, child_pos, animate)
		extent.x = max(extent.x, child_extent.x)
		extent.y = max(extent.y, child_extent.y)
		var child_view: ScratchBlockView = _view_for_block(child_block)
		if child_view != null:
			cursor_y += child_view.size.y + ScratchBlockView.CHILD_GAP
		else:
			cursor_y += 40.0
	return extent

func _place_view(view: ScratchBlockView, pos: Vector2, animate: bool) -> void:
	if animate:
		var tween: Tween = create_tween()
		tween.tween_property(view, "position", pos, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		view.position = pos

func _move_descendant_views(block: BlockInstance, delta: Vector2) -> void:
	for child in block.children:
		if child is BlockInstance:
			_move_subtree_by_delta(child, delta)
	for child in block.else_children:
		if child is BlockInstance:
			_move_subtree_by_delta(child, delta)

func _move_subtree_by_delta(block: BlockInstance, delta: Vector2) -> void:
	var view: ScratchBlockView = _view_for_block(block)
	if view != null:
		view.position += delta
		_set_block_position(block, _get_block_position(block, view.position) + delta)
	for child in block.children:
		if child is BlockInstance:
			_move_subtree_by_delta(child, delta)
	for child in block.else_children:
		if child is BlockInstance:
			_move_subtree_by_delta(child, delta)

func _on_block_edit_requested(block: BlockInstance) -> void:
	block_edit_requested.emit(block)

func _on_block_delete_requested(block: BlockInstance) -> void:
	block_delete_requested.emit(block)

func _on_block_selected(block: BlockInstance) -> void:
	for child in get_children():
		if child is ScratchBlockView:
			child.set_selected(child.block == block)
			if child.block == block:
				selected_view = child

func _sort_all_sequences_by_visual_y() -> void:
	if program == null:
		return
	_sort_sequence_by_visual_y(program.roots)
	for root in program.roots:
		_sort_descendant_sequences(root)

func _sort_descendant_sequences(block: BlockInstance) -> void:
	_sort_sequence_by_visual_y(block.children)
	_sort_sequence_by_visual_y(block.else_children)
	for child in block.children:
		if child is BlockInstance:
			_sort_descendant_sequences(child)
	for child in block.else_children:
		if child is BlockInstance:
			_sort_descendant_sequences(child)

func _sort_sequence_by_visual_y(sequence: Array) -> void:
	sequence.sort_custom(func(a: BlockInstance, b: BlockInstance) -> bool:
		var pos_a: Vector2 = _get_block_position(a, Vector2.ZERO)
		var pos_b: Vector2 = _get_block_position(b, Vector2.ZERO)
		if abs(pos_a.y - pos_b.y) < 8.0:
			return pos_a.x < pos_b.x
		return pos_a.y < pos_b.y
	)

func _view_for_block(block: BlockInstance) -> ScratchBlockView:
	for child in get_children():
		if child is ScratchBlockView and child.block == block:
			return child
	return null

func _find_parent_info(block: BlockInstance) -> Dictionary:
	if program == null or block == null:
		return {}
	for i in range(program.roots.size()):
		var root: BlockInstance = program.roots[i]
		if root == block:
			return {"owner": null, "branch": "roots", "index": i}
		var found: Dictionary = _find_parent_info_recursive(root, block)
		if not found.is_empty():
			return found
	return {}

func _find_parent_info_recursive(owner: BlockInstance, needle: BlockInstance) -> Dictionary:
	for i in range(owner.children.size()):
		var main_child: BlockInstance = owner.children[i]
		if main_child == needle:
			return {"owner": owner, "branch": "children", "index": i}
		var found_in_children: Dictionary = _find_parent_info_recursive(main_child, needle)
		if not found_in_children.is_empty():
			return found_in_children

	for i in range(owner.else_children.size()):
		var else_child: BlockInstance = owner.else_children[i]
		if else_child == needle:
			return {"owner": owner, "branch": "else_children", "index": i}
		var found_in_else: Dictionary = _find_parent_info_recursive(else_child, needle)
		if not found_in_else.is_empty():
			return found_in_else

	return {}

func _sequence_from_info(info: Dictionary) -> Array:
	var owner_variant: Variant = info.get("owner", null)
	var branch: String = str(info.get("branch", "roots"))
	if owner_variant == null:
		return program.roots
	var owner: BlockInstance = owner_variant as BlockInstance
	if owner == null:
		return program.roots
	if branch == "else_children":
		return owner.else_children
	return owner.children

func _remove_from_current_sequence(block: BlockInstance) -> void:
	var info: Dictionary = _find_parent_info(block)
	if info.is_empty():
		return
	var sequence: Array = _sequence_from_info(info)
	var index: int = int(info.get("index", -1))
	if index >= 0 and index < sequence.size():
		sequence.remove_at(index)

func _is_ancestor(possible_parent: BlockInstance, possible_child: BlockInstance) -> bool:
	if possible_parent == null or possible_child == null:
		return false
	for child in possible_parent.children:
		if child == possible_child:
			return true
		if child is BlockInstance and _is_ancestor(child, possible_child):
			return true
	for child in possible_parent.else_children:
		if child == possible_child:
			return true
		if child is BlockInstance and _is_ancestor(child, possible_child):
			return true
	return false

func _get_block_position(block: BlockInstance, fallback: Vector2) -> Vector2:
	if program == null or block == null:
		return fallback
	var positions: Dictionary = program.metadata.get("visual_positions", {})
	var key: String = String(block.uid)
	if positions.has(key):
		var stored: Variant = positions[key]
		if stored is Vector2:
			return stored
		if typeof(stored) == TYPE_DICTIONARY:
			return Vector2(float(stored.get("x", fallback.x)), float(stored.get("y", fallback.y)))
	return fallback

func _set_block_position(block: BlockInstance, pos: Vector2) -> void:
	if program == null or block == null:
		return
	var positions: Dictionary = program.metadata.get("visual_positions", {})
	positions[String(block.uid)] = {"x": pos.x, "y": pos.y}
	program.metadata["visual_positions"] = positions

func _forget_block_position(block: BlockInstance) -> void:
	if program == null or block == null:
		return
	var positions: Dictionary = program.metadata.get("visual_positions", {})
	positions.erase(String(block.uid))
	program.metadata["visual_positions"] = positions

func _forget_subtree_positions(block: BlockInstance) -> void:
	_forget_block_position(block)
	for child in block.children:
		if child is BlockInstance:
			_forget_subtree_positions(child)
	for child in block.else_children:
		if child is BlockInstance:
			_forget_subtree_positions(child)

func _next_block_position() -> Vector2:
	if program == null or program.roots.is_empty():
		return Vector2(snap_x, 32)
	var max_y: float = 20.0
	for block in program.roots:
		var pos: Vector2 = _get_block_position(block, Vector2(snap_x, 32))
		var view_height: float = ScratchBlockView.STATEMENT_HEIGHT
		var view: ScratchBlockView = _view_for_block(block)
		if view != null:
			view_height = view.size.y
		max_y = max(max_y, pos.y + view_height)
	return Vector2(snap_x, max_y + 18.0)

func _expand_canvas_to_fit(pos: Vector2) -> void:
	var new_size: Vector2 = custom_minimum_size
	new_size.x = max(new_size.x, pos.x + 700.0)
	new_size.y = max(new_size.y, pos.y + 300.0)
	if new_size != custom_minimum_size:
		custom_minimum_size = new_size
		size = new_size
		queue_redraw()

func _create_empty_label() -> void:
	_empty_label = Label.new()
	_empty_label.text = "Click blocks from the palette. Drag statement blocks into C-mouths or onto connector notches to build Lua."
	_empty_label.modulate = Color(1, 1, 1, 0.42)
	_empty_label.position = Vector2(32, 28)
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.custom_minimum_size = Vector2(680, 40)
	add_child(_empty_label)

func _update_empty_state() -> void:
	if _empty_label == null:
		return
	var has_blocks: bool = false
	if program != null:
		has_blocks = not program.roots.is_empty()
	_empty_label.visible = not has_blocks

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background_color, true)
	var step: float = 32.0
	var x: float = 0.0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid_color, 1.0)
		x += step
	var y: float = 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), grid_color, 1.0)
		y += step
