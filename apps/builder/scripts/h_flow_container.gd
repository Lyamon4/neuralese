extends HFlowContainer

# Configurable properties
@export var chip_color: Color = Color(0.25, 0.5, 0.8, 1.0)
@export var chip_text_color: Color = Color.WHITE
@export var chip_padding: Vector2 = Vector2(12, 6)
@export var chip_spacing: int = 6
@export var font_size: int = 14

# Internal state
var tags: Array[String] = []
var line_edit: ValidInput
var chips: Array[PanelContainer] = []
var spacer: Control

func _ready() -> void:
	add_theme_constant_override("h_separation", chip_spacing)
	add_theme_constant_override("v_separation", chip_spacing)
	
	# Create a spacer control
	spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 0)
	spacer.visible = false  # Hidden when no tags
	add_child(spacer)
	
	# Create the input field
	line_edit = ValidInput.new()
	line_edit.auto_enter = false
	line_edit.resize_after = 6
	line_edit.max_length = 16
	line_edit.expand_to_text_length = true
	line_edit.placeholder_text = "Class"
	line_edit.custom_minimum_size = Vector2(80, 32)
	line_edit.size = Vector2(80, 32)
	
	# Connect signals
	line_edit.focus_exited.connect(_on_text_submitted)
	line_edit.text_submitted.connect(_on_text_submitted)
#	line_edit.submitted.connect(_on_submitted)
	#line_edit.gui_input.connect(_on_line_edit_input)
	
	add_child(line_edit)

func _on_text_submitted(...args) -> void:
	var text = line_edit.text
	var trimmed = (text if text != "" else line_edit.text).strip_edges()
	if trimmed.is_empty():
		await get_tree().process_frame
		line_edit.set_line("")
		return
	
	var new_tags = trimmed.split(" ", false)
	for tag in new_tags:
		var clean_tag = tag.strip_edges()
		if not clean_tag.is_empty() and not tags.has(clean_tag):
			add_tag(clean_tag)
	
	line_edit.set_line("")  # Clears but keeps focus!
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	line_edit.grab()  # Optional: force focus back just in case


func _on_submitted() -> void:
	#("AAA")
	var text = line_edit.text.strip_edges()
	if not text.is_empty() and not tags.has(text):
		add_tag(text)
	line_edit.set_line("")

func _process(delta: float) -> void:
	pass

#func _unhandled_input(event: InputEvent) -> void:
	#if event is InputEventKey and event.is_pressed():
		#(KEY_ENTER)
		##(event.keycode, " ", KEY_ENTER)
		#if event.keycode == KEY_ENTER:
			#var text = line_edit.text.strip_edges()
			#
			#if not text.is_empty() and not tags.has(text):
				#add_tag(text)
				#get_viewport().set_input_as_handled()
			#await get_tree().process_frame
			#line_edit.set_line("")
	

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Handle space as submission
		#(event.keycode, KEY_ENTER)
		if event.keycode == KEY_SPACE:
			var text = line_edit.text.strip_edges()
			
			if not text.is_empty() and not tags.has(text):
				add_tag(text)
				#get_viewport().set_input_as_handled()
			await get_tree().process_frame
			line_edit.set_line("")
		
		# Handle backspace when input is empty
		elif event.keycode == KEY_BACKSPACE:
			if line_edit.text.is_empty() and tags.size() > 0:
				remove_tag(tags.size() - 1)
				#get_viewport().set_input_as_handled()

@export var border_color: Color = Color.WHITE

func add_tag(tag: String) -> void:
	tags.append(tag)
	
	# Create chip container
	var chip = PanelContainer.new()
	
	# Create custom StyleBox for the chip
	var style = StyleBoxFlat.new()
	style.bg_color = chip_color
	style.set_border_width_all(2)
	style.border_color = border_color
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.content_margin_left = chip_padding.x
	style.content_margin_right = chip_padding.x
	style.content_margin_top = chip_padding.y
	style.content_margin_bottom = chip_padding.y
	
	chip.add_theme_stylebox_override("panel", style)
	
	# Create label
	var label = Label.new()
	label.text = tag
	label.add_theme_color_override("font_color", chip_text_color)
	label.add_theme_font_size_override("font_size", font_size)
	
	chip.add_child(label)
	chips.append(chip)
	
	# Insert chip before the spacer
	var spacer_index = spacer.get_index()
	add_child(chip)
	move_child(chip, spacer_index)
	
	# Show spacer when we have tags
	spacer.visible = true
	
	tag_added.emit(tag)

func clear():
	print(tags)
	for i in len(tags):
		remove_tag(0)

func remove_tag(index: int) -> void:
	if index < 0 or index >= tags.size():
		return
	
	var removed_tag = tags[index]
	tags.remove_at(index)
	
	var chip = chips[index]
	chips.remove_at(index)
	chip.queue_free()
	
	# Hide spacer when no tags remain
	if tags.size() == 0:
		spacer.visible = false
	
	tag_removed.emit(removed_tag)

func get_tags() -> Array[String]:
	return tags.duplicate()

func set_tags(new_tags: Array[String]) -> void:
	clear_tags()
	for tag in new_tags:
		if not tag.strip_edges().is_empty():
			add_tag(tag.strip_edges())

func clear_tags() -> void:
	for chip in chips:
		chip.queue_free()
	chips.clear()
	tags.clear()

# Signals
signal tag_added(tag: String)
signal tag_removed(tag: String)
