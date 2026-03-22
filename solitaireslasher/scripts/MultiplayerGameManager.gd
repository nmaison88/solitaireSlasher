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
var player_statuses: Dictionary = {}  # player_id -> PlayerStatus
var players_ready: Dictionary = {}  # player_id -> bool (for next round)

func _ready() -> void:
	# NetworkManager is an autoload singleton, don't create a new instance
	network_manager = NetworkManager
	
	network_manager.game_started.connect(_on_race_started)
	network_manager.race_completed.connect(_on_race_completed)
	network_manager.game_state_received.connect(_on_game_state_received)

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

func start_local_game() -> void:
	print("MultiplayerGameManager: Starting local game")
	# Don't reset is_multiplayer here - it's already set by host_multiplayer_game() or join_multiplayer_game()
	# Only set to false if we're truly in single player mode (not connected to network)
	if not network_manager.is_host and network_manager.players.size() <= 1:
		is_multiplayer = false
	
	local_game = Game.new()
	add_child(local_game)
	local_game.new_game()
	local_game.game_completed.connect(_on_local_game_completed)
	print("Local game created and initialized (multiplayer: ", is_multiplayer, ")")

func start_multiplayer_race() -> void:
	if not is_multiplayer or not network_manager.is_host:
		return
	
	local_game = Game.new()
	add_child(local_game)
	
	var seed = randi()
	local_game.new_game(seed)
	
	network_manager.start_race()

func _on_race_started() -> void:
	race_start_time = Time.get_time_dict_from_system().hour * 3600 + Time.get_time_dict_from_system().minute * 60 + Time.get_time_dict_from_system().second
	local_player_finished = false
	
	if not local_game:
		local_game = Game.new()
		add_child(local_game)
	
	local_game.new_game(randi())
	local_game.game_completed.connect(_on_local_game_completed)
	race_started.emit()

func _on_local_game_completed() -> void:
	if local_player_finished:
		return
	
	local_player_finished = true
	var completion_time = Time.get_time_dict_from_system().hour * 3600 + Time.get_time_dict_from_system().minute * 60 + Time.get_time_dict_from_system().second - race_start_time
	
	if is_multiplayer:
		# Mark as completed and broadcast
		var local_player_id = network_manager.local_player_id
		player_statuses[local_player_id] = PlayerStatus.COMPLETED
		_broadcast_status_change(local_player_id, "completed")
		
		# Play win sound for winner
		if SoundManager:
			SoundManager.play_win()
		
		network_manager.report_race_completion(completion_time)
		
		# Notify that game has ended for everyone
		_end_multiplayer_race(local_player_id)
	else:
		race_ended.emit(1, "You", completion_time)

func _on_race_completed(player_id: int, time: float) -> void:
	var players = network_manager.get_players()
	var player_name = "Unknown"
	
	if players.has(player_id):
		player_name = players[player_id].name
	
	# Update player status
	player_statuses[player_id] = PlayerStatus.COMPLETED
	
	# If this is not the local player, they lost
	if player_id != network_manager.local_player_id:
		# Play lose sound for non-winners
		if SoundManager:
			SoundManager.play_lose()
		
		# End the race for this player
		_end_multiplayer_race(player_id)
	
	race_ended.emit(player_id, player_name, time)
	
	if player_id == network_manager.local_player_id:
		local_player_finished = true

func _end_multiplayer_race(winner_id: int) -> void:
	"""End the multiplayer race for all players and show ready screen"""
	# Signal to Main.gd to show ready screen
	race_ended.emit(winner_id, "", 0.0)

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
	return network_manager.discover_games()

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
	
	# If no players are still playing (all jammed or completed), end the round
	if playing_count == 0:
		print("All players are jammed or completed - ending round")
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

func _check_all_players_ready() -> void:
	"""Check if all players are ready for next round"""
	var all_ready = true
	var total_players = network_manager.players.size()
	
	print("Checking ready status: ", players_ready.size(), "/", total_players, " players")
	
	for player_id in network_manager.players:
		if not players_ready.get(player_id, false):
			all_ready = false
			print("  Player ", player_id, " not ready yet")
			break
	
	if all_ready and total_players > 0:
		print("All players ready! Starting new round...")
		all_players_ready.emit()
		_start_new_round()

func _start_new_round() -> void:
	"""Start a new round after all players are ready"""
	# Reset ready status
	players_ready.clear()
	player_statuses.clear()
	
	# Start new game
	if network_manager.is_host:
		network_manager.start_race()
	
	# Reset local game
	if local_game:
		local_game.queue_free()
		local_game = null
	
	local_game = Game.new()
	add_child(local_game)
	local_game.new_game()
	local_game.game_completed.connect(_on_local_game_completed)
	
	print("New round started!")

func get_local_player_id() -> int:
	return network_manager.local_player_id if is_multiplayer else 1
