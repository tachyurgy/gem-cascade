class_name Gem
extends Node2D
## A single board piece. Owns its procedural shader visual, an ADDITIVE glow halo
## (reads as bloom on any renderer), textured spark + shard particle bursts for
## clears, and all the per-gem juice (select pulse, swap, fall, pop).

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
var _glow: Sprite2D            # additive halo under the gem
var _mat: ShaderMaterial
var _burst: GPUParticles2D     # round soft puff
var _spark: GPUParticles2D     # bright textured stars
var _shard: GPUParticles2D     # angular gem shards
var _sel_tween: Tween
var _glow_base: float = 0.42

# Shared, lazily-built / loaded textures.
static var _white: Texture2D
static var _glow_tex: Texture2D
static var _spark_tex: Texture2D
static var _shard_tex: Texture2D
static var _dot: Texture2D

static func _white_tex() -> Texture2D:
	if _white == null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	return _white

static func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return _dot_tex()

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

static func _add_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


func setup(p_type: int, gem_size: float, shader: Shader) -> void:
	type = p_type
	_size = gem_size
	if _glow_tex == null:
		_glow_tex = _load_tex("res://assets/particles/glow.png")
		_spark_tex = _load_tex("res://assets/particles/spark.png")
		_shard_tex = _load_tex("res://assets/particles/shard.png")

	# Additive glow halo BEHIND the gem — soft coloured bloom that makes the whole
	# board feel lit. Sits at a lower z so it never washes the gloss highlight out.
	_glow = Sprite2D.new()
	_glow.texture = _glow_tex
	_glow.material = _add_material()
	var gscale := (_size * 1.9) / float(_glow_tex.get_width())
	_glow.scale = Vector2.ONE * gscale
	_glow.modulate = Color(COLORS[type].r, COLORS[type].g, COLORS[type].b, _glow_base)
	_glow.z_index = -1
	add_child(_glow)

	_sprite = Sprite2D.new()
	_sprite.texture = _white_tex()
	_sprite.scale = Vector2.ONE * (_size / 8.0)
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("base_color", COLORS[type])
	_sprite.material = _mat
	add_child(_sprite)

	# Soft round puff (additive, coloured).
	_burst = GPUParticles2D.new()
	_burst.texture = _glow_tex
	_burst.amount = 14
	_burst.one_shot = true
	_burst.emitting = false
	_burst.lifetime = 0.55
	_burst.explosiveness = 1.0
	_burst.local_coords = false
	_burst.material = _add_material()
	_burst.process_material = _puff_pm()
	add_child(_burst)

	# Bright textured stars that shoot out — the "pop sparkle".
	_spark = GPUParticles2D.new()
	_spark.texture = _spark_tex
	_spark.amount = 16
	_spark.one_shot = true
	_spark.emitting = false
	_spark.lifetime = 0.7
	_spark.explosiveness = 1.0
	_spark.local_coords = false
	_spark.material = _add_material()
	_spark.process_material = _spark_pm()
	add_child(_spark)

	# Angular gem shards that tumble with gravity.
	_shard = GPUParticles2D.new()
	_shard.texture = _shard_tex
	_shard.amount = 10
	_shard.one_shot = true
	_shard.emitting = false
	_shard.lifetime = 0.8
	_shard.explosiveness = 1.0
	_shard.local_coords = false
	_shard.process_material = _shard_pm()
	add_child(_shard)


func _puff_pm() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = _size * 0.2
	pm.spread = 180.0
	pm.gravity = Vector3(0, 60, 0)
	pm.initial_velocity_min = 60.0
	pm.initial_velocity_max = 180.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.scale_curve = _fade_curve()
	pm.color = Color(COLORS[type].r, COLORS[type].g, COLORS[type].b, 0.8)
	return pm


func _spark_pm() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = _size * 0.25
	pm.spread = 180.0
	pm.gravity = Vector3(0, 220, 0)
	pm.initial_velocity_min = 180.0
	pm.initial_velocity_max = 460.0
	pm.angular_velocity_min = -720.0
	pm.angular_velocity_max = 720.0
	pm.scale_min = 0.25
	pm.scale_max = 0.7
	pm.scale_curve = _fade_curve()
	pm.color = Color(1, 1, 1, 1)
	return pm


func _shard_pm() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = _size * 0.2
	pm.spread = 180.0
	pm.gravity = Vector3(0, 700, 0)
	pm.initial_velocity_min = 160.0
	pm.initial_velocity_max = 380.0
	pm.angular_velocity_min = -500.0
	pm.angular_velocity_max = 500.0
	pm.scale_min = 0.4
	pm.scale_max = 0.9
	pm.scale_curve = _fade_curve()
	pm.color = COLORS[type]
	return pm


func _fade_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(0.7, 0.8))
	curve.add_point(Vector2(1, 0))
	var t := CurveTexture.new()
	t.curve = curve
	return t


func set_special(kind: int) -> void:
	special = kind
	_mat.set_shader_parameter("special", kind)
	# A bigger, hotter glow announces a forged special.
	_glow_base = 0.75
	_glow.modulate.a = _glow_base
	var base := Vector2.ONE * (_size / 8.0)
	var t := create_tween()
	t.tween_property(_sprite, "scale", base * 1.4, 0.12)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_sprite, "scale", base, 0.20)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func set_selected(on: bool) -> void:
	var base := Vector2.ONE * (_size / 8.0)
	if _sel_tween and _sel_tween.is_valid():
		_sel_tween.kill()
	if on:
		# Breathing pulse: scale + shader halo + additive glow all swell together.
		_sprite.scale = base * 1.1
		_sel_tween = create_tween().set_loops()
		_sel_tween.tween_property(_sprite, "scale", base * 1.22, 0.5)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_sel_tween.parallel().tween_method(_set_sel, 1.0, 0.55, 0.5)
		_sel_tween.parallel().tween_property(_glow, "modulate:a", 0.95, 0.5)
		_sel_tween.tween_property(_sprite, "scale", base * 1.06, 0.5)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_sel_tween.parallel().tween_method(_set_sel, 0.55, 1.0, 0.5)
		_sel_tween.parallel().tween_property(_glow, "modulate:a", 0.55, 0.5)
	else:
		_set_sel(0.0)
		_glow.modulate.a = _glow_base
		var t := create_tween()
		t.tween_property(_sprite, "scale", base, 0.18)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_sel(v: float) -> void:
	_mat.set_shader_parameter("selected", v)


## Drop/slide into a position with a springy landing. On a real drop (TRANS_BOUNCE)
## it adds a quick squash-and-stretch so the gem feels like it has weight.
func move_to(target: Vector2, duration: float, delay: float = 0.0,
		trans: int = Tween.TRANS_BACK) -> void:
	var t := create_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_property(self, "position", target, duration)\
		.set_trans(trans).set_ease(Tween.EASE_OUT)
	if trans == Tween.TRANS_BOUNCE:
		var base := Vector2.ONE * (_size / 8.0)
		t.tween_property(_sprite, "scale", Vector2(base.x * 1.18, base.y * 0.82), 0.07)
		t.tween_property(_sprite, "scale", base, 0.14)\
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Clear animation: fire all bursts, flash the glow huge, shrink + spin away.
func pop() -> void:
	for p in [_burst, _spark, _shard]:
		p.restart()
		p.emitting = true

	# Glow flares to a bright white pop, then dies with the gem.
	_glow.modulate = Color(1, 1, 1, 1)
	var gt := create_tween()
	gt.tween_property(_glow, "scale", _glow.scale * 2.2, 0.18)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	gt.parallel().tween_property(_glow, "modulate:a", 0.0, 0.3)

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_sprite, "scale", Vector2.ONE * (_size / 8.0) * 1.5, 0.10)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(_sprite, "scale", Vector2.ZERO, 0.18)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_sprite, "rotation", randf_range(-PI, PI), 0.28)
	# Free after the longest burst has lived its life.
	await get_tree().create_timer(0.85).timeout
	queue_free()
