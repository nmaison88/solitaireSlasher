extends Node

signal race_started
signal race_ended(winner_id: int, winner_name: String, time: float)
signal player_progress_updated(player_id: int, progress: float)
signal player_status_changed(player_id: int, status: String)
signal last_player_standing(player_id: int)
signal all_players_ready

enum PlayerStatus {
	PLAYING,
	JAMMED,
	COMPLETED
}

var network_manager: NetworkManager
var local_game: Game
var is_multiplayer: bool = false
var race_start_time: float = 0.0
var local_player_finished: bool = false
var _race_ended: bool = false  # Guard against multiple race_ended emissions
var player_statuses: Dictionary = {}  # player_id -> PlayerStatus
var players_ready: Dictionary = {}  # player_id -> bool (for next round)
var current_game_type: String = "Solitaire"  # "Solitaire" or "Sudoku"
var sudoku_puzzle_state: Dictionary = {}  # Shared Sudoku puzzle for all players
var _pending_mirror_data: Dictionary = {}  # Mirror data waiting to be applied
var mirror_mode_enabled: bool = false  # Store mirror mode setting from lobby

func _ready() -> void:
	# NetworkManager is an autoload singleton, don't create a new instance
	network_manager = NetworkManager

	network_manager.game_started.connect(_on_race_started)
	network_manager.race_completed.connect(_on_race_completed)
	network_manager.game_state_received.connect(_on_game_state_received)
	network_manager.player_disconnected.connect(_on_player_disconnected_during_game)

func host_multiplayer_game(player_name: String) -> bool:
	if network_manager.host_game(player_name):
		is_multiplayer = true
		return true
	return false

func join_multiplayer_game(host_ip: String, player_name: String) -> bool:
	if network_manager.join_game(host_ip, player_name):
		is_multiplayer = true
		return true
	return false

func start_local_game(difficulty: String = "Medium") -> void:
	print("MultiplayerGameManager: Starting local game with difficulty: ", difficulty)
	# Don't reset is_multiplayer here - it's already set by host_multiplayer_game() or join_multiplayer_game()
	# Only set to false if we're truly in single player mode (not connected to network)
	if not network_manager.is_host and network_manager.players.size() <= 1:
		is_multiplayer = false

	# Clean up old game node if it exists
	if local_game:
		local_game.queue_free()

	local_game = Game.new()
	add_child(local_game)
	local_game.set_difficulty(difficulty)
	local_game.new_game()
	local_game.game_completed.connect(_on_local_game_completed)
	print("Local game created and initialized (multiplayer: ", is_multiplayer, ")")

func start_multiplayer_race() -> void:
	print("DEBUG: start_multiplayer_race() called")
	print("DEBUG: is_multiplayer: ", is_multiplayer)
	print("DEBUG: network_manager.is_host: ", network_manager.is_host)
	print("DEBUG: current_game_type: ", current_game_type)
	
	if not is_multiplayer or not network_manager.is_host:
		print("DEBUG: Early return from start_multiplayer_race - is_multiplayer: ", is_multiplayer, ", is_host: ", network_manager.is_host)
		return
	
	print("Host: Starting multiplayer race for ", current_game_type)
	
	local_game = Game.new()
	add_child(local_game)
	
	# Create deck and shuffle it first
	var deck = Deck.new_standard_deck()
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var seed = randi()
	rng.seed = seed
	Deck.shuffle(deck, rng)
	
	# Prepare mirror data for later sending
	# Use the stored mirror mode setting from MultiplayerGameManager
	print("DEBUG: Using stored mirror mode setting: ", mirror_mode_enabled)
	var lobby_mirror_mode = mirror_mode_enabled
	
	var prepared_mirror_data = null
	if lobby_mirror_mode:
		if current_game_type == "Solitaire":
			# Prepare Solitaire mirror data
			var deck_data = []
			for card in deck:
				deck_data.append({
					"suit": card.suit,
					"rank": card.rank,
					"face_up": false,  # All cards start face down
					"pile_id": -1,  # Not assigned yet
					"stock": false
				})
			prepared_mirror_data = {
				"deck": deck_data,
				"seed": seed,
				"difficulty": local_game.difficulty
			}
			print("Host: Prepared mirror data for Solitaire")
		elif current_game_type == "Sudoku":
			# Sudoku handles its own mirror data in Main.gd, so don't prepare it here
			prepared_mirror_data = null
			print("Host: Sudoku handles mirror data separately, skipping preparation")
		elif current_game_type == "Spider":
			# Spider handles its own mirror data in Main.gd, so don't prepare it here
			prepared_mirror_data = null
			print("Host: Spider handles mirror data separately, skipping preparation")
		else:
			print("Host: Unknown game type for mirror data: ", current_game_type)
	else:
		print("Host: Mirror mode disabled - not preparing mirror data")
	
	# Now deal the game normally
	local_game.new_game(seed)
	
	# Broadcast game settings and start race
	var broadcast_settings = {
		"game_type": current_game_type,
		"difficulty": local_game.difficulty,
		"mirror_mode": lobby_mirror_mode
	}
	print("DEBUG: Broadcasting settings with mirror_mode: ", lobby_mirror_mode)
	network_manager.start_race(broadcast_settings)
	
	# Send mirror data after a short delay to ensure clients are ready
	if prepared_mirror_data:
		print("Host: Waiting 0.5s before sending mirror data...")
		var timer = get_tree().create_timer(0.5)
		timer.timeout.connect(func():
			print("Host: Sending mirror data now")
			network_manager.send_mirror_data({"game_type": current_game_type, "mirror_data": prepared_mirror_data})
			print("Host: Sent ", current_game_type, " mirror data after delay")
		)
	else:
		print("Host: No mirror data to send (mirror mode disabled)")

func _on_race_started() -> void:
	# Get the game type from network settings (for clients) or local variable (for host)
	var game_type = current_game_type
	if not network_manager.is_host and NetworkManager.game_settings.has("game_type"):
		game_type = NetworkManager.game_settings["game_type"]
		print("DEBUG: Client using received game type: ", game_type)
	else:
		print("DEBUG: Using local game type: ", game_type)
		
	print("DEBUG: MultiplayerGameManager._on_race_started() - game_type: ", game_type)
	race_start_time = Time.get_ticks_msec() / 1000.0  # Use ticks instead of wall-clock time
	local_player_finished = false

	# Only create and initialize game for Solitaire
	# For Sudoku and Spider, the game is already set up in Main.gd
	if game_type == "Solitaire":
		if not local_game:
			local_game = Game.new()
			add_child(local_game)
		
		# Check if mirror mode is enabled
		var mirror_mode_enabled = false
		
		# For host, use the stored setting
		if network_manager.is_host:
			mirror_mode_enabled = self.mirror_mode_enabled  # Use the stored variable
			print("Host: Using stored mirror mode setting: ", mirror_mode_enabled)
		# For client, check received settings
		elif network_manager.game_settings.has("mirror_mode"):
			mirror_mode_enabled = network_manager.game_settings["mirror_mode"]
			print("Client: Mirror mode enabled in settings: ", mirror_mode_enabled)
		
		# Check if we have pending mirror data (for clients)
		if mirror_mode_enabled and not _pending_mirror_data.is_empty():
			print("Client: Using mirror data for Solitaire game")
			if _pending_mirror_data.has("mirror_data"):
				local_game.new_game_mirror(_pending_mirror_data["mirror_data"])
			else:
				local_game.new_game(randi())
				print("No mirror data found, using random seed")
		elif mirror_mode_enabled and _pending_mirror_data.is_empty() and not network_manager.is_host:
			print("Client: Mirror mode enabled but no data yet, waiting...")
			# Don't create game yet, wait for mirror data
			return
		else:
			# No mirror mode or host creating game normally
			if network_manager.is_host:
				# Host already created the game in start_multiplayer_race() with proper initialization
				# Skip duplicate creation regardless of mirror mode setting
				print("Host: Game already created in start_multiplayer_race(), skipping duplicate creation")
			else:
				# Client without mirror data - create a random game
				local_game.new_game(randi())
				print("Creating normal game (mirror mode: ", mirror_mode_enabled, ", is_host: ", network_manager.is_host, ")")
		
		# Clear pending mirror data after use
		_pending_mirror_data.clear()
		
		# Only connect if not already connected
		if not local_game.game_completed.is_connected(_on_local_game_completed):
			local_game.game_completed.connect(_on_local_game_completed)
	
	print("DEBUG: Emitting race_started signal")
	race_started.emit()

func _on_local_game_completed() -> void:
	if local_player_finished:
		return
	
	local_player_finished = true
	var completion_time = (Time.get_ticks_msec() / 1000.0) - race_start_time  # Time elapsed in seconds
	
	if is_multiplayer:
		# Mark as completed and broadcast
		var local_player_id = network_manager.local_player_id
		player_statuses[local_player_id] = PlayerStatus.COMPLETED
		_broadcast_status_change(local_player_id, "completed")

		# Play win sound for winner
		if SoundManager:
			SoundManager.play_win()

		network_manager.report_race_completion(completion_time)

		# Get player name for the completion notification
		var players = network_manager.get_players()
		var player_name = players.get(local_player_id, {}).get("name", "You")

		# Notify that game has ended for everyone
		_end_multiplayer_race(local_player_id, player_name, completion_time)
	else:
		race_ended.emit(1, "You", completion_time)

func _on_race_completed(player_id: int, time: float) -> void:
	# Guard against double-processing
	if local_player_finished:
		return

	var players = network_manager.get_players()
	var player_name = "Unknown"

	if players.has(player_id):
		player_name = players[player_id].name

	# Mark as finished early to guard against re-entrancy
	if player_id == network_manager.local_player_id:
		local_player_finished = true

	# Update player status
	player_statuses[player_id] = PlayerStatus.COMPLETED

	# If this is not the local player, they lost
	if player_id != network_manager.local_player_id:
		# Play lose sound for non-winners
		if SoundManager:
			SoundManager.play_lose()

		# End the race for this player (this will emit race_ended with proper data)
		_end_multiplayer_race(player_id, player_name, time)
	
	if player_id == network_manager.local_player_id:
		local_player_finished = true

func _end_multiplayer_race(winner_id: int, winner_name: String = "", time: float = 0.0) -> void:
	"""End the multiplayer race for all players and show ready screen"""
	# Guard against multiple race_ended emissions
	if _race_ended:
		return
	_race_ended = true

	# If no winner name provided, look it up from players dictionary
	if winner_name == "":
		var players = network_manager.get_players()
		if players.has(winner_id):
			winner_name = players[winner_id].name
		else:
			winner_name = "Unknown"

	# Broadcast to all clients if we're the host
	if network_manager.is_host:
		network_manager.broadcast_race_ended(winner_id)

	# Signal to Main.gd to show ready screen with proper data
	race_ended.emit(winner_id, winner_name, time)

func _on_game_state_received(game_state: Dictionary) -> void:
	if local_game:
		_sync_game_state(game_state)

func _sync_game_state(game_state: Dictionary) -> void:
	pass

func send_local_progress() -> void:
	if not is_multiplayer or not local_game or local_player_finished:
		return
	
	var progress = _calculate_progress()
	network_manager.send_game_state({
		"player_id": network_manager.local_player_id,
		"progress": progress,
		"moves": local_game.get_moves_count(),
		"completed": local_game.is_completed()
	})
	
	player_progress_updated.emit(network_manager.local_player_id, progress)

func _calculate_progress() -> float:
	if not local_game:
		return 0.0
	
	var total_cards = 52
	var cards_in_foundations = 0
	
	for foundation in local_game.foundations:
		cards_in_foundations += foundation.size()
	
	return float(cards_in_foundations) / float(total_cards)

func get_discovered_games() -> Array:
	return await network_manager.discover_games()

func get_connected_players() -> Dictionary:
	return network_manager.get_players()

func leave_multiplayer_game() -> void:
	network_manager.leave_game()
	is_multiplayer = false
	
	if local_game:
		local_game.queue_free()
		local_game = null

func get_local_game() -> Game:
	return local_game

func is_host_player() -> bool:
	return network_manager.is_host

func check_player_status() -> void:
	"""Check if local player is jammed and update status"""
	if not is_multiplayer or not local_game:
		return
	
	var local_player_id = network_manager.local_player_id
	
	# Check if player completed
	if local_game.is_completed():
		if player_statuses.get(local_player_id) != PlayerStatus.COMPLETED:
			player_statuses[local_player_id] = PlayerStatus.COMPLETED
			_broadcast_status_change(local_player_id, "completed")
			player_status_changed.emit(local_player_id, "completed")
			_check_last_player_standing()
		return
	
	# Check if player is jammed
	if not local_game.has_valid_moves():
		if player_statuses.get(local_player_id) != PlayerStatus.JAMMED:
			player_statuses[local_player_id] = PlayerStatus.JAMMED
			_broadcast_status_change(local_player_id, "jammed")
			player_status_changed.emit(local_player_id, "jammed")
			_check_last_player_standing()
	else:
		if player_statuses.get(local_player_id) != PlayerStatus.PLAYING:
			player_statuses[local_player_id] = PlayerStatus.PLAYING
			_broadcast_status_change(local_player_id, "playing")
			player_status_changed.emit(local_player_id, "playing")

func _broadcast_status_change(player_id: int, status: String) -> void:
	"""Broadcast player status change to other players"""
	print("Broadcasting player status: Player ", player_id, " is now ", status)
	network_manager.broadcast_player_status(player_id, status)

func receive_player_status(player_id: int, status: String) -> void:
	"""Receive player status update from network"""
	print("Received status for player ", player_id, ": ", status)

	# Update player status
	match status:
		"playing":
			player_statuses[player_id] = PlayerStatus.PLAYING
		"jammed":
			player_statuses[player_id] = PlayerStatus.JAMMED
		"completed":
			player_statuses[player_id] = PlayerStatus.COMPLETED

	# Emit signal for UI updates
	player_status_changed.emit(player_id, status)

	# Check if this status change affects last player standing (e.g., opponent forfeits)
	_check_last_player_standing()
	
	# Check if this affects last player standing
	_check_last_player_standing()

func _check_last_player_standing() -> void:
	"""Check if only one player is still playing (others jammed or completed)"""
	var playing_count = 0
	var last_playing_id = -1
	
	for player_id in player_statuses:
		if player_statuses[player_id] == PlayerStatus.PLAYING:
			playing_count += 1
			last_playing_id = player_id
	
	# If only one player is still playing, notify them
	if playing_count == 1 and last_playing_id == network_manager.local_player_id:
		last_player_standing.emit(last_playing_id)
	
	# Only host should end the round when all players are done
	# Clients should wait for host to end the race
	if playing_count == 0 and network_manager.is_host:
		print("All players are jammed or completed - host ending round")
		_end_multiplayer_race(-1)  # -1 means no winner (all jammed)

func forfeit_player() -> void:
	"""Mark local player as forfeited (jammed)"""
	var local_player_id = network_manager.local_player_id
	player_statuses[local_player_id] = PlayerStatus.JAMMED
	_broadcast_status_change(local_player_id, "jammed")
	player_status_changed.emit(local_player_id, "jammed")
	_check_last_player_standing()

func set_player_ready(ready: bool) -> void:
	"""Set local player ready status for next round"""
	var local_player_id = network_manager.local_player_id
	players_ready[local_player_id] = ready
	
	# Broadcast to all players
	network_manager.broadcast_player_ready(local_player_id, ready)
	
	# Check if all players are ready
	_check_all_players_ready()

func receive_player_ready(player_id: int, ready: bool) -> void:
	"""Receive player ready status from network"""
	print("Player ", player_id, " ready status: ", ready)
	players_ready[player_id] = ready
	_check_all_players_ready()

func _on_player_disconnected_during_game(player_id: int) -> void:
	"""Handle player disconnect during an active game"""
	print("Player ", player_id, " disconnected during game - marking as jammed")
	# Mark the disconnected player as jammed so the race can end
	if is_multiplayer and player_statuses.has(player_id):
		player_statuses[player_id] = PlayerStatus.JAMMED
		_check_last_player_standing()

func receive_race_ended(data: Dictionary) -> void:
	"""Receive race ended notification from host"""
	var winner_id = data.get("winner_id", -1)
	print("MultiplayerGameManager: Received race ended - winner_id: ", winner_id)
	# End race on client side - this will properly emit race_ended with correct data
	_end_multiplayer_race(winner_id)

func receive_mirror_data(mirror_data: Dictionary) -> void:
	"""Receive mirror mode data from host"""
	# Get the game type from network settings (for clients) or local variable (for host)
	var game_type = current_game_type
	if not network_manager.is_host and NetworkManager.game_settings.has("game_type"):
		game_type = NetworkManager.game_settings["game_type"]
		
	print("MultiplayerGameManager received mirror data for game type: ", game_type)
	if game_type == "Sudoku":
		# Store mirror data for when Sudoku game is created
		_pending_mirror_data = mirror_data
		print("Stored mirror data for Sudoku game")
		
		# If client is waiting for Sudoku mirror data, create the game now
		if not network_manager.is_host and _pending_mirror_data.has("puzzle"):
			print("Client: Creating Sudoku game with received mirror data")
			# Trigger Sudoku game creation by calling Main's setup function
			var main_scene = get_tree().current_scene
			if main_scene and main_scene.has_method("_setup_multiplayer_sudoku"):
				# Set a flag to prevent double creation
				if main_scene.has_method("set_sudoku_mirror_mode"):
					main_scene.set_sudoku_mirror_mode(true)
					main_scene._setup_multiplayer_sudoku()
				else:
					print("ERROR: Could not find Main scene or set_sudoku_mirror_mode method")
			else:
				print("ERROR: Could not find Main scene or _setup_multiplayer_sudoku method")
	elif game_type == "Spider":
		# Unwrap mirror data if it's in the {"game_type": "Spider", "mirror_data": {...}} format
		var actual_mirror_data = mirror_data
		if mirror_data.has("mirror_data"):
			actual_mirror_data = mirror_data["mirror_data"]

		# Store mirror data for when Spider game is created (client side)
		_pending_mirror_data = actual_mirror_data
		print("Stored mirror data for Spider game")

		# If client is waiting for Spider mirror data, create the game now
		if not network_manager.is_host and _pending_mirror_data.has("deck"):
			print("Client: Creating Spider game with received mirror data")
			# Trigger Spider game creation by calling Main's setup function
			var main_scene = get_tree().current_scene
			if main_scene and main_scene.has_method("_setup_multiplayer_spider"):
				# Set a flag to prevent double creation
				if main_scene.has_method("set_spider_mirror_mode"):
					main_scene.set_spider_mirror_mode(true)
					main_scene._setup_multiplayer_spider()
				else:
					print("ERROR: Could not find Main scene or set_spider_mirror_mode method")
			else:
				print("ERROR: Could not find Main scene or _setup_multiplayer_spider method")
	elif game_type == "Solitaire":
		# Apply mirror data to Solitaire game
		if local_game and mirror_data.has("mirror_data"):
			print("Applying mirror data to existing Solitaire game")
			local_game.new_game_mirror(mirror_data["mirror_data"])
			# Debug: Check if arrays are populated
			print("DEBUG: After new_game_mirror - tableau size: ", local_game.tableau.size())
			print("DEBUG: After new_game_mirror - stock size: ", local_game.stock.size())
			print("DEBUG: After new_game_mirror - waste size: ", local_game.waste.size())
			print("DEBUG: After new_game_mirror - foundations size: ", local_game.foundations.size())
			# Need to re-render the board to show the new layout
			print("DEBUG: Attempting to re-render board after mirror data (existing game)")
			# Try to find the board in the scene tree
			var main_scene = get_tree().current_scene
			if main_scene:
				print("DEBUG: Main scene found: ", main_scene.name)
				var board = main_scene.get_node_or_null("Board")
				if board:
					print("DEBUG: Board found, calling render() (existing game)")
					# Update the board's game reference to point to the updated game
					board.game = local_game
					print("DEBUG: Updated board's game reference")
					board.render()
					print("Re-rendered board with mirror layout (existing game)")
				else:
					print("DEBUG: Board node not found in main scene (existing game)")
			else:
				print("DEBUG: Main scene not found (existing game)")
		else:
			# Game not created yet, store for later and create it now
			_pending_mirror_data = mirror_data
			print("Stored mirror data and creating Solitaire game now")

			# Create the game now that we have mirror data
			if not local_game:
				local_game = Game.new()
				add_child(local_game)

			if _pending_mirror_data.has("mirror_data"):
				local_game.new_game_mirror(_pending_mirror_data["mirror_data"])
				print("Created Solitaire game with mirror data")

				# Re-render the board to show the new layout
				print("DEBUG: Attempting to re-render board after mirror data")
				# Try to find the board in the scene tree
				var main_scene = get_tree().current_scene
				if main_scene:
					print("DEBUG: Main scene found: ", main_scene.name)
					var board = main_scene.get_node_or_null("Board")
					if board:
						print("DEBUG: Board found, calling render()")
						board.render()
						print("Re-rendered board with mirror layout")
					else:
						print("DEBUG: Board node not found in main scene")
				else:
					print("DEBUG: Main scene not found")
			
			# Clear pending mirror data after use
			_pending_mirror_data.clear()
			
			# Only connect if not already connected
			if not local_game.game_completed.is_connected(_on_local_game_completed):
				local_game.game_completed.connect(_on_local_game_completed)
			
			# Emit race_started signal since we just created the game
			print("DEBUG: Emitting race_started signal after mirror data received")
			race_started.emit()

func _check_all_players_ready() -> void:
	"""Check if all players are ready for next round"""
	var all_ready = true
	var total_players = network_manager.players.size()

	# Require at least 2 players to start a new round
	if total_players < 2:
		print("Not enough players for new round: ", total_players, "/2")
		return

	# Clean up stale player IDs that are no longer connected
	var stale_players = []
	for player_id in players_ready:
		if not network_manager.players.has(player_id):
			stale_players.append(player_id)
	for player_id in stale_players:
		players_ready.erase(player_id)

	# Also clean up stale players from network_manager that disconnected before registering
	stale_players.clear()
	for player_id in network_manager.players:
		if not player_statuses.has(player_id):
			stale_players.append(player_id)
	for player_id in stale_players:
		network_manager.players.erase(player_id)

	# Update total_players after cleanup
	total_players = network_manager.players.size()

	print("Checking ready status: ", players_ready.size(), "/", total_players, " players")

	# Only check players that are actually in the game
	for player_id in network_manager.players:
		if not players_ready.get(player_id, false):
			all_ready = false
			print("  Player ", player_id, " not ready yet")
			break

	if all_ready:
		print("All players ready! Starting new round...")
		all_players_ready.emit()
		_start_new_round()

func _start_new_round() -> void:
	"""Start a new round after all players are ready"""
	players_ready.clear()
	player_statuses.clear()
	local_player_finished = false
	_race_ended = false  # Reset for new round
	_pending_mirror_data.clear()

	# Free the previous game so start_multiplayer_race() starts fresh
	if local_game:
		local_game.queue_free()
		local_game = null

	if network_manager.is_host:
		# Give clients time to settle after receiving RACE_ENDED before sending GAME_START
		await get_tree().create_timer(0.5).timeout
		# Re-run the full race setup: generates a new seed, handles mirror mode,
		# broadcasts GAME_SETTINGS + GAME_START, and (if mirrored) sends MIRROR_DATA.
		start_multiplayer_race()
	# Clients receive GAME_SETTINGS + GAME_START from the host broadcast,
	# which triggers _on_race_started (and receive_mirror_data for mirror mode).

	print("New round initiated!")

func set_game_type(game_type: String) -> void:
	"""Set the current game type for multiplayer session"""
	current_game_type = game_type
	print("MultiplayerGameManager: Game type set to ", game_type)

func get_game_type() -> String:
	return current_game_type

func set_sudoku_puzzle(puzzle_state: Dictionary) -> void:
	"""Set the Sudoku puzzle state (host generates, clients receive)"""
	sudoku_puzzle_state = puzzle_state
	print("MultiplayerGameManager: Sudoku puzzle state set")

func get_sudoku_puzzle() -> Dictionary:
	return sudoku_puzzle_state

func get_local_player_id() -> int:
	return network_manager.local_player_id if is_multiplayer else 1
