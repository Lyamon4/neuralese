extends GridVisualiser
class_name IconTextGrid

## Emitted when user single-clicks an item
signal item_selected(key: String, meta: Dictionary)

## Emitted when user double-clicks / activates an item
signal item_activated(key: String, meta: Dictionary)

var texture = load("res://game_assets/icons/usr.png")
func _ready() -> void:
	super()
	for i in range(100):
		add_text_item("hello%s"%i, "Mike Issakov")

func clear() -> void:
	_vis_begin_refresh()
	_vis_end_refresh()

## Public API — add a visual item
func add_text_item(
	key: String,
	text: String,
	icon: Texture2D = texture,
	tooltip: String = "",
	meta: Dictionary = {}
) -> void:
	add_item(
		key,
		text,
		icon,
		tooltip,
		meta
	)

## Batch helper (optional, but useful)
func add_items(items: Array) -> void:
	# items = [{ key, text, icon, tooltip?, meta? }, ...]
	var counter := 0
	for item in items:
		add_text_item(
			item.key,
			item.text,
			item.get("icon"),
			item.get("tooltip", ""),
			item.get("meta", {})
		)
		counter += 1
		if counter % batch_size == 0:
			await get_tree().process_frame

## Selection hook (single click)
func _on_item_selected(key: String, meta: Dictionary, tile: Control) -> void:
	item_selected.emit(key, meta)

## Activation hook (double click)
func _on_item_activated(key: String, meta: Dictionary, tile: Control) -> void:
	item_activated.emit(key, meta)
