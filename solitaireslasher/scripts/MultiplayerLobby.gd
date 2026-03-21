extends Control

signal lobby_closed
signal game_started

@onready var player_list: VBoxContainer
@onready var ip_input: LineEdit
@onready var join_button: Button
@onready var start_button: Button
@onready var leave_button: Button
@onready var status_label: Label
@onready var host_label: Label

var is_host: bool = false

func _ready() -> void:
	_create_ui()
	_connect_signals()

func _create_ui() -> void:
	# Main container
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 50)
	margin.add_theme_constant_override("margin_right", 50)
	margin.add_theme_constant_override("margin_top", 50)
	margin.add_theme_constant_override("margin_bottom", 50)
	add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	margin.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "Multiplayer Lobby"
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)
	
	# Host/Join status
	host_label = Label.new()
	host_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(host_label)
	
	# Status label
	status_label = Label.new()
	status_label.text = "Waiting for players..."
	vbox.add_child(status_label)
	
	# IP Entry section (for joining)
	var ip_section = HBoxContainer.new()
	ip_section.add_theme_constant_override("separation", 10)
	vbox.add_child(ip_section)
	
	var ip_label = Label.new()
	ip_label.text = "Host IP:"
	ip_section.add_child(ip_label)
	
	ip_input = LineEdit.new()
	ip_input.placeholder_text = "Enter host IP address (e.g., 192.168.1.100)"
	ip_input.custom_minimum_size = Vector2(300, 0)
	ip_section.add_child(ip_input)
	
	join_button = Button.new()
	join_button.text = "Join Game"
	join_button.pressed.connect(_on_join_pressed)
	ip_section.add_child(join_button)
	
	# Player list
	var players_label = Label.new()
	players_label.text = "Players:"
	players_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(players_label)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	vbox.add_child(scroll)
	
	player_list = VBoxContainer.new()
	scroll.add_child(player_list)
	
	# Buttons
	var button_box = HBoxContainer.new()
	button_box.add_theme_constant_override("separation", 10)
	vbox.add_child(button_box)
	
	start_button = Button.new()
	start_button.text = "Start Game"
	start_button.pressed.connect(_on_start_pressed)
	start_button.visible = false
	button_box.add_child(start_button)
	
	leave_button = Button.new()
	leave_button.text = "Leave Lobby"
	leave_button.pressed.connect(_on_leave_pressed)
	button_box.add_child(leave_button)

func _connect_signals() -> void:
	if NetworkManager:
		NetworkManager.player_connected.connect(_on_player_connected)
		NetworkManager.player_disconnected.connect(_on_player_disconnected)

func setup_as_host(player_name: String) -> void:
	is_host = true
	host_label.text = "You are hosting"
	status_label.text = "Your IP: " + _get_local_ip() + " | Port: 7000"
	ip_input.visible = false
	join_button.visible = false
	start_button.visible = true
	_add_player(NetworkManager.local_player_id, player_name + " (You - Host)")

func setup_as_client(player_name: String) -> void:
	is_host = false
	host_label.text = "Connected as client"
	status_label.text = "Connected to host"
	ip_input.visible = false
	join_button.visible = false
	start_button.visible = false
	_add_player(NetworkManager.local_player_id, player_name + " (You)")

func _get_local_ip() -> String:
	var addresses = IP.get_local_addresses()
	for address in addresses:
		# Filter out localhost and IPv6
		if not address.begins_with("127.") and not address.contains(":"):
			return address
	return "Unknown"

func _add_player(player_id: int, player_name: String) -> void:
	var player_label = Label.new()
	player_label.text = "• " + player_name
	player_label.name = "player_" + str(player_id)
	player_list.add_child(player_label)

func _remove_player(player_id: int) -> void:
	var player_node = player_list.get_node_or_null("player_" + str(player_id))
	if player_node:
		player_node.queue_free()

func _on_player_connected(player_id: int, player_name: String) -> void:
	_add_player(player_id, player_name)
	status_label.text = "Player joined: " + player_name

func _on_player_disconnected(player_id: int) -> void:
	_remove_player(player_id)
	status_label.text = "Player left"

func _on_join_pressed() -> void:
	var host_ip = ip_input.text.strip_edges()
	if host_ip.is_empty():
		status_label.text = "Please enter a host IP address"
		return
	
	status_label.text = "Connecting to " + host_ip + "..."
	var player_name = "Player" + str(randi() % 1000)
	
	if NetworkManager.join_game(host_ip, player_name):
		setup_as_client(player_name)
	else:
		status_label.text = "Failed to connect to " + host_ip

func _on_start_pressed() -> void:
	if is_host:
		NetworkManager.start_race()
		game_started.emit()

func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	lobby_closed.emit()

func update_player_list(players: Dictionary) -> void:
	# Clear existing players
	for child in player_list.get_children():
		child.queue_free()
	
	# Add all players
	for player_id in players:
		var player_data = players[player_id]
		var suffix = ""
		if player_id == NetworkManager.local_player_id:
			suffix = " (You)"
			if is_host:
				suffix += " - Host"
		elif player_id == 1 and not is_host:
			suffix = " (Host)"
		
		_add_player(player_id, player_data.name + suffix)
