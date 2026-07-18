@tool
extends Line2D

var expression_compiled: Expression = null
var status: int = 0
@export_custom(PROPERTY_HINT_EXPRESSION, "") var expr = "":
	set(v):
		expr = v
		expression_compiled = Expression.new()
		status = expression_compiled.parse(v, ["x"])

func _formula(x: float) -> float:
	return expression_compiled.execute([x])

func update():
	if status != OK: return
	var new_points = PackedVector2Array()
	for i in range(-25, 25):
		new_points.append(Vector2(i*4+25*4,-_formula(i*4)*10))
	points = new_points
