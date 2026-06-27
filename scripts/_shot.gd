extends Node
func _ready() -> void:
	await get_tree().process_frame
	# 1) Menu
	var menu := LevelSelect.new()
	add_child(menu)
	await get_tree().create_timer(0.8).timeout
	await _shot("menu")
	menu.queue_free()
	await get_tree().process_frame
	# 2) Jelly level (campaign_2) — play a few auto-moves
	var jelly_lv = Level.builtins()[1]
	var g := GameScene.new()
	g.level = jelly_lv
	add_child(g)
	await get_tree().create_timer(2.0).timeout
	await _shot("jelly_start")
	# drive a couple auto-swaps to crack some jelly
	for i in 4:
		await _auto_move(g._board)
		await get_tree().create_timer(0.6).timeout
	await _shot("jelly_played")
	g.queue_free()
	await get_tree().process_frame
	# 3) Crate + shaped board (campaign_3)
	var vault := GameScene.new()
	vault.level = Level.builtins()[2]
	add_child(vault)
	await get_tree().create_timer(2.0).timeout
	await _shot("vault_shape")
	vault.queue_free()
	await get_tree().process_frame
	# 4) Editor
	var ed := LevelEditor.new()
	add_child(ed)
	await get_tree().create_timer(0.8).timeout
	await _shot("editor")
	get_tree().quit()

func _auto_move(board) -> void:
	if board == null or board._busy or board._ended:
		return
	for c in board.COLS:
		for r in board.ROWS:
			if c+1 < board.COLS and board._swap_makes_match(c,r,c+1,r):
				await board._try_swap(board._grid[c][r], board._grid[c+1][r]); return
			if r+1 < board.ROWS and board._swap_makes_match(c,r,c,r+1):
				await board._try_swap(board._grid[c][r], board._grid[c][r+1]); return

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/v3_%s.png" % name)
