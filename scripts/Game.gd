extends Node2D
## Root scene: builds the animated background, the HUD (score / moves / title) and
## the Board, then keeps the HUD in sync with board signals. The big combo callouts
## are owned by the `Announcer` autoload, so the HUD here stays clean and readable.

const BG_SHADER: Shader = preload("res://shaders/background.gdshader")
const DISPLAY_FONT := "res://assets/fonts/Bungee.ttf"
const TITLE_FONT := "res://assets/fonts/LuckiestGuy.ttf"

var _board: Board
var _score_lbl: Label
var _moves_lbl: Label
var _shuffle_lbl: Label
var _display_font: Font
var _title_font: Font

const W := 720.0
const H := 1280.0


func _ready() -> void:
	randomize()
	_display_font = _opt_font(DISPLAY_FONT)
	_title_font = _opt_font(TITLE_FONT)
	_build_background()
	_build_hud()
	_board = Board.new()
	# Connect before add_child: add_child runs Board._ready(), which emits the
	# initial score/moves — we must already be listening.
	_board.score_changed.connect(_on_score)
	_board.moves_changed.connect(_on_moves)
	_board.shuffled.connect(_on_shuffled)
	add_child(_board)


func _opt_font(path: String) -> Font:
	return load(path) if ResourceLoader.exists(path) else null


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.size = Vector2(W, H)
	bg.material = ShaderMaterial.new()
	bg.material.shader = BG_SHADER
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	layer.layer = -10
	layer.add_child(bg)
	add_child(layer)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	var title := Label.new()
	title.text = "GEM CASCADE"
	if _title_font:
		title.add_theme_font_override("font", _title_font)
	title.add_theme_font_size_override("font_size", 70)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	title.add_theme_color_override("font_outline_color", Color(0.62, 0.18, 0.55, 0.9))
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_shadow_color", Color(0.2, 0.05, 0.3, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 34)
	title.size = Vector2(W, 80)
	title.pivot_offset = Vector2(W * 0.5, 56)
	layer.add_child(title)
	# A gentle breathing pulse keeps the logo alive.
	var tt := create_tween().set_loops()
	tt.tween_property(title, "scale", Vector2.ONE * 1.03, 1.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tt.tween_property(title, "scale", Vector2.ONE, 1.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var subtitle := Label.new()
	subtitle.text = "swipe or tap to match three"
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.position = Vector2(0, 120)
	subtitle.size = Vector2(W, 30)
	layer.add_child(subtitle)

	_build_mute_button(layer)

	_score_lbl = _make_stat(layer, "SCORE", Vector2(40, 178), HORIZONTAL_ALIGNMENT_LEFT)
	_moves_lbl = _make_stat(layer, "MOVES", Vector2(W - 240, 178), HORIZONTAL_ALIGNMENT_RIGHT)

	_shuffle_lbl = Label.new()
	if _display_font:
		_shuffle_lbl.add_theme_font_override("font", _display_font)
	_shuffle_lbl.add_theme_font_size_override("font_size", 34)
	_shuffle_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	_shuffle_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_shuffle_lbl.add_theme_constant_override("outline_size", 6)
	_shuffle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shuffle_lbl.position = Vector2(0, 236)
	_shuffle_lbl.size = Vector2(W, 48)
	_shuffle_lbl.modulate.a = 0.0
	layer.add_child(_shuffle_lbl)


## A small speaker glyph in the top-right that toggles ALL sound (sfx + voice + music).
func _build_mute_button(parent: Node) -> void:
	var btn := Button.new()
	btn.flat = true
	btn.text = "🔊"
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 30)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	btn.position = Vector2(W - 70, 44)
	btn.size = Vector2(52, 52)
	parent.add_child(btn)
	btn.pressed.connect(func() -> void:
		Audio.set_muted(not Audio.muted)
		Music.set_muted(Audio.muted)
		btn.text = "🔇" if Audio.muted else "🔊"
		if not Audio.muted:
			Audio.play("select"))


func _make_stat(parent: Node, caption: String, pos: Vector2, align: int) -> Label:
	var box := VBoxContainer.new()
	box.position = pos
	box.size = Vector2(200, 84)
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	parent.add_child(box)

	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 20)
	cap.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	cap.horizontal_alignment = align
	cap.size = Vector2(200, 22)
	box.add_child(cap)

	var val := Label.new()
	val.text = "0"
	if _display_font:
		val.add_theme_font_override("font", _display_font)
	val.add_theme_font_size_override("font_size", 46)
	val.add_theme_color_override("font_color", Color.WHITE)
	val.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.4))
	val.add_theme_constant_override("outline_size", 4)
	val.horizontal_alignment = align
	val.size = Vector2(200, 56)
	box.add_child(val)
	return val


# ------------------------------------------------------------- HUD sync ---
func _on_score(total: int) -> void:
	_score_lbl.text = str(total)
	_pulse(_score_lbl)


func _on_moves(moves: int) -> void:
	_moves_lbl.text = str(moves)
	_pulse(_moves_lbl)


func _on_shuffled() -> void:
	_shuffle_lbl.text = "NO MOVES — SHUFFLE!"
	_shuffle_lbl.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(0.9)
	t.tween_property(_shuffle_lbl, "modulate:a", 0.0, 0.4)


func _pulse(node: Control, scale: float = 1.2) -> void:
	node.pivot_offset = node.size * 0.5
	var t := create_tween()
	t.tween_property(node, "scale", Vector2.ONE * scale, 0.08)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", Vector2.ONE, 0.14)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
