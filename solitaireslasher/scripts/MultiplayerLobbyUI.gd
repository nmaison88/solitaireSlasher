extends Control
class_name MultiplayerLobbyUI

signal start_game_requested
signal leave_lobby_requested

var multiplayer_manager: MultiplayerGameManager
var player_list: ItemList
var start_button: Button
var leave_button: Button
var status_label: Label

func _ready() -> void:
	_setup_ui()

func _setup_ui() -> void:
	# Create UI elements
	player_list = ItemList.new()
	player_list.size = Vector2(300, 200)
	add_child(player_list)
	
	start_button = Button.new()
	start_button.text = "Start Race"
	start_button.pressed.connect(_on_start_pressed)
	add_child(start_button)
	
	leave_button = Button.new()
	leave_button.text = "Leave Lobby"
	leave_button.pressed.connect(_on_leave_pressed)
	add_child(leave_button)
	
	status_label = Label.new()
	status_label.text = "Waiting for players..."
	add_child(status_label)
	
	# Position elements
	player_list.position = Vector2(50, 50)
	start_button.position = Vector2(50, 270)
	leave_button.position = Vector2(50, 310)
	status_label.position = Vector2(50, 350)
	
	# Initially disable start button for non-hosts
	start_button.disabled = true

func set_multiplayer_manager(value: MultiplayerGameManager) -> void:
	multiplayer_manager = value
	if multiplayer_manager:
		multiplayer_manager.network_manager.player_connected.connect(_on_player_connected)
		multiplayer_manager.network_manager.player_disconnected.connect(_on_player_disconnected)
		
		# Enable start button for host
		if multiplayer_manager.is_host_player():
			start_button.disabled = false
		
		_refresh_player_list()

func _on_player_connected(player_id: int, player_name: String) -> void:
	_refresh_player_list()
	status_label.text = "Player %s joined the game!" % player_name

func _on_player_disconnected(player_id: int) -> void:
	_refresh_player_list()
	status_label.text = "Player %d left the game." % player_id

func _refresh_player_list() -> void:
	if not multiplayer_manager:
		return
	
	player_list.clear()
	var players = multiplayer_manager.get_connected_players()
	
	for player_id in players:
		var player_data = players[player_id]
		var display_text = player_data.name
		if player_id == multiplayer_manager.get_local_player_id():
			display_text += " (You)"
		if multiplayer_manager.is_host_player() and player_id == multiplayer_manager.get_local_player_id():
			display_text += " [Host]"
		
		player_list.add_item(display_text)

func _on_start_pressed() -> void:
	start_game_requested.emit()

func _on_leave_pressed() -> void:
	leave_lobby_requested.emit()
