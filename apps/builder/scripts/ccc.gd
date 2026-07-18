extends Control

@onready var mat: ShaderMaterial = material
var noise = FastNoiseLite.new()

var current_target: Vector2
var velocity: Vector2 = Vector2.ZERO
var move_timer = 0.0
var last_pos: Vector2

# === Tunables ===
@export var MOVE_INTERVAL = 2.5
@export var HOLD_TIME = 0.5
@export var LERP_SPEED = 1.2
@export var MARGIN = 64.0
@export var NOISE_STRENGTH_IDLE = 0.02
@export var NOISE_STRENGTH_MOVE = 0.08
@export var NOISE_FALLOFF = 2.0
@export var CENTER_BIAS = 0.6
@export var RETURN_FORCE = 3.5
@export var MAX_SPEED = 400.0               # pixels / s, clamp for safety

var velocity_noise_seed = randf() * 1000.0
var hold_timer = 0.0

var is_stopped: bool = false

func stop():
	hide()
	is_stopped = true

func resume():
	show()
	is_stopped = false

var tg_visible: bool = false
func target_visible():
	#global_position += (glob.cam.get_screen_center_position() - size / 2 - global_position) / 2.0
	#(global_position)
	tg_visible = true
	show()

func target_invisible():
	tg_visible = false

func _ready() -> void:
	self_modulate.a = 0.0
	hide()
	tg_visible = false
	target_invisible()
	ui.axon_donut = self
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.6
	current_target = position
	last_pos = position
	move_timer = MOVE_INTERVAL * randf()

func _process(delta: float) -> void:
	if is_stopped: return
	if not visible:
		return
	if tg_visible:
		self_modulate.a = lerpf(self_modulate.a, 1.0, delta * 10.0)
	else:
		self_modulate.a = lerpf(self_modulate.a, 0.0, delta * 10.0)
		if is_zero_approx(self_modulate.a):
			hide()
	var rect_world: Rect2 = glob.get_world_visible_rect()

	var donut_size: Vector2 = size
	var half: Vector2 = donut_size * 0.5
	var center = position + half

	# --- Correct playable rect ---
	# shrink only by MARGIN, not by half again
	var inner_pos = rect_world.position + Vector2(MARGIN, MARGIN)
	var inner_size = rect_world.size - Vector2(MARGIN, MARGIN) * 2.0
	if inner_size.x <= 1.0 or inner_size.y <= 1.0:
		return
	var rect_inner = Rect2(inner_pos, inner_size)

	# === Timed movement ===
	move_timer -= delta
	if move_timer <= 0.0:
		move_timer = MOVE_INTERVAL + randf() * 1.2
		current_target = _pick_new_point(rect_inner, rect_inner.get_center())

	# === Velocity + noise on CENTER ===
	var desired = current_target - center
	velocity = velocity.lerp(desired, delta * LERP_SPEED)
	if velocity.length() > MAX_SPEED:
		velocity = velocity.normalized() * MAX_SPEED

	var t = Time.get_ticks_msec() / 1000.0
	var speed_factor = pow(clamp(velocity.length() / MAX_SPEED, 0.0, 1.0), NOISE_FALLOFF)
	var base_strength = lerp(NOISE_STRENGTH_IDLE, NOISE_STRENGTH_MOVE, speed_factor)
	var n_off = Vector2(
		noise.get_noise_1d(t * 0.8 + velocity_noise_seed),
		noise.get_noise_1d(t * 0.8 + velocity_noise_seed + 100.0)
	) * rect_world.size * base_strength

	center += (velocity + n_off) * delta

	# === Containment ===
	var clamped_center = center.clamp(
		rect_inner.position,
		rect_inner.position + rect_inner.size
	)
	if clamped_center != center:
		if center.x <= rect_inner.position.x + half.x or center.x >= rect_inner.position.x + rect_inner.size.x - half.x:
			velocity.x *= -0.4
		if center.y <= rect_inner.position.y + half.y or center.y >= rect_inner.position.y + rect_inner.size.y - half.y:
			velocity.y *= -0.4
		center = clamped_center

	position = center - half

	var alpha = mat.get_shader_parameter("alpha_power")
	alpha = lerp(alpha, 1.0, 0.04)
	mat.set_shader_parameter("alpha_power", alpha)




# --- Pick new random destination, biased away from corners ---
func _pick_new_point(rect: Rect2, center: Vector2) -> Vector2:
	var inner = rect.size
	var best_point = rect.position + Vector2(randf(), randf()) * inner
	var best_score = -INF
	for i in range(6):
		var test_point = rect.position + Vector2(randf(), randf()) * inner
		var corner_dist = min(
			test_point.distance_to(rect.position),
			test_point.distance_to(rect.position + Vector2(inner.x, 0.0)),
			test_point.distance_to(rect.position + Vector2(0.0, inner.y)),
			test_point.distance_to(rect.position + inner)
		)
		var dist_to_center = test_point.distance_to(center)
		var center_factor = 1.0 - (dist_to_center / (inner.length() * 0.5))
		var score = corner_dist * 0.8 + center_factor * 0.2
		if score > best_score:
			best_score = score
			best_point = test_point
	return best_point
