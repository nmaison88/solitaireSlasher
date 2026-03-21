extends Node

signal player_connected(player_id: int, player_name: String)
signal player_disconnected(player_id: int)
signal game_started
signal race_completed(player_id: int, time: float)
signal game_state_received(game_state: Dictionary)

const DEFAULT_PORT = 7000
const MAX_PLAYERS = 8
const BROADCAST_INTERVAL = 2.0

var multiplayer_peer: ENetMultiplayerPeer
var is_host: bool = false
var players: Dictionary = {}
var local_player_id: int = 1
var game_session_active: bool = false
var broadcast_timer: Timer
var discovery_server: UDPServer

enum MessageType {
	PLAYER_JOIN,
	PLAYER_LEAVE,
	GAME_START,
	GAME_STATE,
	RACE_COMPLETE,
	SESSION_INFO
}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	_setup_broadcast()

func _setup_broadcast() -> void:
	broadcast_timer = Timer.new()
	broadcast_timer.wait_time = BROADCAST_INTERVAL
	broadcast_timer.timeout.connect(_broadcast_session)
	add_child(broadcast_timer)

func host_game(player_name: String) -> bool:
	multiplayer_peer = ENetMultiplayerPeer.new()
	var error = multiplayer_peer.create_server(DEFAULT_PORT, MAX_PLAYERS)
	
	if error != OK:
		print("Failed to create server: ", error)
		return false
	
	multiplayer.multiplayer_peer = multiplayer_peer
	is_host = true
	local_player_id = multiplayer.get_unique_id()
	
	players[local_player_id] = {
		"name": player_name,
		"ready": false,
		"completed": false,
		"completion_time": 0.0
	}
	
	_setup_discovery_server()
	broadcast_timer.start()
	print("Hosting game on port ", DEFAULT_PORT)
	return true

func join_game(host_ip: String, player_name: String) -> bool:
	multiplayer_peer = ENetMultiplayerPeer.new()
	var error = multiplayer_peer.create_client(host_ip, DEFAULT_PORT)
	
	if error != OK:
		print("Failed to create client: ", error)
		return false
	
	multiplayer.multiplayer_peer = multiplayer_peer
	local_player_id = multiplayer.get_unique_id()
	
	players[local_player_id] = {
		"name": player_name,
		"ready": false,
		"completed": false,
		"completion_time": 0.0
	}
	
	print("Connecting to host at ", host_ip)
	return true

func _setup_discovery_server() -> void:
	discovery_server = UDPServer.new()
	discovery_server.listen(DEFAULT_PORT + 1, "0.0.0.0")
	print("Discovery server listening on port ", DEFAULT_PORT + 1)

func _broadcast_session() -> void:
	if not is_host or not discovery_server:
		return
	
	discovery_server.poll()
	var peer = PacketPeerUDP.new()
	peer.set_broadcast_enabled(true)
	
	var session_data = {
		"type": MessageType.SESSION_INFO,
		"host_name": players[local_player_id].name,
		"player_count": players.size(),
		"port": DEFAULT_PORT
	}
	
	var json_string = JSON.stringify(session_data)
	var packet = json_string.to_utf8_buffer()
	peer.set_dest_address("255.255.255.255", DEFAULT_PORT + 1)
	peer.put_packet(packet)

func discover_games() -> Array:
	var udp_peer = PacketPeerUDP.new()
	udp_peer.set_broadcast_enabled(true)
	udp_peer.listen(DEFAULT_PORT + 1, "0.0.0.0")
	
	var discovered_games = []
	var start_time = Time.get_time_dict_from_system().hour * 3600 + Time.get_time_dict_from_system().minute * 60 + Time.get_time_dict_from_system().second
	
	while Time.get_time_dict_from_system().hour * 3600 + Time.get_time_dict_from_system().minute * 60 + Time.get_time_dict_from_system().second - start_time < 3.0:  # Search for 3 seconds
		udp_peer.poll()
		if udp_peer.get_available_packet_count() > 0:
			var packet = udp_peer.get_packet()
			var json_string = packet.get_string_from_utf8()
			var json = JSON.new()
			var parse_result = json.parse(json_string)
			
			if parse_result == OK:
				var data = json.data
				if data.has("type") and data.type == MessageType.SESSION_INFO:
					discovered_games.append({
						"host_ip": udp_peer.get_packet_ip(),
						"host_name": data.host_name,
						"player_count": data.player_count,
						"port": data.port
					})
	
	udp_peer.close()
	return discovered_games

func start_race() -> void:
	if not is_host:
		return
	
	game_session_active = true
	_broadcast_message(MessageType.GAME_START, {})
	game_started.emit()

func send_game_state(game_state: Dictionary) -> void:
	if not game_session_active:
		return
	
	_broadcast_message(MessageType.GAME_STATE, game_state)

func report_race_completion(completion_time: float) -> void:
	players[local_player_id].completed = true
	players[local_player_id].completion_time = completion_time
	
	_broadcast_message(MessageType.RACE_COMPLETE, {
		"player_id": local_player_id,
		"time": completion_time
	})
	
	race_completed.emit(local_player_id, completion_time)

func _broadcast_message(message_type: MessageType, data: Dictionary) -> void:
	var message = {
		"type": message_type,
		"data": data
	}
	
	rpc("receive_message", message)

@rpc("any_peer", "reliable")
func receive_message(message: Dictionary) -> void:
	var message_type = message.type
	var data = message.data
	
	match message_type:
		MessageType.PLAYER_JOIN:
			_handle_player_join(data)
		MessageType.PLAYER_LEAVE:
			_handle_player_leave(data)
		MessageType.GAME_START:
			_handle_game_start(data)
		MessageType.GAME_STATE:
			_handle_game_state(data)
		MessageType.RACE_COMPLETE:
			_handle_race_complete(data)

func _handle_player_join(data: Dictionary) -> void:
	var player_id = data.player_id
	var player_name = data.player_name
	
	players[player_id] = {
		"name": player_name,
		"ready": false,
		"completed": false,
		"completion_time": 0.0
	}
	
	player_connected.emit(player_id, player_name)

func _handle_player_leave(data: Dictionary) -> void:
	var player_id = data.player_id
	players.erase(player_id)
	player_disconnected.emit(player_id)

func _handle_game_start(data: Dictionary) -> void:
	game_session_active = true
	game_started.emit()

func _handle_game_state(data: Dictionary) -> void:
	game_state_received.emit(data)

func _handle_race_complete(data: Dictionary) -> void:
	var player_id = data.player_id
	var time = data.time
	
	if players.has(player_id):
		players[player_id].completed = true
		players[player_id].completion_time = time
	
	race_completed.emit(player_id, time)

func _on_peer_connected(peer_id: int) -> void:
	if is_host:
		var player_data = {
			"player_id": peer_id,
			"player_name": players[local_player_id].name
		}
		rpc_id(peer_id, "receive_message", {
			"type": MessageType.PLAYER_JOIN,
			"data": player_data
		})

func _on_peer_disconnected(peer_id: int) -> void:
	players.erase(peer_id)
	player_disconnected.emit(peer_id)

func _on_connected_to_server() -> void:
	var join_data = {
		"player_id": local_player_id,
		"player_name": players[local_player_id].name
	}
	rpc_id(1, "receive_message", {
		"type": MessageType.PLAYER_JOIN,
		"data": join_data
	})

func _on_connection_failed() -> void:
	print("Failed to connect to server")

func _on_server_disconnected() -> void:
	print("Disconnected from server")
	game_session_active = false

func leave_game() -> void:
	if multiplayer_peer:
		multiplayer_peer.close()
	
	players.clear()
	game_session_active = false
	is_host = false
	
	if broadcast_timer:
		broadcast_timer.stop()
	
	if discovery_server:
		discovery_server.close()

func get_players() -> Dictionary:
	return players.duplicate()

func is_game_active() -> bool:
	return game_session_active
