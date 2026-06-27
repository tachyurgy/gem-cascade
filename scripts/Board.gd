class_name Board
extends Node2D
## The play grid, now LEVEL-DRIVEN. A `Level` supplies the board shape (mask),
## jelly + crate blockers, the win objective, and a move budget. The board handles
## input, swap validation, match detection, mask/crate-aware gravity + refill,
## special "blast" pieces, jelly cracking, crate smashing, objective tracking,
## win/lose — and all the juice (shockwave rings, screen shake, hit-stop).

signal score_changed(total: int)
signal combo_changed(combo: int)
signal moves_changed(moves: int)
signal shuffled()
signal objective_changed(done: int, total: int, label: String)
signal finished(won: bool)

const NUM_TYPES := 6

var level: Level                       # set before add_child()

# Geometry (CELL/GEM_SIZE are computed per-level so any shape fits the screen).
var COLS := 7
var ROWS := 8
var CELL := 96.0
var GEM_SIZE := 84.0

var _gem_shader: Shader = preload("res://shaders/gem.gdshader")
var _ring_tex: Texture2D

var _grid: Array = []          # _grid[col][row] -> Gem or null
var _jelly: Array = []         # _jelly[col][row] -> int hp
var _jelly_node: Array = []    # _jelly[col][row] -> Panel or null
var _crate: Array = []         # _crate[col][row] -> int hp (0 = none)
var _crate_node: Array = []    # node or null
var _origin: Vector2           # world position of cell (0,0) centre
var _selected: Gem = null
var _busy := false
var _ended := false
var _score := 0
var _moves := 25
var _collected := 0            # for COLLECT objective
var _shake_trauma := 0.0
var _base_pos := Vector2.ZERO

# Pointer/swipe tracking.
var _press_gem: Gem = null
var _press_pos: Vector2
var _swiped := false


func _ready() -> void:
	if level == null:
		level = Level.builtins()[0]
	COLS = level.cols
	ROWS = level.rows
	# Fit the board into the play area (below the HUD) at any size.
	CELL = min(96.0, (720.0 - 48.0) / COLS, 900.0 / ROWS)
	GEM_SIZE = CELL * 0.875
	var board_w := COLS * CELL
	var board_h := ROWS * CELL
	var area_top := 300.0
	var area_bottom := 1240.0
	var top_y: float = area_top + max(0.0, (area_bottom - area_top - board_h) * 0.5)
	_origin = Vector2((720.0 - board_w) * 0.5 + CELL * 0.5, top_y + CELL * 0.5)

	_ring_tex = _opt_tex("res://assets/particles/ring.png")
	_alloc_grids()
	_draw_frame()
	_place_blockers()
	_initial_fill()

	_moves = level.moves
	emit_signal("score_changed", _score)
	emit_signal("moves_changed", _moves)
	_emit_objective()

	await get_tree().create_timer(0.7).timeout
	Announcer.say("go", 1.0, 3.0)


func _alloc_grids() -> void:
	_grid = _new_grid(null)
	_jelly = _new_grid(0)
	_jelly_node = _new_grid(null)
	_crate = _new_grid(0)
	_crate_node = _new_grid(null)


func _new_grid(fill) -> Array:
	var g: Array = []
	g.resize(COLS)
	for c in COLS:
		var col: Array = []
		col.resize(ROWS)
		col.fill(fill)
		g[c] = col
	return g


func _opt_tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func _playable(c: int, r: int) -> bool:
	return level.playable(c, r)


## A cell a gem can rest in: playable and not blocked by a crate.
func _open(c: int, r: int) -> bool:
	return _playable(c, r) and _crate[c][r] == 0


# ---------------------------------------------------------------- geometry ---
func _cell_pos(c: int, r: int) -> Vector2:
	return _origin + Vector2(c * CELL, r * CELL)


func _gem_at_point(p: Vector2) -> Gem:
	var local := p - _origin + Vector2(CELL, CELL) * 0.5
	var c := int(floor(local.x / CELL))
	var r := int(floor(local.y / CELL))
	if c < 0 or c >= COLS or r < 0 or r >= ROWS:
		return null
	return _grid[c][r]


func _draw_frame() -> void:
	# A soft rounded panel hugging only the playable cells (per-cell, so odd board
	# shapes still read as a single field).
	var holder := Node2D.new()
	holder.z_index = -6
	add_child(holder)
	for c in COLS:
		for r in ROWS:
			if not _playable(c, r):
				continue
			var p := Panel.new()
			var st := StyleBoxFlat.new()
			st.bg_color = Color(0, 0, 0, 0.22)
			st.set_corner_radius_all(14)
			p.add_theme_stylebox_override("panel", st)
			p.position = _cell_pos(c, r) - Vector2(CELL, CELL) * 0.5 + Vector2(3, 3)
			p.size = Vector2(CELL - 6, CELL - 6)
			p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(p)


# ------------------------------------------------------------------- fill ---
func _make_gem(type: int, c: int, r: int) -> Gem:
	var g := Gem.new()
	g.setup(type, GEM_SIZE, _gem_shader)
	g.col = c
	g.row = r
	g.position = _cell_pos(c, r)
	add_child(g)
	_grid[c][r] = g
	return g


func _initial_fill() -> void:
	for c in COLS:
		for r in ROWS:
			if not _open(c, r):
				continue
			var type := _safe_type(c, r)
			var g := _make_gem(type, c, r)
			var from := _cell_pos(c, r) - Vector2(0, (ROWS + 2) * CELL)
			g.position = from
			g.move_to(_cell_pos(c, r), 0.5, (c + r) * 0.03, Tween.TRANS_BACK)


## Pick a type that doesn't immediately create a 3-in-a-row at fill time.
func _safe_type(c: int, r: int) -> int:
	var tries := 0
	while true:
		var t := randi() % NUM_TYPES
		var bad := false
		if c >= 2 and _grid[c - 1][r] and _grid[c - 2][r] \
				and _grid[c - 1][r].type == t and _grid[c - 2][r].type == t:
			bad = true
		if r >= 2 and _grid[c][r - 1] and _grid[c][r - 2] \
				and _grid[c][r - 1].type == t and _grid[c][r - 2].type == t:
			bad = true
		tries += 1
		if not bad or tries > 20:
			return t
	return 0


# ----------------------------------------------------------------- blockers ---
func _place_blockers() -> void:
	for c in COLS:
		for r in ROWS:
			if not _playable(c, r):
				continue
			var jl: int = int(level.jelly[c][r])
			if jl > 0:
				_jelly[c][r] = jl
				_jelly_node[c][r] = _make_jelly(c, r, jl)
			var cr: int = int(level.crate[c][r])
			if cr > 0:
				_crate[c][r] = cr
				_crate_node[c][r] = _make_crate(c, r, cr)


## Translucent jelly tile that sits UNDER the gems. Thicker jelly = brighter.
func _make_jelly(c: int, r: int, hp: int) -> Panel:
	var p := Panel.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.35, 0.85, 1.0, 0.20 + 0.16 * hp)
	st.set_corner_radius_all(16)
	st.set_border_width_all(2 + hp)
	st.border_color = Color(0.7, 0.95, 1.0, 0.55)
	p.add_theme_stylebox_override("panel", st)
	p.position = _cell_pos(c, r) - Vector2(CELL, CELL) * 0.5 + Vector2(4, 4)
	p.size = Vector2(CELL - 8, CELL - 8)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.z_index = -4
	p.pivot_offset = p.size * 0.5
	add_child(p)
	# A slow shimmer so the glaze feels wet.
	var t := create_tween().set_loops()
	t.tween_property(p, "modulate:a", 0.7, 1.1).set_trans(Tween.TRANS_SINE)
	t.tween_property(p, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE)
	return p


## A static wooden crate blocker. hp 2 looks reinforced.
func _make_crate(c: int, r: int, hp: int) -> Control:
	var p := Panel.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.55, 0.36, 0.18) if hp == 1 else Color(0.45, 0.29, 0.14)
	st.set_corner_radius_all(8)
	st.set_border_width_all(4)
	st.border_color = Color(0.30, 0.18, 0.08)
	p.add_theme_stylebox_override("panel", st)
	p.position = _cell_pos(c, r) - Vector2(CELL, CELL) * 0.5 + Vector2(5, 5)
	p.size = Vector2(CELL - 10, CELL - 10)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.z_index = 2
	p.pivot_offset = p.size * 0.5
	add_child(p)
	var glyph := Label.new()
	glyph.text = "▦" if hp == 1 else "▣"
	glyph.add_theme_font_size_override("font_size", int(CELL * 0.5))
	glyph.add_theme_color_override("font_color", Color(0.86, 0.70, 0.45, 0.9))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.size = p.size
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(glyph)
	return p


# ------------------------------------------------------------------ input ---
func _unhandled_input(event: InputEvent) -> void:
	if _busy or _ended:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_press_gem = _gem_at_point(event.position)
			_press_pos = event.position
			_swiped = false
		else:
			_on_release(event.position)
	elif event is InputEventScreenDrag and _press_gem and not _swiped:
		var delta: Vector2 = event.position - _press_pos
		if delta.length() > CELL * 0.45:
			_swiped = true
			_attempt_dir(_press_gem, delta)


func _on_release(_pos: Vector2) -> void:
	if _swiped:
		_press_gem = null
		return
	var g := _press_gem
	_press_gem = null
	if g == null:
		_clear_selection()
		return
	if _selected == null:
		_select(g)
	elif _selected == g:
		_clear_selection()
	elif _are_adjacent(_selected, g):
		var a := _selected
		_clear_selection()
		_try_swap(a, g)
	else:
		_clear_selection()
		_select(g)


func _attempt_dir(g: Gem, delta: Vector2) -> void:
	var dc := 0
	var dr := 0
	if abs(delta.x) > abs(delta.y):
		dc = 1 if delta.x > 0 else -1
	else:
		dr = 1 if delta.y > 0 else -1
	var nc := g.col + dc
	var nr := g.row + dr
	if nc < 0 or nc >= COLS or nr < 0 or nr >= ROWS or _grid[nc][nr] == null:
		return
	_clear_selection()
	_try_swap(g, _grid[nc][nr])


func _select(g: Gem) -> void:
	_selected = g
	g.set_selected(true)
	Audio.play("select")


func _clear_selection() -> void:
	if _selected:
		_selected.set_selected(false)
	_selected = null


func _are_adjacent(a: Gem, b: Gem) -> bool:
	return abs(a.col - b.col) + abs(a.row - b.row) == 1


# ------------------------------------------------------------------ swap ---
func _swap_in_grid(a: Gem, b: Gem) -> void:
	var ac := a.col
	var ar := a.row
	a.col = b.col
	a.row = b.row
	b.col = ac
	b.row = ar
	_grid[a.col][a.row] = a
	_grid[b.col][b.row] = b


func _try_swap(a: Gem, b: Gem) -> void:
	if a == null or b == null:
		return
	_busy = true
	Audio.play("swap")
	_swap_in_grid(a, b)
	a.move_to(_cell_pos(a.col, a.row), 0.18)
	b.move_to(_cell_pos(b.col, b.row), 0.18)
	await get_tree().create_timer(0.20).timeout

	var matches := _find_matches()
	var has_special := a.special != Gem.NONE or b.special != Gem.NONE
	if matches.is_empty() and not has_special:
		Audio.play("invalid")
		_shake(3.0)
		_swap_in_grid(a, b)
		a.move_to(_cell_pos(a.col, a.row), 0.18)
		b.move_to(_cell_pos(b.col, b.row), 0.18)
		await get_tree().create_timer(0.20).timeout
		_busy = false
		return

	_moves -= 1
	emit_signal("moves_changed", _moves)
	await _resolve(a, b)
	_busy = false
	_check_endgame()


# --------------------------------------------------------------- matching ---
func _find_runs() -> Array:
	var runs: Array = []
	for r in ROWS:
		var c := 0
		while c < COLS:
			var g: Gem = _grid[c][r]
			if g == null:
				c += 1
				continue
			var run := [Vector2i(c, r)]
			var cc := c + 1
			while cc < COLS and _grid[cc][r] and _grid[cc][r].type == g.type:
				run.append(Vector2i(cc, r))
				cc += 1
			if run.size() >= 3:
				runs.append({"cells": run, "len": run.size(), "horiz": true})
			c = cc
	for c in COLS:
		var r := 0
		while r < ROWS:
			var g: Gem = _grid[c][r]
			if g == null:
				r += 1
				continue
			var run := [Vector2i(c, r)]
			var rr := r + 1
			while rr < ROWS and _grid[c][rr] and _grid[c][rr].type == g.type:
				run.append(Vector2i(c, rr))
				rr += 1
			if run.size() >= 3:
				runs.append({"cells": run, "len": run.size(), "horiz": false})
			r = rr
	return runs


func _find_matches() -> Dictionary:
	var cells := {}
	for run in _find_runs():
		for cell in run["cells"]:
			cells[cell] = true
	return cells


# --------------------------------------------------------------- resolve ---
func _resolve(swap_a: Gem, swap_b: Gem) -> void:
	var combo := 0
	while true:
		var runs := _find_runs()
		var matched := {}
		for run in runs:
			for cell in run["cells"]:
				matched[cell] = true
		if matched.is_empty():
			break

		combo += 1
		emit_signal("combo_changed", combo)
		Audio.play("match", pow(2.0, min(combo - 1, 12) / 12.0))
		if combo >= 2:
			Announcer.hype(combo)

		var survivors := {}
		for run in runs:
			if run["len"] < 4:
				continue
			var kind := Gem.STRIPE if run["len"] == 4 else Gem.BOMB
			var cell: Vector2i = _pick_survivor(run, swap_a, swap_b)
			if survivors.has(cell):
				survivors[cell] = max(survivors[cell], kind)
			else:
				survivors[cell] = kind

		_expand_specials(matched)
		for cell in survivors:
			matched.erase(cell)

		var gained := matched.size() * 30 * combo
		_score += gained
		emit_signal("score_changed", _score)
		_spawn_score_popup(matched, gained, combo)

		# Objective + blocker bookkeeping for everything in the clear set.
		_apply_clears(matched)

		var centroid := _centroid(matched)
		var big := matched.size() >= 5 or combo >= 3
		_shockwave(centroid, _combo_color(combo),
			1.2 + min(matched.size(), 12) * 0.18 + combo * 0.25)
		if combo >= 2:
			_shake(2.5 + combo * 1.6)
		if big:
			_hitstop(0.06, 0.07)

		for cell in matched:
			var g: Gem = _grid[cell.x][cell.y]
			if g:
				_grid[cell.x][cell.y] = null
				g.pop()

		if not survivors.is_empty():
			Audio.play("special")
			for cell in survivors:
				var g: Gem = _grid[cell.x][cell.y]
				if g:
					g.set_special(survivors[cell])
					if survivors[cell] == Gem.BOMB:
						Announcer.say("wow", 1.0, 2.0)
					else:
						Announcer.say("sweet", 1.05, 1.0)

		_emit_objective()
		await get_tree().create_timer(0.18).timeout
		await _collapse_and_refill()

	emit_signal("combo_changed", 0)
	if _ended:
		return
	if not _has_possible_move():
		await _reshuffle()


## Crack jelly, count collected colours, and damage adjacent crates for a clear set.
func _apply_clears(matched: Dictionary) -> void:
	for cell in matched:
		var c: int = cell.x
		var r: int = cell.y
		if _jelly[c][r] > 0:
			_jelly[c][r] -= 1
			_update_jelly(c, r)
		var g: Gem = _grid[c][r]
		if g and level.obj_type == Level.OBJ_COLLECT and g.type == level.obj_color:
			_collected += 1
	# Crates take damage from any matched cell orthogonally adjacent to them.
	for c in COLS:
		for r in ROWS:
			if _crate[c][r] <= 0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if matched.has(Vector2i(c + d.x, r + d.y)):
					_damage_crate(c, r)
					break


func _update_jelly(c: int, r: int) -> void:
	var node: Panel = _jelly_node[c][r]
	if node == null:
		return
	if _jelly[c][r] <= 0:
		_jelly_node[c][r] = null
		var t := create_tween()
		t.tween_property(node, "modulate:a", 0.0, 0.2)
		t.parallel().tween_property(node, "scale", Vector2.ONE * 1.4, 0.2)
		t.chain().tween_callback(node.queue_free)
		_shockwave(_cell_pos(c, r), Color("#9be8ff"), 1.0)
	else:
		# Down a layer: dim it and pop.
		var st: StyleBoxFlat = node.get_theme_stylebox("panel")
		st.bg_color.a = 0.20 + 0.16 * _jelly[c][r]
		var t := create_tween()
		t.tween_property(node, "scale", Vector2.ONE * 0.85, 0.08)
		t.tween_property(node, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_ELASTIC)


func _damage_crate(c: int, r: int) -> void:
	_crate[c][r] -= 1
	var node: Control = _crate_node[c][r]
	if _crate[c][r] <= 0:
		_crate_node[c][r] = null
		_shake(4.0)
		Audio.play("land", 0.7, 0.0)
		_shockwave(_cell_pos(c, r), Color("#e7b56a"), 1.4)
		if node:
			var t := create_tween()
			t.tween_property(node, "scale", Vector2.ONE * 1.3, 0.1)
			t.parallel().tween_property(node, "modulate:a", 0.0, 0.2)
			t.parallel().tween_property(node, "rotation", randf_range(-0.5, 0.5), 0.2)
			t.chain().tween_callback(node.queue_free)
	elif node:
		var st: StyleBoxFlat = node.get_theme_stylebox("panel")
		st.bg_color = Color(0.55, 0.36, 0.18)
		var t := create_tween()
		t.tween_property(node, "scale", Vector2.ONE * 0.86, 0.06)
		t.tween_property(node, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_ELASTIC)


func _pick_survivor(run: Dictionary, a: Gem, b: Gem) -> Vector2i:
	for cell in run["cells"]:
		if a and cell == Vector2i(a.col, a.row):
			return cell
		if b and cell == Vector2i(b.col, b.row):
			return cell
	return run["cells"][run["cells"].size() / 2]


func _expand_specials(matched: Dictionary) -> void:
	var queue: Array = []
	for cell in matched.keys():
		var g: Gem = _grid[cell.x][cell.y]
		if g and g.special != Gem.NONE:
			queue.append(cell)
	var done := {}
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		if done.has(cell):
			continue
		done[cell] = true
		var g: Gem = _grid[cell.x][cell.y]
		if g == null:
			continue
		var targets: Array = []
		if g.special == Gem.STRIPE:
			for c in COLS:
				targets.append(Vector2i(c, cell.y))
			for r in ROWS:
				targets.append(Vector2i(cell.x, r))
		elif g.special == Gem.BOMB:
			for c in COLS:
				for r in ROWS:
					if _grid[c][r] and _grid[c][r].type == g.type:
						targets.append(Vector2i(c, r))
		for t in targets:
			if not _open(t.x, t.y):
				continue
			matched[t] = true
			var tg: Gem = _grid[t.x][t.y]
			if tg and tg.special != Gem.NONE and not done.has(t):
				queue.append(t)
	if not done.is_empty():
		_shake(9.0)
		_hitstop(0.05, 0.09)
		Audio.play("blast")
		Announcer.say("kaboom", 1.0, 3.0)
		Announcer.flash(Color("#fff1c4"), 0.28)
		Music.duck(9.0, 0.18)
		for cell in done:
			_shockwave(_cell_pos(cell.x, cell.y), Color("#ffe9a8"), 2.6)


# ----------------------------------------------------- gravity & refill ---
## Mask- and crate-aware gravity. Each column is split into vertical SEGMENTS by
## holes and crates; gems compact down within a segment. A segment that is open to
## the sky (top at row 0) refills by raining gems in; a segment trapped below a
## barrier pops new gems in directly so the board can never soft-lock.
func _collapse_and_refill() -> void:
	var longest := 0.0
	for c in COLS:
		var r := ROWS - 1
		while r >= 0:
			if not _open(c, r):
				r -= 1
				continue
			var bottom := r
			var top := r
			while top - 1 >= 0 and _open(c, top - 1):
				top -= 1
			longest = max(longest, _settle_segment(c, top, bottom))
			r = top - 1
	Audio.play("land", randf_range(0.95, 1.05), -4.0)
	await get_tree().create_timer(longest + 0.05).timeout


func _settle_segment(c: int, top: int, bottom: int) -> float:
	var longest := 0.0
	# Collect surviving gems top->bottom, clearing their slots.
	var gems: Array = []
	for r in range(top, bottom + 1):
		if _grid[c][r]:
			gems.append(_grid[c][r])
			_grid[c][r] = null
	# Drop them to the bottom of the segment.
	var write := bottom
	for i in range(gems.size() - 1, -1, -1):
		var g: Gem = gems[i]
		_grid[c][write] = g
		if g.row != write:
			var dist: int = write - g.row
			g.row = write
			g.move_to(_cell_pos(c, write), 0.16 + dist * 0.035, 0.0, Tween.TRANS_BOUNCE)
			longest = max(longest, 0.16 + dist * 0.035)
		write -= 1
	# Refill the empty top of the segment (write..top).
	var sky := (top == 0)
	var spawn := 0
	for r in range(write, top - 1, -1):
		var type := randi() % NUM_TYPES
		var g := Gem.new()
		g.setup(type, GEM_SIZE, _gem_shader)
		g.col = c
		g.row = r
		_grid[c][r] = g
		add_child(g)
		if sky:
			g.position = _cell_pos(c, -1 - spawn)
			var dur := 0.28 + (r + spawn) * 0.03
			g.move_to(_cell_pos(c, r), dur, spawn * 0.02, Tween.TRANS_BOUNCE)
			longest = max(longest, dur)
		else:
			# Trapped pocket — pop in place from nothing.
			g.position = _cell_pos(c, r)
			g._sprite.scale = Vector2.ZERO
			var base := Vector2.ONE * (GEM_SIZE / 8.0)
			var t := create_tween()
			t.tween_property(g._sprite, "scale", base, 0.22)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			longest = max(longest, 0.22)
		spawn += 1
	return longest


# ----------------------------------------------------------- no-moves AI ---
func _has_possible_move() -> bool:
	for c in COLS:
		for r in ROWS:
			if c + 1 < COLS and _swap_makes_match(c, r, c + 1, r):
				return true
			if r + 1 < ROWS and _swap_makes_match(c, r, c, r + 1):
				return true
	return false


func _swap_makes_match(c1: int, r1: int, c2: int, r2: int) -> bool:
	var a: Gem = _grid[c1][r1]
	var b: Gem = _grid[c2][r2]
	if a == null or b == null or not is_instance_valid(a) or not is_instance_valid(b):
		return false
	_grid[c1][r1] = b
	_grid[c2][r2] = a
	var found := _cell_in_match(c1, r1) or _cell_in_match(c2, r2)
	_grid[c1][r1] = a
	_grid[c2][r2] = b
	return found


func _cell_in_match(c: int, r: int) -> bool:
	var t: int = _grid[c][r].type
	var h := 1
	var k := c - 1
	while k >= 0 and _grid[k][r] and _grid[k][r].type == t:
		h += 1; k -= 1
	k = c + 1
	while k < COLS and _grid[k][r] and _grid[k][r].type == t:
		h += 1; k += 1
	if h >= 3:
		return true
	var v := 1
	k = r - 1
	while k >= 0 and _grid[c][k] and _grid[c][k].type == t:
		v += 1; k -= 1
	k = r + 1
	while k < ROWS and _grid[c][k] and _grid[c][k].type == t:
		v += 1; k += 1
	return v >= 3


func _reshuffle() -> void:
	emit_signal("shuffled")
	Audio.play("shuffle")
	var slots: Array = []
	for c in COLS:
		for r in ROWS:
			if _grid[c][r]:
				slots.append(Vector2i(c, r))
	for _i in 60:
		for cell in slots:
			_grid[cell.x][cell.y].type = randi() % NUM_TYPES
		if _find_matches().is_empty() and _has_possible_move():
			break
	for cell in slots:
		var g: Gem = _grid[cell.x][cell.y]
		g.queue_free()
		_grid[cell.x][cell.y] = null
	await get_tree().process_frame
	for cell in slots:
		var g := _make_gem(randi() % NUM_TYPES, cell.x, cell.y)
		g.position = _cell_pos(cell.x, cell.y) - Vector2(0, (ROWS + 2) * CELL)
		g.move_to(_cell_pos(cell.x, cell.y), 0.5, (cell.x + cell.y) * 0.02, Tween.TRANS_BACK)
	await get_tree().create_timer(0.6).timeout


# --------------------------------------------------------------- objective ---
func _objective_progress() -> Array:
	# Returns [done, total, label].
	match level.obj_type:
		Level.OBJ_JELLY:
			var total := level.jelly_total()
			var rem := 0
			for c in COLS:
				for r in ROWS:
					rem += _jelly[c][r]
			return [total - rem, total, "Clear Jelly"]
		Level.OBJ_CRATES:
			var total := level.crate_total()
			var rem := 0
			for c in COLS:
				for r in ROWS:
					if _crate[c][r] > 0:
						rem += 1
			return [total - rem, total, "Smash Crates"]
		Level.OBJ_COLLECT:
			var cname: String = ["Rose", "Amber", "Jade", "Azure", "Violet", "Diamond"][level.obj_color]
			return [min(_collected, level.obj_count), level.obj_count, "Collect %s" % cname]
		_:
			return [min(_score, level.obj_count), level.obj_count, "Score"]


func _emit_objective() -> void:
	var p := _objective_progress()
	emit_signal("objective_changed", p[0], p[1], p[2])


func _objective_met() -> bool:
	var p := _objective_progress()
	return p[0] >= p[1]


func _check_endgame() -> void:
	if _ended:
		return
	if _objective_met():
		_ended = true
		emit_signal("finished", true)
	elif _moves <= 0:
		_ended = true
		emit_signal("finished", false)


# ------------------------------------------------------------------- juice ---
func _shake(amount: float) -> void:
	_shake_trauma = min(_shake_trauma + amount, 16.0)


func _process(delta: float) -> void:
	if _shake_trauma > 0.01:
		var s := _shake_trauma
		position = _base_pos + Vector2(randf_range(-s, s), randf_range(-s, s))
		_shake_trauma = max(0.0, _shake_trauma - delta * 42.0)
	elif position != _base_pos:
		position = _base_pos


func _hitstop(scale: float, dur: float) -> void:
	Engine.time_scale = scale
	await get_tree().create_timer(dur, true, false, true).timeout
	Engine.time_scale = 1.0


func _centroid(cells: Dictionary) -> Vector2:
	if cells.is_empty():
		return _cell_pos(COLS / 2, ROWS / 2)
	var avg := Vector2.ZERO
	for cell in cells:
		avg += _cell_pos(cell.x, cell.y)
	return avg / cells.size()


func _combo_color(combo: int) -> Color:
	var palette := [
		Color("#ffe66d"), Color("#ffd23f"), Color("#ff9f43"),
		Color("#ff6b9d"), Color("#54e1ff"), Color("#c08bff"),
	]
	return palette[clampi(combo - 1, 0, palette.size() - 1)]


func _shockwave(world_pos: Vector2, color: Color, scale_to: float) -> void:
	if _ring_tex == null:
		return
	var s := Sprite2D.new()
	s.texture = _ring_tex
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = cm
	s.position = world_pos
	s.modulate = Color(color.r, color.g, color.b, 0.9)
	s.scale = Vector2.ONE * 0.12
	s.z_index = 40
	add_child(s)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(s, "scale", Vector2.ONE * scale_to, 0.45)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(s, "modulate:a", 0.0, 0.45)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.chain().tween_callback(s.queue_free)


func _spawn_score_popup(cells: Dictionary, amount: int, combo: int) -> void:
	if cells.is_empty():
		return
	var avg := _centroid(cells)
	var lbl := Label.new()
	lbl.text = ("+%d" % amount) if combo < 2 else ("+%d  x%d" % [amount, combo])
	lbl.add_theme_font_size_override("font_size", 30 + combo * 6)
	lbl.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.position = avg + Vector2(-40, -10)
	lbl.z_index = 50
	add_child(lbl)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "position", lbl.position + Vector2(0, -70), 0.7)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "modulate:a", 0.0, 0.7).set_delay(0.25)
	t.chain().tween_callback(lbl.queue_free)
