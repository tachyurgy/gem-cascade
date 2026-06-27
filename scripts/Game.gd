class_name GameScene
extends Node2D
## In-play scene: animated background, HUD (objective + progress, score, moves),
## the Board for a given Level, and a win/lose result overlay. The big combo
## callouts are owned by the `Announcer` autoload, so this HUD stays readable.

signal request_menu()
signal request_retry()

const BG_SHADER: Shader = preload("res://shaders/background.gdshader")
const DISPLAY_FONT := "res://assets/fonts/Bungee.ttf"
const TITLE_FONT := "res://assets/fonts/LuckiestGuy.ttf"

var level: Level                      # set before add_child()

var _board: Board
var _score_lbl: Label
var _moves_lbl: Label
var _obj_lbl: Label
var _obj_bar: ProgressBar
var _shuffle_lbl: Label
var _display_font: Font
var _title_font: Font
var _hud: CanvasLayer

const W := 720.0
const H := 1280.0


func _ready() -> void:
	randomize()
	if level == null:
		level = Level.builtins()[0]
	_display_font = _opt_font(DISPLAY_FONT)
	_title_font = _opt_font(TITLE_FONT)
	_build_background()
	_build_hud()
	_board = Board.new()
	_board.level = level
	_board.score_changed.connect(_on_score)
	_board.moves_changed.connect(_on_moves)
	_board.shuffled.connect(_on_shuffled)
	_board.objective_changed.connect(_on_objective)
	_board.finished.connect(_on_finished)
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
	_hud = layer
	add_child(layer)

	var title := Label.new()
	title.text = level.name.to_upper()
	if _title_font:
		title.add_theme_font_override("font", _title_font)
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	title.add_theme_color_override("font_outline_color", Color(0.62, 0.18, 0.55, 0.9))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_shadow_color", Color(0.2, 0.05, 0.3, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 5)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 26)
	title.size = Vector2(W, 72)
	layer.add_child(title)

	# A small back arrow to leave for the menu.
	var back := Button.new()
	back.flat = true
	back.text = "‹"
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", 44)
	back.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	back.position = Vector2(14, 30)
	back.size = Vector2(52, 56)
	layer.add_child(back)
	back.pressed.connect(func() -> void: emit_signal("request_menu"))

	_build_mute_button(layer)

	# Objective banner — what you must do + a progress bar.
	_obj_lbl = Label.new()
	_obj_lbl.add_theme_font_size_override("font_size", 24)
	_obj_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_obj_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_obj_lbl.position = Vector2(0, 110)
	_obj_lbl.size = Vector2(W, 30)
	layer.add_child(_obj_lbl)

	_obj_bar = ProgressBar.new()
	_obj_bar.show_percentage = false
	_obj_bar.min_value = 0
	_obj_bar.max_value = 1
	_obj_bar.value = 0
	_obj_bar.position = Vector2(W * 0.5 - 170, 146)
	_obj_bar.size = Vector2(340, 14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#54e1ff")
	fill.set_corner_radius_all(7)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	bg.set_corner_radius_all(7)
	_obj_bar.add_theme_stylebox_override("fill", fill)
	_obj_bar.add_theme_stylebox_override("background", bg)
	layer.add_child(_obj_bar)

	_score_lbl = _make_stat(layer, "SCORE", Vector2(40, 186), HORIZONTAL_ALIGNMENT_LEFT)
	_moves_lbl = _make_stat(layer, "MOVES", Vector2(W - 240, 186), HORIZONTAL_ALIGNMENT_RIGHT)

	_shuffle_lbl = Label.new()
	if _display_font:
		_shuffle_lbl.add_theme_font_override("font", _display_font)
	_shuffle_lbl.add_theme_font_size_override("font_size", 30)
	_shuffle_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	_shuffle_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_shuffle_lbl.add_theme_constant_override("outline_size", 6)
	_shuffle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shuffle_lbl.position = Vector2(0, 250)
	_shuffle_lbl.size = Vector2(W, 48)
	_shuffle_lbl.modulate.a = 0.0
	layer.add_child(_shuffle_lbl)


func _build_mute_button(parent: Node) -> void:
	var btn := Button.new()
	btn.flat = true
	btn.text = "🔊"
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 30)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	btn.position = Vector2(W - 70, 40)
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
	if moves <= 5:
		_moves_lbl.add_theme_color_override("font_color", Color("#ff6b6b"))


func _on_objective(done: int, total: int, lbl: String) -> void:
	_obj_lbl.text = "%s   %d / %d" % [lbl, done, total]
	_obj_bar.max_value = max(1, total)
	var t := create_tween()
	t.tween_property(_obj_bar, "value", float(done), 0.3).set_trans(Tween.TRANS_QUAD)


func _on_shuffled() -> void:
	_shuffle_lbl.text = "NO MOVES — SHUFFLE!"
	_shuffle_lbl.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(0.9)
	t.tween_property(_shuffle_lbl, "modulate:a", 0.0, 0.4)


func _on_finished(won: bool) -> void:
	await get_tree().create_timer(0.5).timeout
	_show_result(won)


func _pulse(node: Control, scale: float = 1.2) -> void:
	node.pivot_offset = node.size * 0.5
	var t := create_tween()
	t.tween_property(node, "scale", Vector2.ONE * scale, 0.08)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", Vector2.ONE, 0.14)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# --------------------------------------------------------------- result ---
func _show_result(won: bool) -> void:
	if won:
		Announcer.bigtext("LEVEL CLEAR!", Color("#ffe66d"), 120, 3)
		Announcer.say("cascade", 1.0, 3.0)
		Announcer.flash(Color("#ffe9a8"), 0.4)
	else:
		Announcer.bigtext("OUT OF MOVES", Color("#ff8a8a"), 96, 1)

	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.08, 0.0)
	dim.size = Vector2(W, H)
	layer.add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.72, 0.4)

	var panel := VBoxContainer.new()
	panel.position = Vector2(W * 0.5 - 200, H * 0.5 - 130)
	panel.size = Vector2(400, 260)
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_theme_constant_override("separation", 22)
	layer.add_child(panel)

	var head := Label.new()
	head.text = "LEVEL CLEAR" if won else "OUT OF MOVES"
	if _title_font:
		head.add_theme_font_override("font", _title_font)
	head.add_theme_font_size_override("font_size", 56)
	head.add_theme_color_override("font_color", Color("#ffe66d") if won else Color("#ff8a8a"))
	head.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	head.add_theme_constant_override("outline_size", 8)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.size = Vector2(400, 70)
	panel.add_child(head)

	var sub := Label.new()
	sub.text = "Score  %s" % _board._score
	if _display_font:
		sub.add_theme_font_override("font", _display_font)
	sub.add_theme_font_size_override("font_size", 30)
	sub.add_theme_color_override("font_color", Color.WHITE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size = Vector2(400, 40)
	panel.add_child(sub)

	panel.add_child(_result_button("RETRY", Color("#54e1ff"),
		func() -> void: emit_signal("request_retry")))
	panel.add_child(_result_button("MENU", Color(1, 1, 1, 0.8),
		func() -> void: emit_signal("request_menu")))


func _result_button(text: String, color: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(260, 56)
	if _display_font:
		b.add_theme_font_override("font", _display_font)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color(0.06, 0.06, 0.12))
	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.set_corner_radius_all(14)
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	b.add_theme_stylebox_override("pressed", st)
	b.pressed.connect(cb)
	return b
