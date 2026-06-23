extends Node2D
## Root scene: builds the animated background, the HUD (score / moves / combo /
## title) and the Board, then keeps the HUD in sync with board signals.

const BG_SHADER: Shader = preload("res://shaders/background.gdshader")

var _board: Board
var _score_lbl: Label
var _moves_lbl: Label
var _combo_lbl: Label

const W := 720.0
const H := 1280.0


func _ready() -> void:
	randomize()
	_build_background()
	_build_hud()
	_board = Board.new()
	# Connect before add_child: add_child runs Board._ready(), which emits the
	# initial score/moves — we must already be listening.
	_board.score_changed.connect(_on_score)
	_board.moves_changed.connect(_on_moves)
	_board.combo_changed.connect(_on_combo)
	_board.shuffled.connect(_on_shuffled)
	add_child(_board)


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
	title.text = "GEM  CASCADE"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	title.add_theme_color_override("font_outline_color", Color(0.5, 0.2, 0.6, 0.7))
	title.add_theme_constant_override("outline_size", 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 40)
	title.size = Vector2(W, 64)
	layer.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "swipe or tap to match three"
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.position = Vector2(0, 104)
	subtitle.size = Vector2(W, 30)
	layer.add_child(subtitle)

	_score_lbl = _make_stat(layer, "SCORE", Vector2(40, 168), HORIZONTAL_ALIGNMENT_LEFT)
	_moves_lbl = _make_stat(layer, "MOVES", Vector2(W - 240, 168), HORIZONTAL_ALIGNMENT_RIGHT)
	_combo_lbl = Label.new()
	_combo_lbl.add_theme_font_size_override("font_size", 40)
	_combo_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	_combo_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_combo_lbl.add_theme_constant_override("outline_size", 6)
	_combo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_lbl.position = Vector2(0, 220)
	_combo_lbl.size = Vector2(W, 48)
	_combo_lbl.modulate.a = 0.0
	layer.add_child(_combo_lbl)


func _make_stat(parent: Node, caption: String, pos: Vector2, align: int) -> Label:
	var box := VBoxContainer.new()
	box.position = pos
	box.size = Vector2(200, 80)
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	parent.add_child(box)

	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 20)
	cap.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	cap.horizontal_alignment = align
	cap.size = Vector2(200, 22)
	box.add_child(cap)

	var val := Label.new()
	val.text = "0"
	val.add_theme_font_size_override("font_size", 44)
	val.add_theme_color_override("font_color", Color.WHITE)
	val.horizontal_alignment = align
	val.size = Vector2(200, 50)
	box.add_child(val)
	return val


# ------------------------------------------------------------- HUD sync ---
func _on_score(total: int) -> void:
	_score_lbl.text = str(total)
	_pulse(_score_lbl)


func _on_moves(moves: int) -> void:
	_moves_lbl.text = str(moves)
	_pulse(_moves_lbl)


func _on_combo(combo: int) -> void:
	if combo >= 2:
		_combo_lbl.text = "COMBO  x%d!" % combo
		_combo_lbl.modulate.a = 1.0
		_pulse(_combo_lbl, 1.4)
		var t := create_tween()
		t.tween_interval(0.6)
		t.tween_property(_combo_lbl, "modulate:a", 0.0, 0.4)
	# combo == 0 just lets the fade finish.


func _on_shuffled() -> void:
	_combo_lbl.text = "NO MOVES — SHUFFLE!"
	_combo_lbl.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(0.8)
	t.tween_property(_combo_lbl, "modulate:a", 0.0, 0.4)


func _pulse(node: Control, scale: float = 1.2) -> void:
	node.pivot_offset = node.size * 0.5
	var t := create_tween()
	t.tween_property(node, "scale", Vector2.ONE * scale, 0.08)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", Vector2.ONE, 0.14)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
