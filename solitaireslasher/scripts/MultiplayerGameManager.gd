extends Node

signal race_started
signal race_ended(winner_id: int, winner_name: String, time: float)
signal player_progress_updated(player_id: int, progress: float)

var network_manager: NetworkManager
var local_game: Game
var is_multiplayer: bool = false
var race_start_time: float = 0.0
var local_player_finished: bool = false

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
	is_multiplayer = false
	local_game = Game.new()
	add_child(local_game)
	local_game.new_game()
	local_game.game_completed.connect(_on_local_game_completed)
	print("Local game created and initialized")

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
		network_manager.report_race_completion(completion_time)
	else:
		race_ended.emit(1, "You", completion_time)

func _on_race_completed(player_id: int, time: float) -> void:
	var players = network_manager.get_players()
	var player_name = "Unknown"
	
	if players.has(player_id):
		player_name = players[player_id].name
	
	race_ended.emit(player_id, player_name, time)
	
	if player_id == network_manager.local_player_id:
		local_player_finished = true

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
	return is_multiplayer and network_manager.is_host

func get_local_player_id() -> int:
	return network_manager.local_player_id if is_multiplayer else 1
