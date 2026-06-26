extends CanvasLayer
## Screen-space SPECTACLE: an excited voice announcer + big punchy combo text +
## full-screen colour flash + chromatic punch. Registered as the `Announcer`
## autoload so it renders above everything.
##
## The callouts are REAL recorded voice lines (generated from a free neural TTS
## voice, bundled as .ogg) and the text uses a chunky arcade display font. This is
## the part a producer/animator actually feels — juice you can *hear* and *read*,
## not just shader math.

const VOICE_DIR := "res://assets/voice/"
const FONT_PATH := "res://assets/fonts/LuckiestGuy.ttf"
const W := 720.0
const H := 1280.0

# combo tier -> callout text + which voice clip + colour + font size.
# Index 0 == combo 2 (the first time we shout). Higher combos escalate.
const TIERS := [
	{"texts": ["NICE!", "SWEET!"],            "voices": ["nice", "sweet"],            "color": Color("#ffe66d"), "size": 96},
	{"texts": ["GREAT!", "AWESOME!"],         "voices": ["great", "awesome"],         "color": Color("#ffd23f"), "size": 108},
	{"texts": ["EXCELLENT!", "AMAZING!"],     "voices": ["excellent", "amazing"],     "color": Color("#ff9f43"), "size": 120},
	{"texts": ["INCREDIBLE!", "COMBO!"],      "voices": ["incredible", "combo"],      "color": Color("#ff6b9d"), "size": 132},
	{"texts": ["UNSTOPPABLE!", "SPECTACULAR!"], "voices": ["unstoppable", "spectacular"], "color": Color("#54e1ff"), "size": 146},
	{"texts": ["MEGA COMBO!", "GEM CASCADE!"], "voices": ["megacombo", "cascade"],    "color": Color("#c08bff"), "size": 162},
]

var _font: Font
var _voices := {}
var _players: Array[AudioStreamPlayer] = []
var _vnext := 0
var _flash: ColorRect
var _last_idx := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20

	_font = load(FONT_PATH)

	# A pool of players so overlapping callouts during fast cascades don't cut off.
	for _i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = 1.0
		add_child(p)
		_players.append(p)

	# Pre-load every voice clip.
	for key in ["go", "nice", "sweet", "great", "awesome", "excellent", "amazing",
			"incredible", "unstoppable", "spectacular", "combo", "megacombo",
			"boom", "kaboom", "cascade", "wow"]:
		var path: String = VOICE_DIR + key + ".ogg"
		if ResourceLoader.exists(path):
			_voices[key] = load(path)

	# Full-screen additive flash plate (screen punch on big clears).
	_flash = ColorRect.new()
	_flash.size = Vector2(W, H)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flash.material = cm
	add_child(_flash)


# ---------------------------------------------------------------- voice ---
func say(key: String, pitch: float = 1.0, vol_db: float = 1.0) -> void:
	if Audio.muted or not _voices.has(key):
		return
	var p := _players[_vnext]
	_vnext = (_vnext + 1) % _players.size()
	p.stream = _voices[key]
	p.pitch_scale = pitch
	p.volume_db = vol_db
	p.play()


# The headline call: combo >= 2 fires an escalating shout + big text + flash.
func hype(combo: int) -> void:
	var idx: int = clampi(combo - 2, 0, TIERS.size() - 1)
	var tier: Dictionary = TIERS[idx]
	# Alternate the two phrasings so it never feels canned on repeats.
	var pick: int = (combo + (1 if idx == _last_idx else 0)) % tier["texts"].size()
	_last_idx = idx

	var text: String = tier["texts"][pick]
	var color: Color = tier["color"]
	var size: int = tier["size"]
	# Pitch the voice up a touch as combos climb — energy ramp.
	say(tier["voices"][pick], 1.0 + idx * 0.03, 2.0)
	bigtext(text, color, size, idx)
	flash(color, 0.12 + idx * 0.06)


# ------------------------------------------------------------- big text ---
func bigtext(text: String, color: Color, size: int, intensity: int = 0) -> void:
	var lbl := Label.new()
	lbl.text = text
	if _font:
		lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.08, 0.9))
	lbl.add_theme_constant_override("outline_size", 16)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	lbl.add_theme_constant_override("shadow_offset_x", 0)
	lbl.add_theme_constant_override("shadow_offset_y", 8)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size = Vector2(W, size * 1.5)
	lbl.position = Vector2(0, 600 - size * 0.75)
	lbl.pivot_offset = lbl.size * 0.5
	lbl.scale = Vector2.ZERO
	lbl.rotation = deg_to_rad(randf_range(-7.0, 7.0))
	add_child(lbl)

	var t := create_tween()
	# Punch in past 1.0, settle with an elastic snap.
	t.tween_property(lbl, "scale", Vector2.ONE * 1.18, 0.16)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "scale", Vector2.ONE, 0.18)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.34 + intensity * 0.05)
	# Fly up + fade out.
	t.set_parallel(true)
	t.tween_property(lbl, "position:y", lbl.position.y - 90, 0.45)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(lbl, "modulate:a", 0.0, 0.45)
	t.tween_property(lbl, "scale", Vector2.ONE * 1.3, 0.45)
	t.chain().tween_callback(lbl.queue_free)


# --------------------------------------------------------------- flash ---
func flash(color: Color, strength: float) -> void:
	if _flash == null:
		return
	_flash.color = Color(color.r, color.g, color.b, 1.0)
	_flash.modulate.a = 1.0
	var t := create_tween()
	t.tween_property(_flash, "color:a", strength, 0.02)
	t.tween_property(_flash, "color:a", 0.0, 0.32)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
