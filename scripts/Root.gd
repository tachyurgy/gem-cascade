extends Node
## App shell. Switches between the three screens — level SELECT, PLAY, and the
## level EDITOR — and wires their signals. One screen is alive at a time.

var _current: Node


func _ready() -> void:
	_show_menu()


func _swap(node: Node) -> void:
	if _current and is_instance_valid(_current):
		_current.queue_free()
	_current = node
	add_child(node)


# ----------------------------------------------------------------- menu ---
func _show_menu() -> void:
	var m := LevelSelect.new()
	m.play.connect(_play)
	m.edit.connect(_edit)
	_swap(m)


# ----------------------------------------------------------------- play ---
func _play(level: Level) -> void:
	_start_game(level, _show_menu)


## Play a level, but route "menu"/"retry" back to the editor (used by Playtest).
func _play_from_editor(level: Level) -> void:
	_start_game(level, func() -> void: _edit(level))


func _start_game(level: Level, on_exit: Callable) -> void:
	var g := GameScene.new()
	g.level = level
	g.request_menu.connect(on_exit)
	g.request_retry.connect(func() -> void: _start_game(level, on_exit))
	_swap(g)


# --------------------------------------------------------------- editor ---
func _edit(level: Level) -> void:
	var ed := LevelEditor.new()
	if level != null:
		ed.level = level
	ed.request_menu.connect(_show_menu)
	ed.playtest.connect(_play_from_editor)
	_swap(ed)
