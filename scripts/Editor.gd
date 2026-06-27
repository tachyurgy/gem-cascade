class_name LevelEditor
extends Node2D
## The level editor — the reason the game's design presupposes one. You paint the
## board SHAPE, drop JELLY and CRATE blockers, choose the OBJECTIVE, and tune the
## MOVE budget, then SAVE the level or PLAYTEST it instantly. Levels are saved as
## JSON under user://levels and show up on the home screen alongside the campaign.

signal request_menu()
signal playtest(level: Level)

const BG_SHADER: Shader = preload("res://shaders/background.gdshader")
const DISPLAY_FONT := "res://assets/fonts/Bungee.ttf"
const TITLE_FONT := "res://assets/fonts/LuckiestGuy.ttf"
const USER_DIR := "user://levels"

const W := 720.0
const H := 1280.0

# Brushes.
const B_WALL := 0
const B_JELLY := 1
const B_CRATE := 2
const B_CLEAR := 3
const BRUSH_NAMES := ["SHAPE", "JELLY", "CRATE", "ERASE"]
const BRUSH_COLORS := [Color("#9aa7ff"), Color("#54e1ff"), Color("#d98b4a"), Color("#ff6b9d")]

const COLOR_NAMES := ["Rose", "Amber", "Jade", "Azure", "Violet", "Diamond"]
const COLOR_SWATCH := ["#ff5c7a", "#ffb020", "#36e07a", "#38bdf8", "#a78bfa", "#eef2ff"]

var level: Level

var _display_font: Font
var _title_font: Font
var _brush := B_WALL
var _brush_btns: Array = []
var _cell_btns: Array = []     # [c][r] -> Button
var _grid_holder: Control
var _moves_lbl: Label
var _goal_lbl: Label
var _target_lbl: Label
var _toast: Label
var _ui: CanvasLayer


func _ready() -> void:
	if level == null:
		level = Level.blank(7, 8)
		level.name = "My Level"
		level.id = "user_%d" % int(Time.get_unix_time_from_system())
	_display_font = _opt_font(DISPLAY_FONT)
	_title_font = _opt_font(TITLE_FONT)
	_build_bg()
	_build_ui()
	_rebuild_grid()
	_refresh_controls()
	_set_brush(_brush)


func _opt_font(p: String) -> Font:
	return load(p) if ResourceLoader.exists(p) else null


func _build_bg() -> void:
	var bg := ColorRect.new()
	bg.size = Vector2(W, H)
	bg.material = ShaderMaterial.new()
	bg.material.shader = BG_SHADER
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	layer.layer = -10
	layer.add_child(bg)
	add_child(layer)


# --------------------------------------------------------------------- UI ---
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	_ui = layer
	add_child(layer)

	var title := Label.new()
	title.text = "LEVEL EDITOR"
	if _title_font:
		title.add_theme_font_override("font", _title_font)
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
	title.add_theme_color_override("font_outline_color", Color(0.62, 0.18, 0.55, 0.9))
	title.add_theme_constant_override("outline_size", 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 24)
	title.size = Vector2(W, 56)
	layer.add_child(title)

	var back := Button.new()
	back.flat = true
	back.text = "‹"
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", 44)
	back.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	back.position = Vector2(14, 24)
	back.size = Vector2(52, 56)
	layer.add_child(back)
	back.pressed.connect(func() -> void: emit_signal("request_menu"))

	# Board-size steppers + brush palette.
	var size_row := _row(Vector2(40, 92), W - 80, 40)
	layer.add_child(size_row)
	size_row.add_child(_stepper("COLS", func(d): _resize_board(d, 0)))
	size_row.add_child(_stepper("ROWS", func(d): _resize_board(0, d)))

	var brush_row := _row(Vector2(40, 142), W - 80, 52)
	brush_row.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(brush_row)
	_brush_btns.clear()
	for i in BRUSH_NAMES.size():
		var b := _palette_button(i)
		_brush_btns.append(b)
		brush_row.add_child(b)

	# Interactive grid lives in this region.
	_grid_holder = Control.new()
	_grid_holder.position = Vector2(60, 210)
	_grid_holder.size = Vector2(W - 120, 540)
	layer.add_child(_grid_holder)

	# Objective + moves controls.
	var y := 770.0
	_goal_lbl = _control_row(layer, Vector2(40, y), "GOAL",
		func(): _cycle_goal(-1), func(): _cycle_goal(1))
	# For a COLLECT goal, tapping the goal value cycles which colour to collect.
	_goal_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	_goal_lbl.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and level.obj_type == Level.OBJ_COLLECT:
			level.obj_color = (level.obj_color + 1) % 6
			Audio.play("select")
			_refresh_controls())
	_target_lbl = _control_row(layer, Vector2(40, y + 58), "TARGET",
		func(): _bump_target(-1), func(): _bump_target(1))
	_moves_lbl = _control_row(layer, Vector2(40, y + 116), "MOVES",
		func(): _bump_moves(-1), func(): _bump_moves(1))

	# Save / Playtest.
	var act := _row(Vector2(40, y + 186), W - 80, 64)
	act.add_theme_constant_override("separation", 16)
	layer.add_child(act)
	act.add_child(_big_button("SAVE", Color("#ffd23f"), _save))
	act.add_child(_big_button("PLAYTEST", Color("#54e1ff"),
		func(): emit_signal("playtest", level)))

	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 24)
	_toast.add_theme_color_override("font_color", Color("#9be8a0"))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position = Vector2(0, H - 40)
	_toast.size = Vector2(W, 30)
	_toast.modulate.a = 0.0
	layer.add_child(_toast)


func _row(pos: Vector2, w: float, h: float) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.position = pos
	r.size = Vector2(w, h)
	r.add_theme_constant_override("separation", 10)
	return r


func _stepper(caption: String, cb: Callable) -> Control:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	box.add_child(_tiny_button("-", func(): cb.call(-1)))
	var l := Label.new()
	l.text = caption
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(64, 40)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(l)
	box.add_child(_tiny_button("+", func(): cb.call(1)))
	return box


func _palette_button(i: int) -> Button:
	var b := Button.new()
	b.text = BRUSH_NAMES[i]
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(140, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(func() -> void: _set_brush(i))
	return b


func _control_row(parent: Node, pos: Vector2, caption: String, dec: Callable, inc: Callable) -> Label:
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 20)
	cap.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	cap.position = pos
	cap.size = Vector2(120, 44)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(cap)

	var decb := _tiny_button("-", dec)
	decb.position = Vector2(pos.x + 150, pos.y)
	parent.add_child(decb)

	var val := Label.new()
	if _display_font:
		val.add_theme_font_override("font", _display_font)
	val.add_theme_font_size_override("font_size", 24)
	val.add_theme_color_override("font_color", Color.WHITE)
	val.position = Vector2(pos.x + 200, pos.y)
	val.size = Vector2(W - 80 - 200 - 60, 44)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(val)

	var incb := _tiny_button("+", inc)
	incb.position = Vector2(pos.x + W - 80 - 44, pos.y)
	parent.add_child(incb)
	return val


func _tiny_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(44, 44)
	b.size = Vector2(44, 44)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color.WHITE)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 0.16)
	st.set_corner_radius_all(10)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	b.add_theme_stylebox_override("pressed", st)
	b.pressed.connect(cb)
	return b


func _big_button(text: String, color: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 60)
	if _display_font:
		b.add_theme_font_override("font", _display_font)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", Color(0.06, 0.06, 0.12))
	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.set_corner_radius_all(16)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	b.add_theme_stylebox_override("pressed", st)
	b.pressed.connect(cb)
	return b


# ----------------------------------------------------------------- grid ---
func _rebuild_grid() -> void:
	for ch in _grid_holder.get_children():
		ch.queue_free()
	_cell_btns = []
	_cell_btns.resize(level.cols)
	var region := _grid_holder.size
	var cell: float = min(region.x / level.cols, region.y / level.rows)
	var gw := cell * level.cols
	var gh := cell * level.rows
	var ox := (region.x - gw) * 0.5
	var oy := (region.y - gh) * 0.5
	for c in level.cols:
		_cell_btns[c] = []
		_cell_btns[c].resize(level.rows)
		for r in level.rows:
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.position = Vector2(ox + c * cell + 2, oy + r * cell + 2)
			b.size = Vector2(cell - 4, cell - 4)
			b.add_theme_font_size_override("font_size", int(cell * 0.42))
			_grid_holder.add_child(b)
			_cell_btns[c][r] = b
			var cc := c
			var rr := r
			b.pressed.connect(func() -> void: _paint(cc, rr))
			_style_cell(c, r)


func _style_cell(c: int, r: int) -> void:
	var b: Button = _cell_btns[c][r]
	var st := StyleBoxFlat.new()
	st.set_corner_radius_all(8)
	b.text = ""
	if not level.mask[c][r]:
		st.bg_color = Color(1, 1, 1, 0.04)
		st.set_border_width_all(1)
		st.border_color = Color(1, 1, 1, 0.10)
	elif int(level.crate[c][r]) > 0:
		st.bg_color = Color(0.55, 0.36, 0.18) if level.crate[c][r] == 1 else Color(0.45, 0.29, 0.14)
		b.text = "▦" if level.crate[c][r] == 1 else "▣"
		b.add_theme_color_override("font_color", Color(0.9, 0.74, 0.48))
	elif int(level.jelly[c][r]) > 0:
		st.bg_color = Color(0.35, 0.85, 1.0, 0.30 + 0.2 * level.jelly[c][r])
		st.set_border_width_all(2)
		st.border_color = Color(0.7, 0.95, 1.0, 0.7)
		b.text = str(level.jelly[c][r])
		b.add_theme_color_override("font_color", Color(0.95, 1, 1))
	else:
		st.bg_color = Color(1, 1, 1, 0.13)
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, st)


func _paint(c: int, r: int) -> void:
	match _brush:
		B_WALL:
			level.mask[c][r] = not level.mask[c][r]
			if not level.mask[c][r]:
				level.jelly[c][r] = 0
				level.crate[c][r] = 0
		B_JELLY:
			level.mask[c][r] = true
			level.crate[c][r] = 0
			level.jelly[c][r] = (int(level.jelly[c][r]) + 1) % 3
		B_CRATE:
			level.mask[c][r] = true
			level.jelly[c][r] = 0
			level.crate[c][r] = (int(level.crate[c][r]) + 1) % 3
		B_CLEAR:
			level.jelly[c][r] = 0
			level.crate[c][r] = 0
	Audio.play("select")
	_style_cell(c, r)
	if level.obj_type == Level.OBJ_JELLY or level.obj_type == Level.OBJ_CRATES:
		_refresh_controls()


# --------------------------------------------------------------- controls ---
func _set_brush(i: int) -> void:
	_brush = i
	Audio.play("select")
	for j in _brush_btns.size():
		var b: Button = _brush_btns[j]
		var st := StyleBoxFlat.new()
		st.set_corner_radius_all(12)
		if j == i:
			st.bg_color = BRUSH_COLORS[j]
			b.add_theme_color_override("font_color", Color(0.06, 0.06, 0.12))
		else:
			st.bg_color = Color(1, 1, 1, 0.10)
			b.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, st)


func _resize_board(dc: int, dr: int) -> void:
	level.cols = clampi(level.cols + dc, 4, 8)
	level.rows = clampi(level.rows + dr, 5, 10)
	level.ensure_grids()
	# A freshly grown column/row defaults to "wall on" so it's instantly usable.
	for c in level.cols:
		for r in level.rows:
			if dc > 0 and c == level.cols - 1:
				level.mask[c][r] = true
			if dr > 0 and r == level.rows - 1:
				level.mask[c][r] = true
	Audio.play("select")
	_rebuild_grid()
	_refresh_controls()


func _cycle_goal(d: int) -> void:
	level.obj_type = (level.obj_type + d + 4) % 4
	# Sensible defaults per goal type.
	match level.obj_type:
		Level.OBJ_SCORE:
			level.obj_count = 2000
		Level.OBJ_COLLECT:
			level.obj_count = 25
		_:
			pass
	Audio.play("select")
	_refresh_controls()


func _bump_target(d: int) -> void:
	match level.obj_type:
		Level.OBJ_SCORE:
			level.obj_count = max(500, level.obj_count + d * 250)
		Level.OBJ_COLLECT:
			# The +/- on a COLLECT target also lets you flip colour with a long step.
			level.obj_count = clampi(level.obj_count + d * 5, 5, 80)
		_:
			# Jelly/Crates targets are derived from the board; cycle the colour idea is N/A.
			pass
	Audio.play("select")
	_refresh_controls()


func _bump_moves(d: int) -> void:
	level.moves = clampi(level.moves + d, 5, 60)
	Audio.play("select")
	_refresh_controls()


## For COLLECT, the GOAL row's value doubles as a colour picker via a tap on the swatch.
func _refresh_controls() -> void:
	_moves_lbl.text = str(level.moves)
	match level.obj_type:
		Level.OBJ_JELLY:
			_goal_lbl.text = "Clear Jelly"
			_target_lbl.text = "%d tiles" % level.jelly_total()
		Level.OBJ_CRATES:
			_goal_lbl.text = "Smash Crates"
			_target_lbl.text = "%d crates" % level.crate_total()
		Level.OBJ_COLLECT:
			_goal_lbl.text = "Collect %s" % COLOR_NAMES[level.obj_color]
			_target_lbl.text = "%d  (tap goal to recolour)" % level.obj_count
		_:
			_goal_lbl.text = "Score"
			_target_lbl.text = str(level.obj_count)


# ----------------------------------------------------------------- save ---
func _save() -> void:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	# Guard against impossible levels.
	if level.obj_type == Level.OBJ_JELLY and level.jelly_total() == 0:
		_show_toast("Add jelly first (JELLY brush)", Color("#ff8a8a"))
		return
	if level.obj_type == Level.OBJ_CRATES and level.crate_total() == 0:
		_show_toast("Add crates first (CRATE brush)", Color("#ff8a8a"))
		return
	var path := "%s/%s.json" % [USER_DIR, level.id]
	var err := level.save_to(path)
	if err == OK:
		_show_toast("Saved ✓  Find it on the home screen", Color("#9be8a0"))
		Audio.play("special")
	else:
		_show_toast("Save failed (%d)" % err, Color("#ff8a8a"))


func _show_toast(text: String, color: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(1.6)
	t.tween_property(_toast, "modulate:a", 0.0, 0.5)


# Tapping the GOAL value cycles the COLLECT colour (wired via _goal_lbl gui_input).
func _unhandled_input(_e: InputEvent) -> void:
	pass
