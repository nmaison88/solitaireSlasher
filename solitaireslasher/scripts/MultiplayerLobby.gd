extends Control

signal lobby_closed
signal game_started(game_type: String, difficulty: String)

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
var game_type_option: OptionButton
var difficulty_option: OptionButton
var selected_game_type: String = "Solitaire"
var selected_difficulty: String = "Medium"
var qr_node: QR
var qr_texture_rect: TextureRect
var scan_button: Button
var native_camera: NativeCamera
var camera_display: TextureRect
var camera_panel: Panel
var close_camera_button: Button
var is_scanning: bool = false

func _ready() -> void:
	# Load and setup IP helper
	var ip_helper_script = preload("res://scripts/IPHelper.gd")
	ip_helper = ip_helper_script.new()
	add_child(ip_helper)
	ip_helper.public_ip_received.connect(_on_public_ip_received)
	ip_helper.public_ip_failed.connect(_on_public_ip_failed)
	
	# Setup QR plugin
	qr_node = QR.new()
	add_child(qr_node)
	qr_node.qr_detected.connect(_on_qr_detected)
	qr_node.qr_scan_failed.connect(_on_qr_scan_failed)
	
	# Setup Native Camera plugin
	native_camera = NativeCamera.new()
	native_camera.name = "NativeCamera"
	add_child(native_camera)
	print("NativeCamera node added to scene tree")
	
	# Wait for ready
	await get_tree().process_frame
	
	# Connect signals
	if native_camera.camera_permission_granted.connect(_on_camera_permission_granted) == OK:
		print("camera_permission_granted signal connected")
	if native_camera.camera_permission_denied.connect(_on_camera_permission_denied) == OK:
		print("camera_permission_denied signal connected")
	if native_camera.frame_available.connect(_on_camera_frame_available) == OK:
		print("frame_available signal connected")
	else:
		print("ERROR: Failed to connect frame_available signal!")
	
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
	
	# Scan QR Code button
	scan_button = Button.new()
	scan_button.text = "Scan QR Code"
	scan_button.custom_minimum_size = Vector2(150, 0)
	scan_button.pressed.connect(_on_scan_qr_pressed)
	ip_section.add_child(scan_button)
	
	join_button = Button.new()
	join_button.text = "Join Game"
	join_button.pressed.connect(_on_join_pressed)
	ip_section.add_child(join_button)
	
	# Game settings (only visible for host)
	var settings_label = Label.new()
	settings_label.name = "SettingsLabel"
	settings_label.text = "Game Settings:"
	settings_label.add_theme_font_size_override("font_size", 20)
	settings_label.visible = false
	vbox.add_child(settings_label)
	
	# Game type selection
	var game_type_container = HBoxContainer.new()
	game_type_container.name = "GameTypeContainer"
	game_type_container.visible = false
	vbox.add_child(game_type_container)
	
	var game_type_label = Label.new()
	game_type_label.text = "Game Type:"
	game_type_label.add_theme_font_size_override("font_size", 18)
	game_type_container.add_child(game_type_label)
	
	game_type_option = OptionButton.new()
	game_type_option.add_item("Solitaire")
	game_type_option.add_item("Sudoku")
	game_type_option.select(0)
	game_type_option.custom_minimum_size = Vector2(200, 40)
	game_type_option.item_selected.connect(_on_game_type_changed)
	game_type_container.add_child(game_type_option)
	
	# Difficulty selection
	var difficulty_container = HBoxContainer.new()
	difficulty_container.name = "DifficultyContainer"
	difficulty_container.visible = false
	vbox.add_child(difficulty_container)
	
	var difficulty_label = Label.new()
	difficulty_label.text = "Difficulty:"
	difficulty_label.add_theme_font_size_override("font_size", 18)
	difficulty_container.add_child(difficulty_label)
	
	difficulty_option = OptionButton.new()
	difficulty_option.add_item("Easy")
	difficulty_option.add_item("Medium")
	difficulty_option.add_item("Hard")
	difficulty_option.select(1)
	difficulty_option.custom_minimum_size = Vector2(200, 40)
	difficulty_option.item_selected.connect(_on_difficulty_changed)
	difficulty_container.add_child(difficulty_option)
	
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
		NetworkManager.game_settings_received.connect(_on_game_settings_received)

func setup_as_host(player_name: String) -> void:
	is_host = true
	host_label.text = "You are hosting"
	
	# Show game settings for host
	var settings_label = get_node_or_null("ScrollOuter/VBoxContainer/SettingsLabel")
	if settings_label:
		settings_label.visible = true
	
	var game_type_container = get_node_or_null("ScrollOuter/VBoxContainer/GameTypeContainer")
	if game_type_container:
		game_type_container.visible = true
	
	var difficulty_container = get_node_or_null("ScrollOuter/VBoxContainer/DifficultyContainer")
	if difficulty_container:
		difficulty_container.visible = true
	
	# Create IP info section for host
	var ip_info_container = VBoxContainer.new()
	ip_info_container.name = "IPInfoContainer"
	
	# Local IP (for LAN play)
	local_ip_label = Label.new()
	local_ip_label.text = "Local IP (LAN): " + ip_helper.get_local_ip() + " | Port: 7777"
	local_ip_label.add_theme_font_size_override("font_size", 16)
	ip_info_container.add_child(local_ip_label)
	
	# Generate QR code for local IP
	var local_ip = ip_helper.get_local_ip()
	_generate_qr_code(local_ip, ip_info_container)
	
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
	scan_button.visible = false  # Hide scan button for host
	start_button.visible = true
	_add_player(NetworkManager.local_player_id, player_name + " (You - Host)")
	
	# Fetch public IP
	ip_helper.get_public_ip()

func setup_as_client(player_name: String) -> void:
	is_host = false
	client_player_name = player_name  # Store the player name for later use
	host_label.text = "Join Multiplayer Game"
	status_label.text = "Enter host IP address or scan QR code to connect"
	# Keep IP input and scan button visible for joining
	ip_input.visible = true
	join_button.visible = true
	scan_button.visible = true  # Show scan button for client
	start_button.visible = false
	# Don't add player yet - wait until connected

func _on_client_connected() -> void:
	"""Called after successfully connecting to host"""
	host_label.text = "Connected as client"
	status_label.text = "Connected to host"
	ip_input.visible = false
	join_button.visible = false
	scan_button.visible = false  # Hide scan button after connecting

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
		print("DEBUG: Host start button pressed")
		# Pass game settings to start_race so they can be broadcast to clients
		var game_settings = {
			"game_type": selected_game_type,
			"difficulty": selected_difficulty
		}
		NetworkManager.start_race(game_settings)
		# Don't emit game_started here - NetworkManager will broadcast it

func _on_network_game_started() -> void:
	"""Called when NetworkManager broadcasts game start (for clients)"""
	print("Client received game start signal from host")
	print("Lobby game settings - Type: ", selected_game_type, ", Difficulty: ", selected_difficulty)
	game_started.emit(selected_game_type, selected_difficulty)

func _on_game_settings_received(settings: Dictionary) -> void:
	"""Called when client receives game settings from host"""
	print("Received game settings from host: ", settings)
	if settings.has("game_type"):
		selected_game_type = settings["game_type"]
	if settings.has("difficulty"):
		selected_difficulty = settings["difficulty"]
	print("Updated lobby settings - Type: ", selected_game_type, ", Difficulty: ", selected_difficulty)

func _on_game_type_changed(index: int) -> void:
	"""Handle game type selection change"""
	match index:
		0:
			selected_game_type = "Solitaire"
		1:
			selected_game_type = "Sudoku"
	print("Multiplayer game type changed to: ", selected_game_type)

func _on_difficulty_changed(index: int) -> void:
	"""Handle difficulty selection change"""
	match index:
		0:
			selected_difficulty = "Easy"
		1:
			selected_difficulty = "Medium"
		2:
			selected_difficulty = "Hard"
	print("Multiplayer difficulty changed to: ", selected_difficulty)

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

func _generate_qr_code(ip_address: String, container: VBoxContainer) -> void:
	"""Generate and display QR code for IP address"""
	if qr_node:
		# Generate QR code texture
		var qr_texture = qr_node.generate_qr_texture(ip_address, 256, Color.BLACK, Color.WHITE)
		
		if qr_texture:
			# Create TextureRect to display QR code
			qr_texture_rect = TextureRect.new()
			qr_texture_rect.texture = qr_texture
			qr_texture_rect.custom_minimum_size = Vector2(256, 256)
			qr_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			qr_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			
			# Add label
			var qr_label = Label.new()
			qr_label.text = "Scan QR Code to Join:"
			qr_label.add_theme_font_size_override("font_size", 16)
			container.add_child(qr_label)
			
			container.add_child(qr_texture_rect)
		else:
			print("Failed to generate QR code texture")
	else:
		print("QR plugin not available")

func _on_scan_qr_pressed() -> void:
	"""Open camera to scan QR code using NativeCamera plugin"""
	if not qr_node or not native_camera:
		status_label.text = "QR scanner not available"
		return
	
	print("Starting QR code scan with NativeCamera...")
	status_label.text = "Requesting camera permission..."
	
	# Check if we already have camera permission
	if native_camera.has_camera_permission():
		print("Camera permission already granted")
		_start_camera_feed()
	else:
		print("Requesting camera permission...")
		native_camera.request_camera_permission()
		# Permission result will trigger _on_camera_permission_granted or _on_camera_permission_denied

func _on_qr_detected(data: String) -> void:
	"""Called when QR code is successfully scanned"""
	print("QR code detected: ", data)
	
	# Close camera
	_close_camera()
	
	# Set the scanned IP in the input field
	ip_input.text = data
	status_label.text = "QR code scanned! IP: " + data
	
	# Auto-join after scanning
	_on_join_pressed()

func _on_qr_scan_failed(error) -> void:
	"""Called when QR code scanning fails"""
	print("QR scan failed: ", error)
	status_label.text = "QR scan failed. Please enter IP manually."

func _create_camera_overlay() -> void:
	"""Create camera overlay UI for scanning"""
	if camera_panel:
		print("Camera overlay already exists")
		return  # Already created
	
	print("Creating camera overlay UI...")
	
	# Create full-screen panel for camera
	camera_panel = Panel.new()
	camera_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	camera_panel.z_index = 100  # On top of everything
	camera_panel.visible = false
	add_child(camera_panel)
	print("Camera panel created, z_index: ", camera_panel.z_index)
	
	# Create camera display
	camera_display = TextureRect.new()
	camera_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	camera_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	camera_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	camera_panel.add_child(camera_display)
	print("Camera display TextureRect created")
	
	# Create close button
	close_camera_button = Button.new()
	close_camera_button.text = "Close Camera"
	close_camera_button.custom_minimum_size = Vector2(200, 80)
	close_camera_button.position = Vector2(50, 50)
	close_camera_button.pressed.connect(_on_close_camera_pressed)
	camera_panel.add_child(close_camera_button)
	print("Close camera button created")
	
	# Add instruction label
	var instruction_label = Label.new()
	instruction_label.text = "Point camera at QR code"
	instruction_label.add_theme_font_size_override("font_size", 32)
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.position = Vector2(0, 150)
	instruction_label.size = Vector2(get_viewport().size.x, 50)
	camera_panel.add_child(instruction_label)
	print("Camera overlay UI created successfully")

func _on_close_camera_pressed() -> void:
	"""Close camera and stop scanning"""
	_close_camera()
	status_label.text = "Camera closed"

func _close_camera() -> void:
	"""Stop camera feed and hide overlay"""
	is_scanning = false
	
	if native_camera:
		native_camera.stop()
		print("Camera stopped")
	
	if camera_panel:
		camera_panel.visible = false

func _start_camera_feed() -> void:
	"""Start the native camera feed"""
	print("Starting native camera feed...")
	status_label.text = "Opening camera..."
	
	# Create camera UI overlay
	_create_camera_overlay()
	
	# Get available cameras first
	var cameras = native_camera.get_all_cameras()
	print("Available cameras: ", cameras.size())
	for i in range(cameras.size()):
		var cam = cameras[i]
		print("  Camera ", i, ": ", cam)
	
	# Create feed request with lower frames_to_skip for more frequent updates
	var feed_request = FeedRequest.new()
	
	# Try to set the camera ID to the first available camera
	if cameras.size() > 0:
		var camera_id = cameras[0].get_camera_id()
		feed_request.set_camera_id(camera_id)
		print("Setting camera ID to: ", camera_id)
	
	feed_request.set_width(1280)
	feed_request.set_height(720)
	feed_request.set_frames_to_skip(5)  # Only skip 5 frames instead of 40
	feed_request.set_rotation(90)  # Portrait mode
	feed_request.set_grayscale(false)
	print("Feed request created:")
	print("  - Width: 1280")
	print("  - Height: 720")
	print("  - Frames to skip: 5")
	print("  - Rotation: 90")
	print("  - Grayscale: false")
	print("  - Feed request data: ", feed_request.get_raw_data())
	
	# Check if native_camera has the plugin singleton
	if native_camera._plugin_singleton:
		print("NativeCamera plugin singleton is initialized")
	else:
		print("ERROR: NativeCamera plugin singleton is NULL!")
	
	# Start camera with request
	print("Calling native_camera.start()...")
	native_camera.start(feed_request)
	print("Camera start() called - waiting for frames...")
	
	# Show camera overlay
	if camera_panel:
		camera_panel.visible = true
		print("Camera panel set to visible: ", camera_panel.visible)
		print("Camera panel position: ", camera_panel.position)
		print("Camera panel size: ", camera_panel.size)
	else:
		print("ERROR: camera_panel is null!")
	
	is_scanning = true
	
	print("Native camera feed started, is_scanning: ", is_scanning)

func _on_camera_permission_granted() -> void:
	"""Called when camera permission is granted"""
	print("Camera permission granted!")
	status_label.text = "Camera permission granted"
	_start_camera_feed()

func _on_camera_permission_denied() -> void:
	"""Called when camera permission is denied"""
	print("Camera permission denied")
	status_label.text = "Camera permission denied. Please enter IP manually."

func _on_camera_frame_available(frame_info: FrameInfo) -> void:
	"""Called when a new camera frame is available"""
	print("Frame received! is_scanning: ", is_scanning)
	
	if not is_scanning:
		print("Not scanning, ignoring frame")
		return
	
	# Get image from frame
	var img = frame_info.get_image()
	print("Frame image size: ", img.get_size() if img else "null")
	
	if img and img.get_size().x > 0:
		# Display the frame
		if camera_display:
			var texture = ImageTexture.create_from_image(img)
			camera_display.texture = texture
			print("Frame displayed in camera_display, texture size: ", texture.get_size())
		else:
			print("ERROR: camera_display is null!")
		
		# Scan the image for QR codes
		qr_node.scan_qr_image(img)
