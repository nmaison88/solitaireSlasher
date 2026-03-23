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
var players: Dictionary = {}
var client_player_name: String = ""
var ip_helper: Node
var local_ip_label: Label
var public_ip_label: Label
var port_forward_label: Label

func _ready() -> void:
	# Load and setup IP helper
	var ip_helper_script = preload("res://scripts/IPHelper.gd")
	ip_helper = ip_helper_script.new()
	add_child(ip_helper)
	ip_helper.public_ip_received.connect(_on_public_ip_received)
	ip_helper.public_ip_failed.connect(_on_public_ip_failed)
	
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
	
	# Add scroll container to ensure all content is accessible
	var scroll_outer = ScrollContainer.new()
	scroll_outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(scroll_outer)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.size_flags_horizontal = Control.SIZE_FILL
	scroll_outer.add_child(vbox)
	
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
	ip_input.placeholder_text = "Enter host IP (LAN: 192.168.x.x or Internet: public IP)"
	ip_input.custom_minimum_size = Vector2(400, 0)
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
		NetworkManager.game_started.connect(_on_network_game_started)

func setup_as_host(player_name: String) -> void:
	is_host = true
	host_label.text = "You are hosting"
	
	# Create IP info section for host
	var ip_info_container = VBoxContainer.new()
	ip_info_container.name = "IPInfoContainer"
	
	# Local IP (for LAN play)
	local_ip_label = Label.new()
	local_ip_label.text = "Local IP (LAN): " + ip_helper.get_local_ip() + " | Port: 7777"
	local_ip_label.add_theme_font_size_override("font_size", 16)
	ip_info_container.add_child(local_ip_label)
	
	# Public IP (for internet play) - will be fetched
	public_ip_label = Label.new()
	public_ip_label.text = "Public IP (Internet): Fetching..."
	public_ip_label.add_theme_font_size_override("font_size", 16)
	ip_info_container.add_child(public_ip_label)
	
	# Port forwarding instructions
	port_forward_label = Label.new()
	port_forward_label.text = "For internet play: Forward port 7777 (TCP/UDP) on your router"
	port_forward_label.add_theme_font_size_override("font_size", 14)
	port_forward_label.modulate = Color(1.0, 0.8, 0.0)  # Yellow warning color
	ip_info_container.add_child(port_forward_label)
	
	# Add to status area (replace status_label)
	status_label.get_parent().add_child(ip_info_container)
	status_label.visible = false
	
	ip_input.visible = false
	join_button.visible = false
	start_button.visible = true
	_add_player(NetworkManager.local_player_id, player_name + " (You - Host)")
	
	# Fetch public IP
	ip_helper.get_public_ip()

func setup_as_client(player_name: String) -> void:
	is_host = false
	client_player_name = player_name  # Store the player name for later use
	host_label.text = "Join Multiplayer Game"
	status_label.text = "Enter host IP address to connect"
	# Keep IP input visible for joining
	ip_input.visible = true
	join_button.visible = true
	start_button.visible = false
	# Don't add player yet - wait until connected

func _on_client_connected() -> void:
	"""Called after successfully connecting to host"""
	host_label.text = "Connected as client"
	status_label.text = "Connected to host"
	ip_input.visible = false
	join_button.visible = false

func _on_public_ip_received(ip: String) -> void:
	"""Called when public IP is successfully fetched"""
	if public_ip_label:
		public_ip_label.text = "Public IP (Internet): " + ip + " | Port: 7777"
		print("Public IP fetched: ", ip)

func _on_public_ip_failed(error: String) -> void:
	"""Called when public IP fetch fails"""
	if public_ip_label:
		public_ip_label.text = "Public IP (Internet): Failed to fetch (" + error + ")"
		print("Failed to fetch public IP: ", error)

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
	
	# Use the stored player name instead of generating a random one
	var player_name = client_player_name
	if player_name.is_empty():
		player_name = "Player" + str(randi() % 1000)
	
	if NetworkManager.join_game(host_ip, player_name):
		_on_client_connected()
		_add_player(NetworkManager.local_player_id, player_name + " (You)")
	else:
		status_label.text = "Failed to connect to " + host_ip

func _on_start_pressed() -> void:
	if is_host:
		NetworkManager.start_race()
		game_started.emit()

func _on_network_game_started() -> void:
	"""Called when NetworkManager broadcasts game start (for clients)"""
	print("Client received game start signal from host")
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
