extends Node
## Drives the real game for App Store captures; added to Main by record-store-assets.sh in a
## temporary project copy. Uses the game's own handlers, so everything shown is real gameplay.
## User args: --mode=video | --mode=shots | --mode=seed, --out=<folder for screenshots>

const END_TIME := 26.0  # Seconds; App Store previews must be 15-30 s

var main: Node
var mode := "video"
var out_dir := ""
var _seen_states := {}

func _ready() -> void:
	main = get_parent()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.split("=")[1]
		elif arg.begins_with("--out="):
			out_dir = arg.split("=")[1]
	_clear_saved_games()
	match mode:
		"video":
			_record_video()
		"shots":
			_take_screenshots()

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _age_game(game: Object, seconds: float) -> void:
	"""Show a realistic time on the HUD for a screenshot"""
	game._start_time -= seconds

func _start_solitaire() -> void:
	main._current_game_type = "Solitaire"
	main._on_game_selected()

# ── Video ────────────────────────────────────────────────────────────────────

func _record_video() -> void:
	PlayerData.background_music_enabled = true  # This copy's save only
	await _wait(1.8)
	var carousel = main._menu_carousel
	for index in [1, 2, 0]:
		carousel.go_to_index(index)
		await _wait(1.5)
	main._on_menu_play_pressed()
	await _wait(2.2)
	main._on_single_player_start("Solitaire")
	await _wait(2.6)  # Deal
	# Movie Maker runs on a fixed 30 fps clock, so count frames rather than wall time
	var end_frame := Engine.get_process_frames() + int((END_TIME - 2.6 - 2.2 - 1.8 - 4.5) * 30.0)
	while Engine.get_process_frames() < end_frame:
		await _play_solitaire_step()
		await _wait(0.45)
	await _wait(1.0)
	get_tree().quit()

# ── Screenshots ──────────────────────────────────────────────────────────────

func _shot(file_name: String) -> void:
	await _wait(0.5)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)  # App Store rejects screenshots with alpha
	image.save_png("%s/%s.png" % [out_dir, file_name])
	print("SHOT ", file_name, " ", image.get_size())

func _clear_saved_games() -> void:
	"""Saved games would put the Continue dialog in front of the next game"""
	for game_type in ["Solitaire", "Spider", "Sudoku"]:
		PlayerData.clear_saved_game(game_type)

func _clear_screen() -> void:
	main._on_back_to_menu_pressed()
	_clear_saved_games()
	await _wait(0.5)

func _take_screenshots() -> void:
	await _wait(1.5)
	await _shot("01-choose-your-game")

	main._current_game_type = "Solitaire"
	main._on_menu_play_pressed()
	await _wait(0.6)
	await _shot("02-difficulty")
	main._on_game_menu_back()
	await _wait(0.4)

	main._current_game_type = "Solitaire"
	main._current_difficulty = "Medium"
	main._on_game_selected()
	await _wait(0.3)
	main._on_single_player_start("Solitaire")
	await _wait(2.6)
	for i in 18:
		await _play_solitaire_step()
	_age_game(main._game, 134.0)
	await _shot("03-solitaire-slasher")
	await _clear_screen()

	PlayerData.deck_style = "classic"
	_seen_states.clear()
	main._current_game_type = "Solitaire"
	main._current_difficulty = "Medium"
	main._on_game_selected()
	await _wait(0.3)
	main._on_single_player_start("Solitaire")
	await _wait(2.6)
	for i in 18:
		await _play_solitaire_step()
	_age_game(main._game, 118.0)
	await _shot("04-classic-deck")
	await _clear_screen()
	PlayerData.deck_style = "slasher"

	main._current_game_type = "Spider"
	main._current_difficulty = "Medium"
	main._on_game_selected()
	await _wait(0.3)
	main._on_single_player_start("Spider")
	await _wait(3.0)
	for i in 14:
		await _play_spider_step()
	_age_game(main._spider_board._game, 201.0)
	await _shot("05-spider")
	await _clear_screen()

	main._current_game_type = "Sudoku"
	main._current_difficulty = "Medium"
	main._on_game_selected()
	await _wait(0.3)
	main._on_single_player_start("Sudoku")
	await _wait(1.0)
	_fill_sudoku(14)
	_age_game(main._sudoku_game, 256.0)
	await _shot("06-sudoku")
	await _clear_screen()

	main._current_game_type = "Spider"
	main._on_show_multiplayer_menu("Spider")
	await _wait(0.5)
	await _shot("07-multiplayer")
	get_tree().quit()

func _fill_sudoku(cells: int) -> void:
	var game = main._sudoku_game
	var board = main._sudoku_board
	var last := Vector2i(-1, -1)
	for r in 9:
		for c in 9:
			if cells > 0 and game.is_cell_editable(r, c) and game.get_cell_value(r, c) == 0:
				board._on_cell_pressed(Vector2i(r, c))
				board._on_number_selected(game.get_solution_value(r, c))
				last = Vector2i(r, c)
				cells -= 1
	if last.x >= 0:
		board._on_cell_pressed(last)

# ── Bots: pick a real legal move and play it through the board's tap handlers ─

func _layout(game) -> String:
	var parts := []
	for pile in game.tableau:
		for card in pile:
			parts.append("%d.%d" % [card.suit, card.rank])
		parts.append("|")
	return ",".join(parts)

func _pick_solitaire_card(game) -> SolitaireCard:
	"""A card worth tapping, or null to draw. Skips moves that would just shuffle cards back and forth."""
	var hint: Dictionary = game.get_hint()
	match hint.type:
		"tableau_to_foundation":
			return game.tableau[hint.from][-1]
		"waste_to_foundation", "waste_to_tableau":
			return game.waste[-1]
		"tableau_to_tableau":
			var pile = game.tableau[hint.from]
			var pointless: bool = hint.count == pile.size() and game.tableau[hint.to].is_empty()
			var state := _layout(game) + str(hint.from) + ">" + str(hint.to)
			if not pointless and not _seen_states.has(state):
				_seen_states[state] = true
				return pile[pile.size() - hint.count]
	return null

func _play_solitaire_step() -> void:
	var board = main._board
	var game = main._game
	var card := _pick_solitaire_card(game)
	var view: CardView = null
	if card:
		for child in board.get_children():
			if child is CardView and child.card == card:
				view = child
				break
	if view:
		board._on_card_clicked(view)
	else:
		board._on_stock_pressed()
	await get_tree().process_frame
	while board._animating:
		await get_tree().process_frame

func _play_spider_step() -> void:
	var board = main._spider_board
	var game = board._game
	for from_col in range(game.TABLEAU_COUNT):
		var col = game.tableaus[from_col]
		var idx: int = col.size() - 1
		while idx >= 0 and game.can_move_from(from_col, idx):
			for to_col in range(game.TABLEAU_COUNT):
				var state := str(from_col, ">", to_col, "#", idx, "#", col.size(), "#", game.stock.size())
				if to_col != from_col and not game.tableaus[to_col].is_empty() and game.can_place_on(col[idx], to_col) and not _seen_states.has(state):
					_seen_states[state] = true
					for child in board.get_children():
						if child is CardView and child.card == col[idx]:
							board._on_card_clicked(child)
							await get_tree().process_frame
							while board._animating:
								await get_tree().process_frame
							return
			idx -= 1
	if not game.stock.is_empty():
		board._on_stock_pressed()
		await get_tree().process_frame
		while board._animating:
			await get_tree().process_frame
