class_name Gem
extends Node2D
## A single board piece. Owns its procedural shader visual, a one-shot particle
## burst for clears, and all the per-gem juice (select pulse, swap, fall, pop).

const NONE := 0
const STRIPE := 1   ## clears its whole row + column when matched
const BOMB := 2     ## clears every gem of its colour when matched

const COLORS := [
	Color("#ff5c7a"),  # rose
	Color("#ffb020"),  # amber
	Color("#36e07a"),  # jade
	Color("#38bdf8"),  # azure
	Color("#a78bfa"),  # violet
	Color("#eef2ff"),  # diamond
]

var type: int = 0
var col: int = 0
var row: int = 0
var special: int = NONE

var _size: float = 80.0
var _sprite: Sprite2D
var _mat: ShaderMaterial
var _burst: GPUParticles2D
var _sel_tween: Tween

# Shared, lazily-built textures (one white quad, one soft dot for particles).
static var _white: Texture2D
static var _dot: Texture2D

static func _white_tex() -> Texture2D:
	if _white == null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	return _white

static func _dot_tex() -> Texture2D:
	if _dot == null:
		var n := 32
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var c := Vector2(n, n) * 0.5
		for y in n:
			for x in n:
				var dist := Vector2(x + 0.5, y + 0.5).distance_to(c) / (n * 0.5)
				var a: float = clamp(1.0 - dist, 0.0, 1.0)
				a = a * a
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_dot = ImageTexture.create_from_image(img)
	return _dot


func setup(p_type: int, gem_size: float, shader: Shader) -> void:
	type = p_type
	_size = gem_size

	_sprite = Sprite2D.new()
	_sprite.texture = _white_tex()
	_sprite.scale = Vector2.ONE * (_size / 8.0)
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("base_color", COLORS[type])
	_sprite.material = _mat
	add_child(_sprite)

	_burst = GPUParticles2D.new()
	_burst.texture = _dot_tex()
	_burst.amount = 18
	_burst.one_shot = true
	_burst.emitting = false
	_burst.lifetime = 0.6
	_burst.explosiveness = 1.0
	_burst.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = _size * 0.25
	pm.direction = Vector3(0, 0, 0)
	pm.spread = 180.0
	pm.gravity = Vector3(0, 320, 0)
	pm.initial_velocity_min = 120.0
	pm.initial_velocity_max = 320.0
	pm.angular_velocity_min = -400.0
	pm.angular_velocity_max = 400.0
	pm.scale_min = 0.3
	pm.scale_max = 0.8
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	pm.scale_curve = _wrap_curve(curve)
	pm.color = COLORS[type]
	_burst.process_material = pm
	add_child(_burst)


func _wrap_curve(c: Curve) -> CurveTexture:
	var t := CurveTexture.new()
	t.curve = c
	return t


func set_special(kind: int) -> void:
	special = kind
	_mat.set_shader_parameter("special", kind)
	# A quick flourish when a special is forged.
	var t := create_tween()
	t.tween_property(_sprite, "scale", Vector2.ONE * (_size / 8.0) * 1.35, 0.12)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_sprite, "scale", Vector2.ONE * (_size / 8.0), 0.18)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func set_selected(on: bool) -> void:
	var base := Vector2.ONE * (_size / 8.0)
	if _sel_tween and _sel_tween.is_valid():
		_sel_tween.kill()
	if on:
		# A continuous breathing pulse: scale + glow oscillate together so the
		# picked gem reads as alive, with the shader halo blooming around it.
		_sprite.scale = base * 1.1
		_sel_tween = create_tween().set_loops()
		_sel_tween.tween_property(_sprite, "scale", base * 1.2, 0.5)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_sel_tween.parallel().tween_method(_set_sel, 1.0, 0.55, 0.5)
		_sel_tween.tween_property(_sprite, "scale", base * 1.06, 0.5)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_sel_tween.parallel().tween_method(_set_sel, 0.55, 1.0, 0.5)
	else:
		_set_sel(0.0)
		var t := create_tween()
		t.tween_property(_sprite, "scale", base, 0.18)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_sel(v: float) -> void:
	_mat.set_shader_parameter("selected", v)


## Drop/slide into a position with a springy landing. Returns the tween so the
## board can await the whole wave at once.
func move_to(target: Vector2, duration: float, delay: float = 0.0,
		trans: int = Tween.TRANS_BACK) -> void:
	var t := create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_property(self, "position", target, duration)\
		.set_trans(trans).set_ease(Tween.EASE_OUT)


## Clear animation: fire particles, flash white, shrink + spin away.
func pop() -> void:
	_burst.restart()
	_burst.emitting = true
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_sprite, "scale", Vector2.ONE * (_size / 8.0) * 1.4, 0.10)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(_sprite, "scale", Vector2.ZERO, 0.18)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_sprite, "rotation", randf_range(-PI, PI), 0.28)
	# Free after the burst has lived its life.
	await get_tree().create_timer(0.65).timeout
	queue_free()
