extends Control
@export var _unit: Control
@export var grid_padding: float = 0.0
@export var grid: Vector2i = Vector2i.ZERO
@export var target_grid: Vector2i = Vector2i.ZERO
@export var max_displayed: int = 20

@export var group: int = 5
var tg: Vector2 = Vector2.ZERO

func _draw() -> void:
	if _unit == null:
		return
	if tg < Vector2(1,1): return
	
	var cw = _unit.size.x + grid_padding
	var ch = _unit.size.y + grid_padding
	if cw <= 0.0 or ch <= 0.0:
		return
	
	var vis_w = tg.x
	var vis_h = tg.y
	var cols = min(int(floor(vis_w / cw)), max_displayed)
	var rows = min(int(floor(vis_h / ch)), max_displayed)
	var c = Color.WHITE
	
	for x in range(0, cols + 1):
		if x % group != 0:
			continue
		var xpx = x * cw - 0.25
		draw_line(Vector2(xpx, -1), Vector2(xpx, vis_h), c, 1.5)
	# trailing vertical edge at the animated boundary
	if vis_w > 0.0 and int(floor(vis_w / cw)) <= max_displayed:
		var xedge = vis_w - 0.25
		draw_line(Vector2(xedge, -1), Vector2(xedge, vis_h), c, 1.5)
	
	for y in range(0, rows + 1):
		if y % group != 0:
			continue
		var ypx = y * ch - 0.25
		draw_line(Vector2(-1, ypx), Vector2(vis_w, ypx), c, 1.5)
	# trailing horizontal edge
	if vis_h > 0.0 and int(floor(vis_h / ch)) <= max_displayed:
		var yedge = vis_h - 0.25
		draw_line(Vector2(-1, yedge), Vector2(vis_w, yedge), c, 1.5)

func _process(delta: float) -> void:
	queue_redraw()
	if _unit == null:
		return
	#("fjfj")
	
	var cw = _unit.size.x + grid_padding
	var ch = _unit.size.y + grid_padding
	
	var grid_size = Vector2(grid.x * cw, grid.y * ch)
	var target_size = Vector2(target_grid.x * cw, target_grid.y * ch)
	
	# keep control big enough for both directions (prevents clipping while expanding)
	size = Vector2(max(grid_size.x, grid_size.x), max(grid_size.y, grid_size.y))
	
	# animate toward target_grid (this is the FIX for shrinking)
	glob.inst_uniform(self, "extents", 
	Vector4(0, ch * max_displayed + global_position.y,0,cw * max_displayed + global_position.x))
	tg = tg.lerp(grid_size, delta * 15.0)
