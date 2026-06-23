class_name Board
extends Node2D
## The play grid: input, swap validation, match detection, cascading gravity,
## refills, special "blast" pieces, and all the timing that makes it feel juicy.

signal score_changed(total: int)
signal combo_changed(combo: int)
signal moves_changed(moves: int)
signal shuffled()

const COLS := 7
const ROWS := 8
const CELL := 96.0
const GEM_SIZE := 84.0
const NUM_TYPES := 6
const START_MOVES := 30

var _gem_shader: Shader = preload("res://shaders/gem.gdshader")

var _grid: Array = []          # _grid[col][row] -> Gem or null
var _origin: Vector2           # world position of cell (0,0) centre
var _selected: Gem = null
var _busy := false
var _score := 0
var _moves := START_MOVES

# Pointer/swipe tracking.
var _press_gem: Gem = null
var _press_pos: Vector2
var _swiped := false


func _ready() -> void:
	var board_w := COLS * CELL
	_origin = Vector2((720.0 - board_w) * 0.5 + CELL * 0.5, 372.0)
	_draw_frame()
	_grid.resize(COLS)
	for c in COLS:
		_grid[c] = []
		_grid[c].resize(ROWS)
	_initial_fill()
	emit_signal("score_changed", _score)
	emit_signal("moves_changed", _moves)


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
	# Soft rounded play-field panel behind the gems.
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.22)
	style.set_corner_radius_all(28)
	style.set_border_width_all(2)
	style.border_color = Color(1, 1, 1, 0.10)
	style.expand_margin_top = 18
	style.expand_margin_bottom = 18
	style.expand_margin_left = 18
	style.expand_margin_right = 18
	panel.add_theme_stylebox_override("panel", style)
	var top_left := _cell_pos(0, 0) - Vector2(CELL, CELL) * 0.5
	panel.position = top_left
	panel.size = Vector2(COLS * CELL, ROWS * CELL)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)


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
			var type := _safe_type(c, r)
			var g := _make_gem(type, c, r)
			# Cascade them in from the top for a satisfying entrance.
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


# ------------------------------------------------------------------ input ---
func _unhandled_input(event: InputEvent) -> void:
	if _busy:
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
	if nc < 0 or nc >= COLS or nr < 0 or nr >= ROWS:
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
		# Invalid: swap back with a little shake.
		Audio.play("invalid")
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


# --------------------------------------------------------------- matching ---
## Returns an Array of "runs": each run is a Dictionary { cells:[Vector2i], len:int }.
func _find_runs() -> Array:
	var runs: Array = []
	# Horizontal.
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
	# Vertical.
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
		# Also pull in any specials that got dragged into a match.
		if matched.is_empty():
			break

		combo += 1
		emit_signal("combo_changed", combo)
		# Each cascade step rings a semitone higher — the satisfying combo ladder.
		Audio.play("match", pow(2.0, min(combo - 1, 12) / 12.0))

		# Decide which cells become new special pieces (don't clear those).
		var survivors := {}    # Vector2i -> kind
		for run in runs:
			if run["len"] < 4:
				continue
			var kind := Gem.STRIPE if run["len"] == 4 else Gem.BOMB
			var cell: Vector2i = _pick_survivor(run, swap_a, swap_b)
			if survivors.has(cell):
				survivors[cell] = max(survivors[cell], kind)
			else:
				survivors[cell] = kind

		# Expand the clear set through any triggered specials.
		_expand_specials(matched)
		for cell in survivors:
			matched.erase(cell)

		# Score: rewards big groups and deep cascades.
		var gained := matched.size() * 30 * combo
		_score += gained
		emit_signal("score_changed", _score)
		_spawn_score_popup(matched, gained, combo)
		if combo >= 2:
			_shake(min(2.0 + combo, 8.0))

		# Pop everything in the clear set.
		for cell in matched:
			var g: Gem = _grid[cell.x][cell.y]
			if g:
				_grid[cell.x][cell.y] = null
				g.pop()

		# Forge the new specials.
		if not survivors.is_empty():
			Audio.play("special")
		for cell in survivors:
			var g: Gem = _grid[cell.x][cell.y]
			if g:
				g.set_special(survivors[cell])

		await get_tree().create_timer(0.18).timeout
		await _collapse_and_refill()

	emit_signal("combo_changed", 0)
	if _moves <= 0:
		return
	if not _has_possible_move():
		await _reshuffle()


func _pick_survivor(run: Dictionary, a: Gem, b: Gem) -> Vector2i:
	for cell in run["cells"]:
		if a and cell == Vector2i(a.col, a.row):
			return cell
		if b and cell == Vector2i(b.col, b.row):
			return cell
	return run["cells"][run["cells"].size() / 2]


## BFS over specials inside the clear set, adding the cells each one blasts.
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
			matched[t] = true
			var tg: Gem = _grid[t.x][t.y]
			if tg and tg.special != Gem.NONE and not done.has(t):
				queue.append(t)
	if not done.is_empty():
		_shake(5.0)
		Audio.play("blast")


# ----------------------------------------------------- gravity & refill ---
func _collapse_and_refill() -> void:
	var longest := 0.0
	for c in COLS:
		# Compact existing gems downward.
		var write := ROWS - 1
		for r in range(ROWS - 1, -1, -1):
			var g: Gem = _grid[c][r]
			if g:
				if write != r:
					_grid[c][write] = g
					_grid[c][r] = null
					g.row = write
					var dist: int = write - r
					g.move_to(_cell_pos(c, write), 0.16 + dist * 0.035, 0.0, Tween.TRANS_BOUNCE)
					longest = max(longest, 0.16 + dist * 0.035)
				write -= 1
		# Spawn new gems above the board to fill the gap.
		var spawn := 0
		for r in range(write, -1, -1):
			var type := randi() % NUM_TYPES
			var g := Gem.new()
			g.setup(type, GEM_SIZE, _gem_shader)
			g.col = c
			g.row = r
			g.position = _cell_pos(c, -1 - spawn)
			add_child(g)
			_grid[c][r] = g
			var dur := 0.28 + (r + spawn) * 0.03
			g.move_to(_cell_pos(c, r), dur, spawn * 0.02, Tween.TRANS_BOUNCE)
			longest = max(longest, dur)
			spawn += 1
	# A soft thud when the wave of gems settles into place.
	Audio.play("land", randf_range(0.95, 1.05), -4.0)
	await get_tree().create_timer(longest + 0.05).timeout


# ----------------------------------------------------------- no-moves AI ---
func _has_possible_move() -> bool:
	# Try every adjacent swap on a virtual copy; any 3-match means a move exists.
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
	if a == null or b == null:
		return false
	_grid[c1][r1] = b
	_grid[c2][r2] = a
	var found := _cell_in_match(c1, r1) or _cell_in_match(c2, r2)
	_grid[c1][r1] = a
	_grid[c2][r2] = b
	return found


func _cell_in_match(c: int, r: int) -> bool:
	var t: int = _grid[c][r].type
	# Horizontal run length through (c,r).
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
	# Re-roll types in place until at least one move exists and no instant matches.
	for _i in 40:
		for c in COLS:
			for r in ROWS:
				_grid[c][r].type = randi() % NUM_TYPES
		if _find_matches().is_empty() and _has_possible_move():
			break
	# Re-skin every gem and bounce them to advertise the shuffle.
	for c in COLS:
		for r in ROWS:
			var g: Gem = _grid[c][r]
			g.queue_free()
			_grid[c][r] = null
	await get_tree().process_frame
	for c in COLS:
		for r in ROWS:
			var g := _make_gem(randi() % NUM_TYPES, c, r)
			g.position = _cell_pos(c, r) - Vector2(0, (ROWS + 2) * CELL)
			g.move_to(_cell_pos(c, r), 0.5, (c + r) * 0.02, Tween.TRANS_BACK)
	await get_tree().create_timer(0.6).timeout


# ------------------------------------------------------------------- juice ---
func _shake(strength: float) -> void:
	var t := create_tween()
	for i in 6:
		t.tween_property(self, "position",
			Vector2(randf_range(-strength, strength), randf_range(-strength, strength)),
			0.03)
	t.tween_property(self, "position", Vector2.ZERO, 0.05)


func _spawn_score_popup(cells: Dictionary, amount: int, combo: int) -> void:
	if cells.is_empty():
		return
	var avg := Vector2.ZERO
	for cell in cells:
		avg += _cell_pos(cell.x, cell.y)
	avg /= cells.size()

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
