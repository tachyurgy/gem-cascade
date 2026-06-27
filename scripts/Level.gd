class_name Level
extends RefCounted
## A single hand-authored puzzle: the board SHAPE (which cells exist), where the
## jelly and crate blockers sit, the win OBJECTIVE, and a tuned MOVE budget.
##
## None of this can be procedurally generated into a *good* puzzle — the fun lives
## in the spatial arrangement and a move budget tuned to be just-barely-winnable.
## That is exactly why the game needs a level EDITOR: levels are content, authored
## and playtested by hand, not random boards.

# Objective kinds.
const OBJ_SCORE := 0    ## reach a target score
const OBJ_JELLY := 1    ## clear every jelly tile
const OBJ_COLLECT := 2  ## collect N gems of a chosen colour
const OBJ_CRATES := 3   ## smash every crate

const OBJ_NAMES := ["Score", "Clear Jelly", "Collect", "Smash Crates"]

var id: String = "level"
var name: String = "Untitled"
var cols: int = 7
var rows: int = 8
var moves: int = 25

# Per-cell layers, indexed [c][r].
var mask: Array = []    # bool  — is this cell part of the board?
var jelly: Array = []   # int 0..2 — jelly coating thickness
var crate: Array = []   # int 0..2 — crate hp (0 = no crate)

var obj_type: int = OBJ_SCORE
var obj_color: int = 0   # colour index for OBJ_COLLECT
var obj_count: int = 1500


static func blank(p_cols: int = 7, p_rows: int = 8) -> Level:
	var lv := Level.new()
	lv.cols = p_cols
	lv.rows = p_rows
	lv.ensure_grids()
	for c in p_cols:
		for r in p_rows:
			lv.mask[c][r] = true
	return lv


## (Re)allocate the per-cell arrays to cols x rows, preserving overlap.
func ensure_grids() -> void:
	mask = _resize_grid(mask, false)
	jelly = _resize_grid(jelly, 0)
	crate = _resize_grid(crate, 0)


func _resize_grid(src: Array, fill) -> Array:
	var out: Array = []
	out.resize(cols)
	for c in cols:
		var colarr: Array = []
		colarr.resize(rows)
		for r in rows:
			if c < src.size() and r < src[c].size():
				colarr[r] = src[c][r]
			else:
				colarr[r] = fill
		out[c] = colarr
	return out


func playable(c: int, r: int) -> bool:
	if c < 0 or c >= cols or r < 0 or r >= rows:
		return false
	return bool(mask[c][r])


## How many jelly units exist — used as the JELLY objective total.
func jelly_total() -> int:
	var n := 0
	for c in cols:
		for r in rows:
			n += int(jelly[c][r])
	return n


func crate_total() -> int:
	var n := 0
	for c in cols:
		for r in rows:
			if int(crate[c][r]) > 0:
				n += 1
	return n


# ---------------------------------------------------------------- (de)serialise ---
func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "cols": cols, "rows": rows, "moves": moves,
		"mask": mask, "jelly": jelly, "crate": crate,
		"obj_type": obj_type, "obj_color": obj_color, "obj_count": obj_count,
		"v": 1,
	}


static func from_dict(d: Dictionary) -> Level:
	var lv := Level.new()
	lv.id = str(d.get("id", "level"))
	lv.name = str(d.get("name", "Untitled"))
	lv.cols = int(d.get("cols", 7))
	lv.rows = int(d.get("rows", 8))
	lv.moves = int(d.get("moves", 25))
	lv.obj_type = int(d.get("obj_type", OBJ_SCORE))
	lv.obj_color = int(d.get("obj_color", 0))
	lv.obj_count = int(d.get("obj_count", 1500))
	lv.ensure_grids()
	_copy_grid(d.get("mask", []), lv.mask, lv.cols, lv.rows, false, true)
	_copy_grid(d.get("jelly", []), lv.jelly, lv.cols, lv.rows, 0, false)
	_copy_grid(d.get("crate", []), lv.crate, lv.cols, lv.rows, 0, false)
	return lv


static func _copy_grid(src, dst: Array, cols: int, rows: int, fill, as_bool: bool) -> void:
	for c in cols:
		for r in rows:
			var v = fill
			if src is Array and c < src.size() and src[c] is Array and r < src[c].size():
				v = src[c][r]
			dst[c][r] = bool(v) if as_bool else int(v)


func save_to(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	return OK


static func load_from(path: String) -> Level:
	if not FileAccess.file_exists(path):
		return null
	var txt := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(txt)
	if data is Dictionary:
		return from_dict(data)
	return null


# --------------------------------------------------------------------- built-ins ---
## A small curated campaign so the game has content out of the box. Each one is a
## deliberately different shape + objective — i.e. the kind of thing only a human
## designer (with an editor) produces.
static func builtins() -> Array:
	return [_b1(), _b2(), _b3(), _b4()]


static func _b1() -> Level:
	# Tutorial: small full board, score goal.
	var lv := Level.blank(7, 8)
	lv.id = "campaign_1"
	lv.name = "First Sparks"
	lv.moves = 20
	lv.obj_type = OBJ_SCORE
	lv.obj_count = 2000
	return lv


static func _b2() -> Level:
	# Jelly cross in the middle — clear all jelly.
	var lv := Level.blank(7, 8)
	lv.id = "campaign_2"
	lv.name = "Cracked Glass"
	lv.moves = 22
	lv.obj_type = OBJ_JELLY
	for c in range(2, 5):
		for r in range(2, 6):
			lv.jelly[c][r] = 1
	lv.jelly[3][3] = 2
	lv.jelly[3][4] = 2
	return lv


static func _b3() -> Level:
	# Diamond board shape with crates in the corners.
	var lv := Level.blank(7, 8)
	lv.id = "campaign_3"
	lv.name = "The Vault"
	lv.moves = 24
	lv.obj_type = OBJ_CRATES
	# Carve the corners off to make a hexish shape.
	for c in lv.cols:
		for r in lv.rows:
			if (c + r < 2) or (c - r > 5) or (r - c > 6) or (c + r > 12):
				lv.mask[c][r] = false
	for cell in [Vector2i(1, 2), Vector2i(5, 2), Vector2i(1, 5), Vector2i(5, 5), Vector2i(3, 0)]:
		if lv.playable(cell.x, cell.y):
			lv.crate[cell.x][cell.y] = 1
	return lv


static func _b4() -> Level:
	# Collect goal: gather rose gems on a tall, narrow board.
	var lv := Level.blank(6, 9)
	lv.id = "campaign_4"
	lv.name = "Rose Harvest"
	lv.moves = 26
	lv.obj_type = OBJ_COLLECT
	lv.obj_color = 0   # rose
	lv.obj_count = 30
	# A couple of jelly accents for flavour.
	for c in lv.cols:
		lv.jelly[c][lv.rows - 1] = 1
	return lv
