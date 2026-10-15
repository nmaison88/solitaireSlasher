extends Node
# TEMPORARY multiplayer test driver (deleted after the test run).
# Launch: Godot --path . -- --role=host|client --game=Solitaire|Spider

var role := ""
var game := "Solitaire"
var num_clients := 1  # Host: how many clients to wait for
var idx := 1  # Client: 1-based index; staggers join time and when it drops out
var main: Node
var _last_move := []
var _race_ended_count := 0
var _all_ready_seen := false

func log_line(s: String) -> void:
	print("MPTEST[", role, "] ", s)

func _ready() -> void:
	main = get_parent()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.split("=")[1]
		elif a.begins_with("--game="):
			game = a.split("=")[1]
		elif a.begins_with("--clients="):
			num_clients = int(a.split("=")[1])
		elif a.begins_with("--idx="):
			idx = int(a.split("=")[1])
	if role == "client":
		role = "client%d" % idx
	MultiplayerGameManager.player_status_changed.connect(func(pid, st):
		log_line("status_changed player=%s status=%s (me=%s)" % [pid, st, NetworkManager.local_player_id]))
	MultiplayerGameManager.race_ended.connect(func(w, _n, _t):
		_race_ended_count += 1
		log_line("race_ended winner=%s" % w))
	MultiplayerGameManager.last_player_standing.connect(func(pid): log_line("last_player_standing %s" % pid))
	MultiplayerGameManager.all_players_ready.connect(func():
		_all_ready_seen = true
		log_line("all_players_ready"))
	run()

func wait_until(cond: Callable, timeout: float = 20.0) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().create_timer(0.1).timeout
		t += 0.1
		if t > timeout:
			return false
	return true

func current_game() -> Object:
	if game == "Solitaire":
		return MultiplayerGameManager.local_game
	if game == "Sudoku":
		return main._sudoku_game
	return main._spider_board._game if main._spider_board else null

func deal_ready() -> bool:
	var g = current_game()
	if not is_instance_valid(g):
		return false
	if game == "Solitaire":
		return g.tableau.size() == 7 and not g.tableau[6].is_empty()
	if game == "Sudoku":
		return g.puzzle.size() == 9 and g.solution_grid.size() == 9
	return g.tableaus.size() > 0 and not g.tableaus[0].is_empty()

func signature() -> String:
	var g = current_game()
	if game == "Sudoku":
		return str((str(g.puzzle) + str(g.solution_grid)).hash())
	var parts := []
	var cols = g.tableau if game == "Solitaire" else g.tableaus
	for col in cols:
		for c in col:
			parts.append("%d.%d" % [c.suit, c.rank])
		parts.append("|")
	for c in g.stock:
		parts.append("%d.%d" % [c.suit, c.rank])
	return str(",".join(parts).hash())

func others_jammed() -> int:
	var n := 0
	for pid in MultiplayerGameManager.player_statuses:
		if pid != NetworkManager.local_player_id and MultiplayerGameManager.player_statuses[pid] == MultiplayerGameManager.PlayerStatus.JAMMED:
			n += 1
	return n

func other_player_jammed() -> bool:
	for pid in MultiplayerGameManager.player_statuses:
		if pid != NetworkManager.local_player_id and MultiplayerGameManager.player_statuses[pid] == MultiplayerGameManager.PlayerStatus.JAMMED:
			return true
	return false

func run() -> void:
	await get_tree().create_timer(1.0 if role == "host" else 3.0 + idx * 1.5).timeout
	main._current_game_type = game
	if role == "host":
		main._on_host_game(game)
		await wait_until(func(): return main._multiplayer_lobby != null and main._multiplayer_lobby.is_host)
		await get_tree().create_timer(0.5).timeout
		main._multiplayer_lobby.mirror_mode_enabled = true
		MultiplayerGameManager.mirror_mode_enabled = true
		var joined = await wait_until(func(): return NetworkManager.get_players().size() >= num_clients + 1, 40.0)
		log_line("client joined=%s" % joined)
		await get_tree().create_timer(1.0).timeout
		main._multiplayer_lobby._on_start_pressed()
	else:
		main._on_join_game(game)
		await wait_until(func(): return main._multiplayer_lobby != null and main._multiplayer_lobby.ip_input != null)
		await get_tree().create_timer(0.5).timeout
		main._multiplayer_lobby.ip_input.text = "127.0.0.1"
		main._multiplayer_lobby._on_join_pressed()

	var ready1 = await wait_until(deal_ready, 30.0)
	await get_tree().create_timer(2.0).timeout
	log_line("round1 ready=%s players=%d SIG=%s" % [ready1, NetworkManager.get_players().size(), signature() if ready1 else "-"])
	# Stagger drop-outs: client k waits k*8s first, so they leave the race one at a time
	if role.begins_with("client"):
		await get_tree().create_timer(idx * 8.0).timeout

	if role.begins_with("client") and game == "Sudoku":
		await sudoku_play()
	elif role.begins_with("client"):
		await play_steps(80)
		if game == "Spider":
			# Rig a genuinely stuck board and fire a move: the Spider status check should report jammed
			var g = main._spider_board._game
			g.stock.clear()
			for col in g.tableaus.size():
				var ace = load("res://scripts/Card.gd").new()
				ace.suit = col % 4; ace.rank = 1; ace.face_up = true
				g.tableaus[col] = [ace]
			log_line("rigged stuck board, has_valid_moves=%s" % g.has_valid_moves())
			g.card_moved.emit()
			await get_tree().create_timer(1.0).timeout
			log_line("after rigged move my_reported_status=%s (1=JAMMED)" % MultiplayerGameManager.player_statuses.get(NetworkManager.local_player_id, -1))
		log_line("client forfeiting")
		main._on_forfeit_pressed()
	else:
		var saw = await wait_until(func(): return others_jammed() >= num_clients, 150.0)
		await get_tree().create_timer(2.0).timeout
		log_line("host saw client jammed=%s; race ended before host forfeited=%s (expect false); host forfeiting" % [saw, _race_ended_count > 0])
		main._on_forfeit_pressed()

	var ended = await wait_until(func(): return main._ready_button != null and is_instance_valid(main._ready_button), 20.0)
	log_line("ready screen shown=%s" % ended)
	await get_tree().create_timer(0.5).timeout
	main._on_ready_pressed()

	await wait_until(func(): return _all_ready_seen, 60.0)
	await get_tree().create_timer(4.0).timeout  # New round: settings, game start and mirror data
	var ready2 = await wait_until(deal_ready, 20.0)
	await get_tree().create_timer(1.0).timeout
	log_line("round2 ready=%s SIG=%s" % [ready2, signature() if ready2 else "-"])
	await get_tree().create_timer(3.0).timeout
	log_line("DONE")
	get_tree().quit()

func play_steps(n: int) -> void:
	for i in range(n):
		var acted := solitaire_step() if game == "Solitaire" else spider_step()
		await get_tree().create_timer(0.15).timeout
		var g = current_game()
		var me = NetworkManager.local_player_id
		log_line("STEP %d %s truly_has_moves=%s my_reported_status=%s" % [i, acted, g.has_valid_moves(), MultiplayerGameManager.player_statuses.get(me, -1)])

func solitaire_step() -> String:
	var g = MultiplayerGameManager.local_game
	var h = g.get_hint()
	var acted := ""
	match h.type:
		"tableau_to_foundation":
			g.move_to_foundation("tableau", h.from, h.to); acted = "t->f"
		"waste_to_foundation":
			g.move_to_foundation("waste", 0, h.to); acted = "w->f"
		"waste_to_tableau":
			g.move_waste_to_tableau(h.to); acted = "w->t"
		"tableau_to_tableau":
			var pointless = h.count == g.tableau[h.from].size() and g.tableau[h.to].is_empty()
			if not pointless and _last_move != [h.to, h.from]:
				g.move_tableau_to_tableau(h.from, h.to, h.count); acted = "t->t"
				_last_move = [h.from, h.to]
	if acted == "":
		g.draw_from_stock_3(); acted = "draw"
	main._board.render()
	return acted

func spider_step() -> String:
	var g = main._spider_board._game
	for from_col in range(g.TABLEAU_COUNT):
		var col = g.tableaus[from_col]
		var idx = col.size() - 1
		while idx >= 0 and g.can_move_from(from_col, idx):
			for to_col in range(g.TABLEAU_COUNT):
				if to_col == from_col or (idx == 0 and g.tableaus[to_col].is_empty()):
					continue
				if _last_move == [to_col, from_col]:
					continue
				if g.can_place_on(col[idx], to_col) and not g.tableaus[to_col].is_empty():
					g.move_cards(from_col, idx, to_col)
					_last_move = [from_col, to_col]
					main._spider_board.render()
					return "move"
			idx -= 1
	if not g.stock.is_empty():
		g.deal_from_stock()
		main._spider_board.render()
		return "deal"
	return "idle"

func sudoku_play() -> void:
	var b = main._sudoku_board
	var g = main._sudoku_game
	var me = NetworkManager.local_player_id
	var filled := 0
	for r in 9:
		for c in 9:
			if filled < 10 and g.is_cell_editable(r, c) and g.get_cell_value(r, c) == 0:
				b._on_cell_pressed(Vector2i(r, c))
				b._on_number_selected(g.get_solution_value(r, c))
				filled += 1
				await get_tree().create_timer(0.1).timeout
	log_line("filled %d correct cells, lives=%d my_reported_status=%s (0=PLAYING)" % [filled, g.lives, MultiplayerGameManager.player_statuses.get(me, -1)])
	for k in 3:
		var done := false
		for r in 9:
			for c in 9:
				if not done and g.is_cell_editable(r, c) and g.get_cell_value(r, c) == 0:
					b._on_cell_pressed(Vector2i(r, c))
					b._on_number_selected((g.get_solution_value(r, c) % 9) + 1)
					done = true
		await get_tree().create_timer(0.5).timeout
		log_line("wrong entry %d -> lives=%d my_reported_status=%s" % [k + 1, g.lives, MultiplayerGameManager.player_statuses.get(me, -1)])
