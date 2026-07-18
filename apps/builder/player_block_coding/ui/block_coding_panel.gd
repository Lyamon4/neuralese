extends Control
class_name BlockCodingPanel

signal code_exported(language: StringName, code: String)
signal program_changed(program: BlockProgram)

const BlockDefinitionClass = preload("res://player_block_coding/core/block_definition.gd")
const BlockInstanceClass = preload("res://player_block_coding/core/block_instance.gd")
const BlockProgramClass = preload("res://player_block_coding/core/block_program.gd")
const LuaEmitterClass = preload("res://player_block_coding/languages/lua_emitter.gd")
const DefaultBlockLibraryClass = preload("res://player_block_coding/library/default_block_library.gd")
const ScratchBlockViewClass = preload("res://player_block_coding/ui/scratch_block_view.gd")
const ScratchWorkspaceClass = preload("res://player_block_coding/ui/scratch_workspace.gd")

@export var palette_list_path: NodePath
@export var block_list_path: NodePath
@export var block_canvas_path: NodePath
@export var language_option_path: NodePath
@export var export_button_path: NodePath
@export var clear_button_path: NodePath
@export var status_label_path: NodePath
@export var code_preview_path: NodePath
@export var auto_preview: bool = true
@export var auto_build_missing_ui: bool = true

var catalog: Dictionary = {}
var program: BlockProgram = BlockProgramClass.new()
var emitters: Dictionary = {}

var palette_list: VBoxContainer = null
var block_canvas: ScratchWorkspace = null
var language_option: OptionButton = null
var export_button: Button = null
var clear_button: Button = null
var status_label: Label = null
var code_preview: TextEdit = null

func _ready() -> void:
	_make_self_visible_if_collapsed()
	_resolve_nodes()
	if auto_build_missing_ui and _ui_is_missing_core_nodes():
		_build_default_ui()
		_resolve_nodes()
	_upgrade_legacy_block_list_to_canvas()
	_resolve_nodes()

	catalog = DefaultBlockLibrary.build_catalog()
	register_emitter(LuaEmitterClass.new())
	_build_language_options()
	_build_palette()
	_connect_buttons()
	_connect_workspace()
	_render_workspace()
	_set_status("Ready")
	_refresh_preview()

func register_emitter(emitter: BlockLanguageEmitter) -> void:
	if emitter == null:
		return
	emitters[emitter.language_id] = emitter

func add_block_by_id(block_id: StringName) -> BlockInstance:
	var block: BlockInstance = DefaultBlockLibrary.create_instance(block_id, catalog)
	if block == null:
		return null
	program.add_root(block)
	if block_canvas != null:
		block_canvas.add_visual_for_block(block)
	else:
		_render_workspace()
	_emit_changed()
	return block

func clear_program() -> void:
	program.clear()
	_render_workspace()
	_emit_changed()

func export_code(language_id: StringName = &"") -> String:
	var selected_language: StringName = language_id
	if selected_language == &"":
		selected_language = get_selected_language()
	if not emitters.has(selected_language):
		_set_status("Missing emitter: %s" % String(selected_language))
		return ""
	if block_canvas != null:
		block_canvas.sort_program_by_layout()
	var emitter: BlockLanguageEmitter = emitters[selected_language]
	var code: String = emitter.emit_program(program)
	if code_preview != null:
		code_preview.text = code
	code_exported.emit(selected_language, code)
	_set_status("Exported %s" % String(selected_language))
	return code

func get_selected_language() -> StringName:
	if language_option == null or language_option.item_count == 0:
		return &"lua"
	return StringName(language_option.get_item_text(language_option.selected))

func serialize_program() -> Dictionary:
	return program.to_dictionary()

func load_program(data: Dictionary) -> void:
	program = BlockProgram.from_dictionary(data, catalog)
	_render_workspace()
	_emit_changed()

func _resolve_nodes() -> void:
	palette_list = get_node_or_null(palette_list_path) as VBoxContainer
	block_canvas = get_node_or_null(block_canvas_path) as ScratchWorkspace
	language_option = get_node_or_null(language_option_path) as OptionButton
	export_button = get_node_or_null(export_button_path) as Button
	clear_button = get_node_or_null(clear_button_path) as Button
	status_label = get_node_or_null(status_label_path) as Label
	code_preview = get_node_or_null(code_preview_path) as TextEdit

	if block_canvas == null:
		var old_block_node: Node = get_node_or_null(block_list_path)
		if old_block_node is ScratchWorkspace:
			block_canvas = old_block_node

func _ui_is_missing_core_nodes() -> bool:
	return palette_list == null or language_option == null or export_button == null or clear_button == null or status_label == null or code_preview == null

func _build_default_ui() -> void:
	_clear_children(self)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "BlockCodingPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.08, 0.08, 0.98), Color(1, 1, 1, 0.08), 1, 12))
	add_child(panel)

	var split: HSplitContainer = HSplitContainer.new()
	split.name = "HSplitContainer"
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.split_offset = 280
	panel.add_child(split)

	var palette_panel: PanelContainer = PanelContainer.new()
	palette_panel.name = "PalettePanel"
	palette_panel.custom_minimum_size = Vector2(280, 0)
	palette_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.075, 0.075, 0.075, 0.98), Color(1, 1, 1, 0.05), 1, 10))
	split.add_child(palette_panel)

	var palette_scroll: ScrollContainer = ScrollContainer.new()
	palette_scroll.name = "PaletteScroll"
	palette_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette_panel.add_child(palette_scroll)

	var new_palette_list: VBoxContainer = VBoxContainer.new()
	new_palette_list.name = "PaletteList"
	new_palette_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_palette_list.add_theme_constant_override("separation", 8)
	palette_scroll.add_child(new_palette_list)

	var workspace_panel: PanelContainer = PanelContainer.new()
	workspace_panel.name = "WorkspacePanel"
	workspace_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.105, 0.105, 0.105, 0.98), Color(1, 1, 1, 0.06), 1, 10))
	split.add_child(workspace_panel)

	var workspace_vbox: VBoxContainer = VBoxContainer.new()
	workspace_vbox.name = "WorkspaceVBox"
	workspace_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace_vbox.add_theme_constant_override("separation", 8)
	workspace_panel.add_child(workspace_vbox)

	var toolbar: HBoxContainer = HBoxContainer.new()
	toolbar.name = "Toolbar"
	toolbar.custom_minimum_size = Vector2(0, 42)
	toolbar.add_theme_constant_override("separation", 10)
	workspace_vbox.add_child(toolbar)

	var lang_label: Label = Label.new()
	lang_label.name = "LanguageLabel"
	lang_label.text = "Language"
	toolbar.add_child(lang_label)

	var new_language_option: OptionButton = OptionButton.new()
	new_language_option.name = "LanguageOption"
	toolbar.add_child(new_language_option)

	var new_export_button: Button = Button.new()
	new_export_button.name = "ExportButton"
	new_export_button.text = "Export"
	toolbar.add_child(new_export_button)

	var new_clear_button: Button = Button.new()
	new_clear_button.name = "ClearButton"
	new_clear_button.text = "Clear"
	toolbar.add_child(new_clear_button)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	var new_status_label: Label = Label.new()
	new_status_label.name = "StatusLabel"
	new_status_label.text = "Ready"
	new_status_label.modulate = Color(1, 1, 1, 0.65)
	toolbar.add_child(new_status_label)

	var workspace_scroll: ScrollContainer = ScrollContainer.new()
	workspace_scroll.name = "WorkspaceScroll"
	workspace_scroll.custom_minimum_size = Vector2(0, 350)
	workspace_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	workspace_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	workspace_vbox.add_child(workspace_scroll)

	var new_block_canvas: ScratchWorkspace = ScratchWorkspaceClass.new()
	new_block_canvas.name = "BlockCanvas"
	new_block_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_block_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace_scroll.add_child(new_block_canvas)

	var new_code_preview: TextEdit = TextEdit.new()
	new_code_preview.name = "CodePreview"
	new_code_preview.custom_minimum_size = Vector2(0, 190)
	new_code_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_code_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	new_code_preview.editable = false
	new_code_preview.placeholder_text = "Lua output appears here."
	workspace_vbox.add_child(new_code_preview)

	palette_list_path = NodePath("BlockCodingPanel/HSplitContainer/PalettePanel/PaletteScroll/PaletteList")
	block_canvas_path = NodePath("BlockCodingPanel/HSplitContainer/WorkspacePanel/WorkspaceVBox/WorkspaceScroll/BlockCanvas")
	language_option_path = NodePath("BlockCodingPanel/HSplitContainer/WorkspacePanel/WorkspaceVBox/Toolbar/LanguageOption")
	export_button_path = NodePath("BlockCodingPanel/HSplitContainer/WorkspacePanel/WorkspaceVBox/Toolbar/ExportButton")
	clear_button_path = NodePath("BlockCodingPanel/HSplitContainer/WorkspacePanel/WorkspaceVBox/Toolbar/ClearButton")
	status_label_path = NodePath("BlockCodingPanel/HSplitContainer/WorkspacePanel/WorkspaceVBox/Toolbar/StatusLabel")
	code_preview_path = NodePath("BlockCodingPanel/HSplitContainer/WorkspacePanel/WorkspaceVBox/CodePreview")

func _upgrade_legacy_block_list_to_canvas() -> void:
	if block_canvas != null:
		return
	var old_block_node: Control = get_node_or_null(block_list_path) as Control
	if old_block_node == null:
		return
	var parent: Node = old_block_node.get_parent()
	if parent == null:
		return

	parent.remove_child(old_block_node)
	old_block_node.queue_free()

	var new_canvas: ScratchWorkspace = ScratchWorkspaceClass.new()
	new_canvas.name = "BlockCanvas"
	new_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(new_canvas)
	block_canvas = new_canvas
	block_canvas_path = get_path_to(new_canvas)

func _make_self_visible_if_collapsed() -> void:
	if get_parent() is Control and (size.x < 120.0 or size.y < 120.0):
		set_anchors_preset(Control.PRESET_FULL_RECT)
		offset_left = 0
		offset_top = 0
		offset_right = 0
		offset_bottom = 0

func _build_language_options() -> void:
	if language_option == null:
		return
	language_option.clear()
	var ids: Array = emitters.keys()
	ids.sort()
	for language_id in ids:
		language_option.add_item(String(language_id))
	if language_option.item_count > 0:
		language_option.selected = 0
	if not language_option.item_selected.is_connected(_on_language_selected):
		language_option.item_selected.connect(_on_language_selected)

func _build_palette() -> void:
	if palette_list == null:
		return
	_clear_children(palette_list)

	var by_category: Dictionary = {}
	for definition in catalog.values():
		if not by_category.has(definition.category):
			by_category[definition.category] = []
		by_category[definition.category].append(definition)

	var categories: Array = by_category.keys()
	categories.sort()
	for category in categories:
		var header: Label = Label.new()
		header.text = String(category)
		header.modulate = Color(1, 1, 1, 0.62)
		header.add_theme_font_size_override("font_size", 13)
		header.custom_minimum_size = Vector2(0, 26)
		palette_list.add_child(header)

		var definitions: Array = by_category[category]
		definitions.sort_custom(func(a: BlockDefinition, b: BlockDefinition) -> bool:
			return a.label < b.label
		)

		for definition in definitions:
			var view: ScratchBlockView = ScratchBlockViewClass.new()
			view.background_color = Color(0.075, 0.075, 0.075, 1.0)
			view.set_definition(definition, true)
			view.tooltip_text = definition.description
			view.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			view.palette_block_pressed.connect(_on_palette_block_pressed)
			palette_list.add_child(view)

func _render_workspace() -> void:
	if block_canvas == null:
		return
	block_canvas.set_program(program)

func _connect_buttons() -> void:
	if export_button != null and not export_button.pressed.is_connected(_on_export_pressed):
		export_button.pressed.connect(_on_export_pressed)
	if clear_button != null and not clear_button.pressed.is_connected(_on_clear_pressed):
		clear_button.pressed.connect(_on_clear_pressed)

func _connect_workspace() -> void:
	if block_canvas == null:
		return
	block_canvas.set_program(program)
	if not block_canvas.block_edit_requested.is_connected(_on_block_edit_requested):
		block_canvas.block_edit_requested.connect(_on_block_edit_requested)
	if not block_canvas.block_delete_requested.is_connected(_on_block_delete_requested):
		block_canvas.block_delete_requested.connect(_on_block_delete_requested)
	if not block_canvas.workspace_changed.is_connected(_on_workspace_visual_changed):
		block_canvas.workspace_changed.connect(_on_workspace_visual_changed)
	if not block_canvas.order_changed.is_connected(_on_workspace_order_changed):
		block_canvas.order_changed.connect(_on_workspace_order_changed)

func _on_palette_block_pressed(block_id: StringName) -> void:
	add_block_by_id(block_id)

func _on_export_pressed() -> void:
	export_code()

func _on_clear_pressed() -> void:
	clear_program()

func _on_language_selected(_index: int) -> void:
	_refresh_preview()

func _on_workspace_visual_changed() -> void:
	_refresh_preview()

func _on_workspace_order_changed() -> void:
	_emit_changed()

func _on_block_delete_requested(block: BlockInstance) -> void:
	if block == null:
		return
	if block_canvas != null:
		block_canvas.remove_block_from_program(block)
	else:
		program.roots.erase(block)
	_emit_changed()

func _on_block_edit_requested(block: BlockInstance) -> void:
	if block == null or block.definition == null:
		return
	_open_argument_editor(block)

func _emit_changed() -> void:
	program_changed.emit(program)
	_refresh_preview()

func _refresh_preview() -> void:
	if not auto_preview:
		return
	if emitters.is_empty():
		return
	var language_id: StringName = get_selected_language()
	if not emitters.has(language_id):
		return
	if block_canvas != null:
		block_canvas.sort_program_by_layout()
	var emitter: BlockLanguageEmitter = emitters[language_id]
	if code_preview != null:
		code_preview.text = emitter.emit_program(program)

func _open_argument_editor(block: BlockInstance) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "Edit block arguments"
	dialog.min_size = Vector2(460, 160)
	add_child(dialog)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	dialog.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = block.definition.label
	title.modulate = Color(1, 1, 1, 0.8)
	vbox.add_child(title)

	var editors: Array[LineEdit] = []
	for schema in block.definition.input_schema:
		var name: StringName = StringName(str(schema.get("name", "")))
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vbox.add_child(row)

		var label: Label = Label.new()
		label.text = String(name)
		label.custom_minimum_size = Vector2(120, 0)
		row.add_child(label)

		var edit: LineEdit = LineEdit.new()
		edit.text = _argument_to_editor_text(block.get_argument(name, block.definition.defaults.get(name, "")))
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.set_meta("arg_name", name)
		edit.set_meta("arg_type", StringName(str(schema.get("type", "raw"))))
		row.add_child(edit)
		editors.append(edit)

	if editors.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "This block has no editable arguments."
		empty_label.modulate = Color(1, 1, 1, 0.55)
		vbox.add_child(empty_label)

	dialog.confirmed.connect(func() -> void:
		for edit in editors:
			var arg_name: StringName = edit.get_meta("arg_name")
			var arg_type: StringName = edit.get_meta("arg_type")
			block.set_argument(arg_name, _editor_text_to_argument(edit.text, arg_type))
		if block_canvas != null:
			block_canvas.refresh_visual_text()
		_emit_changed()
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
	)
	dialog.popup_centered(Vector2(500, max(170, 90 + editors.size() * 42)))

func _argument_to_editor_text(value: Variant) -> String:
	if value == null:
		return ""
	return str(value)

func _editor_text_to_argument(text: String, arg_type: StringName) -> Variant:
	var t: String = text.strip_edges()
	match String(arg_type):
		"number":
			if t.is_valid_int():
				return t.to_int()
			if t.is_valid_float():
				return t.to_float()
			return 0
		"bool":
			return t.to_lower() in ["true", "1", "yes", "y", "да"]
		"string":
			return text
		_:
			return text

func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _panel_style(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8
	style.content_margin_top = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	return style
