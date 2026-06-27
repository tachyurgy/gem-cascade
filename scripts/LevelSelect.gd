class_name LevelSelect
extends Node2D
## The home screen: the built-in campaign plus any levels the player authored in
## the editor, each playable, each editable. "New Level" opens a blank editor.

signal play(level: Level)
signal edit(level: Level)

const BG_SHADER: Shader = preload("res://shaders/background.gdshader")
const TITLE_FONT := "res://assets/fonts/LuckiestGuy.ttf"
const DISPLAY_FONT := "res://assets/fonts/Bungee.ttf"
const USER_DIR := "user://levels"

const W := 720.0
const H := 1280.0

var _title_font: Font
var _display_font: Font


func _ready() -> void:
	_title_font = _opt_font(TITLE_FONT)
	_display_font = _opt_font(DISPLAY_FONT)
	_build_bg()
	_build_ui()


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


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var title := Label.new()
	title.text = "GEM CASCADE"
	if _title_font:
		title.add_theme_font_override("font", _title_font)
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	title.add_theme_color_override("font_outline_color", Color(0.62, 0.18, 0.55, 0.9))
	title.add_theme_constant_override("outline_size", 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 56)
	title.size = Vector2(W, 90)
	layer.add_child(title)

	var sub := Label.new()
	sub.text = "select a level"
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(0, 150)
	sub.size = Vector2(W, 30)
	layer.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(60, 210)
	scroll.size = Vector2(W - 120, H - 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layer.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(W - 120, 0)
	list.add_theme_constant_override("separation", 16)
	scroll.add_child(list)

	for lv in Level.builtins():
		list.add_child(_level_card(lv, false))
	for lv in _user_levels():
		list.add_child(_level_card(lv, true))

	# New-level button pinned at the bottom.
	var newbtn := Button.new()
	newbtn.text = "+  CREATE NEW LEVEL"
	newbtn.focus_mode = Control.FOCUS_NONE
	if _display_font:
		newbtn.add_theme_font_override("font", _display_font)
	newbtn.add_theme_font_size_override("font_size", 26)
	newbtn.add_theme_color_override("font_color", Color(0.06, 0.06, 0.12))
	newbtn.position = Vector2(60, H - 96)
	newbtn.size = Vector2(W - 120, 60)
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#ffd23f")
	st.set_corner_radius_all(16)
	newbtn.add_theme_stylebox_override("normal", st)
	newbtn.add_theme_stylebox_override("hover", st)
	newbtn.add_theme_stylebox_override("pressed", st)
	layer.add_child(newbtn)
	newbtn.pressed.connect(func() -> void: emit_signal("edit", null))


func _level_card(lv: Level, is_user: bool) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 92)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 0.07)
	st.set_corner_radius_all(16)
	st.set_border_width_all(1)
	st.border_color = Color(1, 1, 1, 0.12)
	st.content_margin_left = 18
	st.content_margin_right = 14
	st.content_margin_top = 12
	st.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", st)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var nm := Label.new()
	nm.text = lv.name
	if _display_font:
		nm.add_theme_font_override("font", _display_font)
	nm.add_theme_font_size_override("font_size", 28)
	nm.add_theme_color_override("font_color", Color.WHITE)
	info.add_child(nm)

	var meta := Label.new()
	meta.text = "%s   ·   %d moves" % [_obj_summary(lv), lv.moves]
	meta.add_theme_font_size_override("font_size", 18)
	meta.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	info.add_child(meta)

	row.add_child(_mini_button("EDIT", Color(1, 1, 1, 0.18), Color.WHITE,
		func() -> void: emit_signal("edit", lv)))
	row.add_child(_mini_button("PLAY", Color("#54e1ff"), Color(0.06, 0.06, 0.12),
		func() -> void: emit_signal("play", lv)))
	return card


func _mini_button(text: String, bg: Color, fg: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(86, 56)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", fg)
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.set_corner_radius_all(12)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	b.add_theme_stylebox_override("pressed", st)
	b.pressed.connect(cb)
	return b


func _obj_summary(lv: Level) -> String:
	match lv.obj_type:
		Level.OBJ_JELLY:
			return "Clear all jelly"
		Level.OBJ_CRATES:
			return "Smash all crates"
		Level.OBJ_COLLECT:
			var cname: String = ["rose", "amber", "jade", "azure", "violet", "diamond"][lv.obj_color]
			return "Collect %d %s" % [lv.obj_count, cname]
		_:
			return "Score %d" % lv.obj_count


func _user_levels() -> Array:
	var out: Array = []
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var d := DirAccess.open(USER_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".json"):
			var lv := Level.load_from(USER_DIR + "/" + f)
			if lv:
				out.append(lv)
	return out
