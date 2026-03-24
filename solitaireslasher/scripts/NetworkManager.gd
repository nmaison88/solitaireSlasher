extends Node

signal player_connected(player_id: int, player_name: String)
signal player_disconnected(player_id: int)
signal game_started
signal race_completed(player_id: int, time: float)
signal game_state_received(game_state: Dictionary)
signal game_settings_received(game_settings: Dictionary)

const DEFAULT_PORT = 7777  # Changed from 7000 to avoid conflicts with other applications
const MAX_PLAYERS = 8
const BROADCAST_INTERVAL = 2.0

var multiplayer_peer: ENetMultiplayerPeer
var is_host: bool = false
var players: Dictionary = {}
var local_player_id: int = 1
var game_session_active: bool = false
var broadcast_timer: Timer
var discovery_server: UDPServer
var custom_port: int = DEFAULT_PORT  # Can be overridden via command line (for hosting)
var connect_port: int = DEFAULT_PORT  # Port to connect to when joining (always use host's port)

enum MessageType {
	PLAYER_JOIN,
	PLAYER_LEAVE,
	GAME_START,
	GAME_STATE,
	RACE_COMPLETE,
	SESSION_INFO,
	PLAYER_STATUS,
	PLAYER_READY,
	GAME_SETTINGS
}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Parse command line arguments for custom port
	_parse_command_line_args()
	
	_setup_broadcast()

func _parse_command_line_args() -> void:
	"""Parse command line arguments to allow custom port for testing"""
	var args = OS.get_cmdline_args()
	for arg in args:
		if arg.begins_with("--port="):
			var port_str = arg.split("=")[1]
			custom_port = int(port_str)
			print("Using custom port: ", custom_port)
			break

func _setup_broadcast() -> void:
	broadcast_timer = Timer.new()
	broadcast_timer.wait_time = BROADCAST_INTERVAL
	broadcast_timer.timeout.connect(_broadcast_session)
	add_child(broadcast_timer)

func host_game(player_name: String) -> bool:
	# Clean up any existing connection first
	if multiplayer_peer:
		multiplayer_peer.close()
		multiplayer_peer = null
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
	
	multiplayer_peer = ENetMultiplayerPeer.new()
	var error = multiplayer_peer.create_server(custom_port, MAX_PLAYERS)
	
	if error != OK:
		print("Failed to create server: ", error)
		print("Error code 20 usually means port is already in use.")
		print("To test multiplayer on same machine, use: --port=7778 for second instance")
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
	print("Hosting game on port ", custom_port)
	return true

func join_game(host_ip: String, player_name: String) -> bool:
	multiplayer_peer = ENetMultiplayerPeer.new()
	# Always connect to DEFAULT_PORT (host's port), not custom_port
	var error = multiplayer_peer.create_client(host_ip, DEFAULT_PORT)
	
	if error != OK:
		print("Failed to create client: ", error)
		print("Make sure host is running on port ", DEFAULT_PORT)
		return false
	
	print("Attempting to connect to ", host_ip, ":", DEFAULT_PORT)
	
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

func start_race(game_settings: Dictionary = {}) -> void:
	if not is_host:
		return
	
	print("DEBUG: start_race called - is_host: ", is_host, ", settings: ", game_settings)
	game_session_active = true
	
	# Send game settings first if provided
	if not game_settings.is_empty():
		print("DEBUG: Broadcasting GAME_SETTINGS")
		_broadcast_message(MessageType.GAME_SETTINGS, game_settings)
	
	print("DEBUG: Broadcasting GAME_START")
	_broadcast_message(MessageType.GAME_START, {})
	game_started.emit()

func send_game_state(game_state: Dictionary) -> void:
	if not game_session_active:
		return
	
	_broadcast_message(MessageType.GAME_STATE, game_state)

func report_race_completion(time: float) -> void:
	if not game_session_active:
		return
	
	_broadcast_message(MessageType.RACE_COMPLETE, {
		"player_id": local_player_id,
		"time": time
	})

func broadcast_player_status(player_id: int, status: String) -> void:
	"""Broadcast player status change to all players"""
	_broadcast_message(MessageType.PLAYER_STATUS, {
		"player_id": player_id,
		"status": status
	})

func broadcast_player_ready(player_id: int, ready: bool) -> void:
	"""Broadcast player ready status for next round"""
	_broadcast_message(MessageType.PLAYER_READY, {
		"player_id": player_id,
		"ready": ready
	})

func _broadcast_message(message_type: MessageType, data: Dictionary) -> void:
	var message = {
		"type": message_type,
		"data": data
	}
	
	rpc("receive_message", message)

@rpc("any_peer", "reliable")
func receive_message(message: Dictionary) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	
	print("DEBUG: receive_message - sender_id: ", sender_id, ", is_host: ", is_host, ", message_type: ", message.type)
	
	# Host shouldn't process its own broadcast messages
	if is_host and sender_id == 1:
		print("DEBUG: Host ignoring own message")
		return
	
	var message_type = message.type
	var data = message.data
	
	match message_type:
		MessageType.PLAYER_JOIN:
			_handle_player_join(data)
		MessageType.PLAYER_LEAVE:
			_handle_player_leave(data)
		MessageType.GAME_SETTINGS:
			_handle_game_settings(data)
		MessageType.GAME_START:
			_handle_game_start(data)
		MessageType.GAME_STATE:
			_handle_game_state(data)
		MessageType.RACE_COMPLETE:
			_handle_race_complete(data)
		MessageType.PLAYER_STATUS:
			_handle_player_status(data)
		MessageType.PLAYER_READY:
			_handle_player_ready(data)

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

func _handle_game_settings(data: Dictionary) -> void:
	print("Received game settings from host: ", data)
	game_settings_received.emit(data)

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

func _handle_player_status(data: Dictionary) -> void:
	"""Handle player status updates from other players"""
	var player_id = data.player_id
	var status = data.status
	print("Received player status update: Player ", player_id, " is now ", status)
	
	# Forward to MultiplayerGameManager
	if MultiplayerGameManager:
		MultiplayerGameManager.receive_player_status(player_id, status)

func _handle_player_ready(data: Dictionary) -> void:
	"""Handle player ready status for next round"""
	var player_id = data.player_id
	var ready = data.ready
	print("Received player ready update: Player ", player_id, " ready: ", ready)
	
	# Forward to MultiplayerGameManager
	if MultiplayerGameManager:
		MultiplayerGameManager.receive_player_ready(player_id, ready)

func _on_peer_connected(id: int) -> void:
	print("✓ Peer connected: ", id)
	print("  Total peers now: ", multiplayer.get_peers().size() + 1)
	# Send player info to the new peer
	rpc_id(id, "_receive_player_info", local_player_id, players[local_player_id].name)

@rpc("any_peer", "reliable")
func _receive_player_info(player_id: int, player_name: String) -> void:
	"""Receive player info from a peer"""
	print("Received player info: ", player_name, " (ID: ", player_id, ")")
	if not players.has(player_id):
		players[player_id] = {
			"name": player_name,
			"ready": false,
			"completed": false,
			"completion_time": 0.0
		}
		player_connected.emit(player_id, player_name)

func _on_peer_disconnected(peer_id: int) -> void:
	players.erase(peer_id)
	player_disconnected.emit(peer_id)

func _on_connected_to_server() -> void:
	print("✓ Successfully connected to server!")
	print("  Local player ID: ", local_player_id)
	var join_data = {
		"player_id": local_player_id,
		"player_name": players[local_player_id].name
	}
	rpc_id(1, "receive_message", {
		"type": MessageType.PLAYER_JOIN,
		"data": join_data
	})

func _on_connection_failed() -> void:
	print("✗ Connection to server failed")
	print("  Check that host is running and port ", DEFAULT_PORT, " is accessible")

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
		discovery_server.stop()  # UDPServer uses stop() not close()

func get_players() -> Dictionary:
	return players.duplicate()

func is_game_active() -> bool:
	return game_session_active
