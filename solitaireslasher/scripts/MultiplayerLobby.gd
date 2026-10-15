extends Control

const WastelandStyle = preload("res://scripts/WastelandStyle.gd")

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
var selected_game_type: String = "Solitaire"
var selected_difficulty: String = "Medium"
var mirror_mode_enabled: bool = false
var qr_node: QR
var qr_texture_rect: TextureRect
var scan_button: Button
var native_camera: NativeCamera
var camera_display: TextureRect
var camera_panel: Panel
var close_camera_button: Button
var is_scanning: bool = false
var settings_label: Label
var main_vbox: VBoxContainer  # Store reference to main vbox
var ip_card: PanelContainer  # Wraps the IP input and join/scan buttons
var accent: Color = WastelandStyle.accent_for("Solitaire")  # Set from the selected game in _create_ui

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
	
	# Wait for ready
	await get_tree().process_frame
	
	# Connect signals
	native_camera.camera_permission_granted.connect(_on_camera_permission_granted)
	native_camera.camera_permission_denied.connect(_on_camera_permission_denied)
	native_camera.frame_available.connect(_on_camera_frame_available)
	
	_create_ui()
	_connect_signals()

func _create_ui() -> void:
	# Accent color follows the game chosen in the main menu
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("get_current_game_type"):
		accent = WastelandStyle.accent_for(main_scene.get_current_game_type())

	# Main container with responsive margins
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Use smaller margins on mobile devices (narrow screens)
	var horizontal_margin = 40 if get_viewport().get_visible_rect().size.x < 600 else 80
	var vertical_margin = 40 if get_viewport().get_visible_rect().size.y < 900 else 80
	if OS.has_feature("mobile"):
		vertical_margin += int(DisplayServer.get_display_safe_area().position.y)

	margin.add_theme_constant_override("margin_left", horizontal_margin)
	margin.add_theme_constant_override("margin_right", horizontal_margin)
	margin.add_theme_constant_override("margin_top", vertical_margin)
	margin.add_theme_constant_override("margin_bottom", vertical_margin)
	add_child(margin)
	
	# Add scroll container to ensure all content is accessible
	var scroll_outer = ScrollContainer.new()
	scroll_outer.name = "ScrollOuter"
	scroll_outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll_outer.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll_outer)
	
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.add_theme_constant_override("separation", 28)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_outer.add_child(vbox)
	main_vbox = vbox  # Store reference for later use
	
	# Title
	vbox.add_child(WastelandStyle.title("THE LOBBY", 80))
	
	# Host/Join status
	host_label = WastelandStyle.label("", 44, accent.lightened(0.15), 3, 8)
	host_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(host_label)
	
	# Status label
	status_label = WastelandStyle.label("Waiting for players...", 30, Color(WastelandStyle.BONE, 0.75), 1)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(status_label)
	
	# IP Entry section (for joining)
	ip_card = WastelandStyle.card(accent)
	ip_card.name = "IPCard"
	vbox.add_child(ip_card)
	var ip_section = VBoxContainer.new()
	ip_section.add_theme_constant_override("separation", 24)
	ip_card.add_child(ip_section)
	
	ip_section.add_child(WastelandStyle.section_header("HOST IP"))
	
	ip_input = LineEdit.new()
	ip_input.placeholder_text = "e.g. 192.168.1.20"
	ip_input.custom_minimum_size = Vector2(0, 100)
	WastelandStyle.style_line_edit(ip_input, accent)
	ip_section.add_child(ip_input)
	
	# Button row
	var button_row = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 20)
	ip_section.add_child(button_row)
	
	# Scan QR Code button
	scan_button = WastelandStyle.make_button("SCAN QR", accent, false, Vector2(340, 104), 36)
	scan_button.pressed.connect(_on_scan_qr_pressed)
	button_row.add_child(scan_button)
	
	join_button = WastelandStyle.make_button("JOIN", accent, true, Vector2(340, 104), 36)
	join_button.pressed.connect(_on_join_pressed)
	button_row.add_child(join_button)
	
	# Game settings (only visible for host)
	settings_label = Label.new()
	settings_label.name = "SettingsLabel"
	settings_label.visible = false
	vbox.add_child(settings_label)
	
	# (game type and difficulty selectors are created in _create_game_settings_display)
	
	# Player list
	var players_card = WastelandStyle.card(accent)
	players_card.name = "PlayerList"
	vbox.add_child(players_card)
	var players_box = VBoxContainer.new()
	players_box.add_theme_constant_override("separation", 18)
	players_card.add_child(players_box)
	players_box.add_child(WastelandStyle.section_header("PLAYERS"))
	
	player_list = VBoxContainer.new()
	player_list.add_theme_constant_override("separation", 14)
	player_list.custom_minimum_size = Vector2(0, 60)
	players_box.add_child(player_list)
	
	# Buttons
	var button_box = HBoxContainer.new()
	button_box.name = "ButtonBox"
	button_box.alignment = BoxContainer.ALIGNMENT_CENTER
	button_box.add_theme_constant_override("separation", 20)
	vbox.add_child(button_box)
	
	start_button = WastelandStyle.make_button("START RACE", accent, true, Vector2(360, 112), 38)
	start_button.pressed.connect(_on_start_pressed)
	start_button.visible = false
	button_box.add_child(start_button)
	
	leave_button = WastelandStyle.make_button("LEAVE", accent, false, Vector2(300, 112), 38)
	leave_button.pressed.connect(_on_leave_pressed)
	button_box.add_child(leave_button)

	# Fade in
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)

func _reset_lobby_state() -> void:
	"""Reset lobby state to prevent issues from previous sessions"""
	print("Resetting lobby state...")
	
	# Clear players dictionary
	players.clear()
	
	# Reset selected values to defaults
	selected_game_type = "Solitaire"
	selected_difficulty = "Medium"
	mirror_mode_enabled = false
	
	# Clear any existing IP info containers
	var existing_ip_info = get_node_or_null("IPInfoContainer")
	if existing_ip_info:
		existing_ip_info.queue_free()
	
	print("Lobby state reset complete")

func _connect_signals() -> void:
	if NetworkManager:
		NetworkManager.player_connected.connect(_on_player_connected)
		NetworkManager.player_disconnected.connect(_on_player_disconnected)
		NetworkManager.game_started.connect(_on_network_game_started)
		NetworkManager.game_settings_received.connect(_on_game_settings_received)

func _create_game_settings_display() -> void:
	"""Create game settings card: game name, difficulty slider and mirror mode"""
	var settings_container = WastelandStyle.card(accent)
	settings_container.name = "GameSettingsContainer"
	var settings_box = VBoxContainer.new()
	settings_box.add_theme_constant_override("separation", 18)
	settings_container.add_child(settings_box)

	settings_box.add_child(WastelandStyle.section_header("RACE SETTINGS"))

	# Game type — non-editable label
	var game_type_val = WastelandStyle.label(WastelandStyle.display_name(selected_game_type), 44, accent.lightened(0.15), 3, 6)
	game_type_val.name = "GameTypeValue"
	settings_box.add_child(game_type_val)

	# Difficulty — face icon + slider
	var difficulties = ["Easy", "Medium", "Hard"]
	var current_index = difficulties.find(selected_difficulty)
	if current_index == -1:
		current_index = 1

	var face_row = HBoxContainer.new()
	face_row.alignment = BoxContainer.ALIGNMENT_CENTER
	face_row.add_theme_constant_override("separation", 18)
	settings_box.add_child(face_row)

	var face_icon = FontAwesome.new()
	face_icon.name = "DifficultyFaceIcon"
	face_icon.icon_size = 64
	face_icon.add_theme_color_override("font_color", accent)
	_set_difficulty_face_icon(face_icon, current_index)
	face_row.add_child(face_icon)

	var face_label = WastelandStyle.label(difficulties[current_index].to_upper(), 44, WastelandStyle.BONE, 4)
	face_label.name = "DifficultyFaceLabel"
	face_row.add_child(face_label)

	var slider_row = HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 20)
	var easy_lbl = WastelandStyle.label("EASY", 28, WastelandStyle.BONE_MUTED, 2)
	easy_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slider_row.add_child(easy_lbl)

	var diff_slider = HSlider.new()
	diff_slider.name = "DifficultySlider"
	diff_slider.min_value = 0
	diff_slider.max_value = 2
	diff_slider.step = 1
	diff_slider.value = current_index
	diff_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff_slider.custom_minimum_size = Vector2(260, 100)  # Tall hit area for thumbs
	WastelandStyle.style_slider(diff_slider, accent)

	# Tap-to-position: left third = Easy, middle = Medium, right = Hard
	diff_slider.gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
			var relative_pos = event.position.x / diff_slider.size.x  # gui_input positions are local
			diff_slider.value = 0 if relative_pos < 0.33 else (1 if relative_pos < 0.67 else 2)
	)

	slider_row.add_child(diff_slider)
	var hard_lbl = WastelandStyle.label("HARD", 28, WastelandStyle.BONE_MUTED, 2)
	hard_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slider_row.add_child(hard_lbl)
	settings_box.add_child(slider_row)

	# Mirror Mode
	var mirror_checkbox = CheckBox.new()
	mirror_checkbox.name = "MirrorModeCheckbox"
	mirror_checkbox.text = "MIRROR MODE"
	mirror_checkbox.button_pressed = mirror_mode_enabled
	mirror_checkbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	WastelandStyle.style_check_box(mirror_checkbox, accent)
	mirror_checkbox.toggled.connect(func(toggled_on: bool) -> void:
		mirror_mode_enabled = toggled_on
		print("Mirror mode " + ("enabled" if toggled_on else "disabled"))
		# Update the stored setting in MultiplayerGameManager
		if MultiplayerGameManager:
			MultiplayerGameManager.mirror_mode_enabled = toggled_on
			print("Updated MultiplayerGameManager mirror mode: ", toggled_on)
	)
	settings_box.add_child(mirror_checkbox)

	var mirror_explanation = WastelandStyle.label("Everyone races the exact same deal or puzzle", 26, Color(WastelandStyle.BONE, 0.6), 1)
	mirror_explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_box.add_child(mirror_explanation)

	diff_slider.value_changed.connect(func(val: float) -> void:
		var idx = int(val)
		selected_difficulty = difficulties[idx]
		face_label.text = difficulties[idx].to_upper()
		_set_difficulty_face_icon(face_icon, idx)
		print("Multiplayer difficulty changed to: ", selected_difficulty)
	)

	_insert_before(settings_container, "PlayerList")

func _insert_before(node: Control, sibling_name: String) -> void:
	"""Add node to the main vbox just before the named sibling (or at the end if it's missing)"""
	if not main_vbox:
		return
	main_vbox.add_child(node)
	var sibling = main_vbox.get_node_or_null(sibling_name)
	if sibling:
		main_vbox.move_child(node, sibling.get_index())

func _set_difficulty_face_icon(icon: FontAwesome, index: int) -> void:
	match index:
		0: icon.icon_name = "face-smile"
		1: icon.icon_name = "face-meh"
		2: icon.icon_name = "face-angry"

func _update_game_settings_display() -> void:
	"""Update the game type label in the settings display"""
	var settings_container = null
	if main_vbox:
		settings_container = main_vbox.get_node_or_null("GameSettingsContainer")
	if not settings_container:
		return
	# Update game type label
	var game_type_val = settings_container.find_child("GameTypeValue", true, false)
	if game_type_val is Label:
		game_type_val.text = WastelandStyle.display_name(selected_game_type)
	print("Updated game settings display - Type: ", selected_game_type, ", Difficulty: ", selected_difficulty)

func _create_qr_section() -> void:
	"""Create QR code card at the top of the host lobby"""
	var local_ip = ip_helper.get_local_ip()
	
	var qr_container = WastelandStyle.card(accent)
	qr_container.name = "QRContainer"
	var qr_box = VBoxContainer.new()
	qr_box.alignment = BoxContainer.ALIGNMENT_CENTER
	qr_box.add_theme_constant_override("separation", 18)
	qr_container.add_child(qr_box)
	
	qr_box.add_child(WastelandStyle.section_header("SCAN TO JOIN"))
	
	# Generate QR code
	_generate_qr_code(local_ip, qr_box)
	
	# IP Address text
	var ip_text = WastelandStyle.label("Local IP: " + local_ip + "  ·  Port 7777", 28, Color(WastelandStyle.BONE, 0.7), 1)
	qr_box.add_child(ip_text)
	
	# Put the QR first so the joining player can scan it without scrolling
	_insert_before(qr_container, "GameSettingsContainer" if main_vbox.has_node("GameSettingsContainer") else "PlayerList")

func setup_as_host(player_name: String) -> void:
	# Reset state to prevent issues from previous sessions
	_reset_lobby_state()
	
	is_host = true
	
	# Get the current game type from Main scene
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("get_current_game_type"):
		selected_game_type = main_scene.get_current_game_type()
	elif main_scene and main_scene.has_property("_current_game_type"):
		selected_game_type = main_scene._current_game_type
	
	print("Hosting multiplayer game for: ", selected_game_type)
	host_label.text = "Hosting " + WastelandStyle.display_name(selected_game_type)
	
	# Initialize MultiplayerGameManager for multiplayer
	if MultiplayerGameManager.host_multiplayer_game(player_name):
		print("MultiplayerGameManager initialized for hosting")
		# Store mirror mode setting in MultiplayerGameManager
		MultiplayerGameManager.mirror_mode_enabled = mirror_mode_enabled
		print("Stored mirror mode setting in MultiplayerGameManager: ", mirror_mode_enabled)
	else:
		print("Failed to initialize MultiplayerGameManager for hosting")
	
	# Create professional game settings display
	_create_game_settings_display()
	
	# Create QR code section above buttons
	_create_qr_section()
	
	if settings_label:
		settings_label.visible = false
	
	# Hide join elements for host
	ip_input.visible = false
	join_button.visible = false
	scan_button.visible = false
	ip_card.visible = false
	start_button.visible = true
	_add_player(NetworkManager.local_player_id, player_name + " (You - Host)")

func setup_as_client(player_name: String) -> void:
	# Reset state to prevent issues from previous sessions
	_reset_lobby_state()
	
	is_host = false
	client_player_name = player_name  # Store the player name for later use
	status_label.text = "Enter host IP address or scan QR code to connect"
	
	# Get the current game type from Main scene
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("get_current_game_type"):
		selected_game_type = main_scene.get_current_game_type()
	elif main_scene and main_scene.has_property("_current_game_type"):
		selected_game_type = main_scene._current_game_type
	
	print("Joining multiplayer game for: ", selected_game_type)
	host_label.text = "Joining " + WastelandStyle.display_name(selected_game_type)

	# Don't set is_multiplayer yet - wait until connection actually succeeds
	# It will be set in _on_client_connected()
	
	selected_difficulty = "Medium"
	
	# Keep IP input and scan button visible for joining
	ip_input.visible = true
	join_button.visible = true
	scan_button.visible = true  # Show scan button for client
	ip_card.visible = true
	start_button.visible = false
	# Don't add player yet - wait until connected

func _on_client_connected() -> void:
	"""Called after successfully connecting to host"""
	is_host = false

	# Now that connection succeeded, mark as multiplayer
	MultiplayerGameManager.is_multiplayer = true

	# Show the connected host IP
	var connected_ip = ip_input.text
	host_label.text = "Connected to Host: " + connected_ip
	status_label.text = "Waiting for host to start game..."
	status_label.visible = true
	
	# Hide join UI elements
	ip_input.visible = false
	join_button.visible = false
	scan_button.visible = false
	ip_card.visible = false
	
	# Show leave button
	leave_button.visible = true
	start_button.visible = false

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
	var row = HBoxContainer.new()
	row.name = "player_" + str(player_id)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	var icon = FontAwesome.new()
	icon.icon_name = "user"
	icon.icon_size = 32
	icon.add_theme_color_override("font_color", accent)
	row.add_child(icon)
	row.add_child(WastelandStyle.label(player_name, 34, WastelandStyle.BONE, 1))
	player_list.add_child(row)

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

func get_mirror_mode() -> bool:
	"""Get the current mirror mode setting"""
	return mirror_mode_enabled

func _on_start_pressed() -> void:
	if is_host:
		print("DEBUG: Host start button pressed")
		# Debug check
		print("DEBUG: MultiplayerGameManager.is_multiplayer: ", MultiplayerGameManager.is_multiplayer)
		print("DEBUG: MultiplayerGameManager.network_manager.is_host: ", MultiplayerGameManager.network_manager.is_host)
		print("DEBUG: selected_game_type: ", selected_game_type)
		print("DEBUG: current_game_type in MultiplayerGameManager: ", MultiplayerGameManager.current_game_type)
		
		# Set game type in MultiplayerGameManager before starting
		MultiplayerGameManager.current_game_type = selected_game_type
		
		# Call MultiplayerGameManager to start the race (this handles mirror data)
		print("DEBUG: About to call MultiplayerGameManager.start_multiplayer_race()")
		MultiplayerGameManager.start_multiplayer_race()
		print("DEBUG: Called MultiplayerGameManager.start_multiplayer_race()")
		# Don't emit game_started here - NetworkManager will broadcast it

func _on_network_game_started() -> void:
	"""Called when NetworkManager broadcasts game start (for clients)"""
	print("Client received game start signal from host")
	print("Lobby game settings - Type: ", selected_game_type, ", Difficulty: ", selected_difficulty)
	game_started.emit(selected_game_type, selected_difficulty)

func _on_game_settings_received(settings: Dictionary) -> void:
	"""Called when client receives game settings from host"""
	print("Client received game settings from host: ", settings)
	if settings.has("game_type"):
		selected_game_type = settings["game_type"]
	if settings.has("difficulty"):
		selected_difficulty = settings["difficulty"]
	if settings.has("mirror_mode"):
		mirror_mode_enabled = settings["mirror_mode"]
		# Update checkbox state
		var checkbox = find_child("MirrorModeCheckbox", true, false)
		if checkbox is CheckBox:
			checkbox.button_pressed = mirror_mode_enabled
	print("Updated lobby settings - Type: ", selected_game_type, ", Difficulty: ", selected_difficulty, ", Mirror Mode: ", mirror_mode_enabled)

func _on_game_carousel_changed():
	pass  # Legacy stub — game type is now inferred from main scene selection

func _on_difficulty_carousel_changed():
	pass  # Legacy stub — difficulty now controlled by HSlider in _create_game_settings_display

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
		var qr_texture = qr_node.generate_qr_texture(ip_address, 512, Color.BLACK, Color.WHITE)
		
		if qr_texture:
			# White plate with an accent rim keeps the code scannable on the dark background
			var plate_style = StyleBoxFlat.new()
			plate_style.bg_color = Color.WHITE
			plate_style.set_border_width_all(6)
			plate_style.border_color = accent
			plate_style.set_corner_radius_all(16)
			plate_style.set_content_margin_all(24)
			plate_style.shadow_color = Color(accent, 0.4)
			plate_style.shadow_size = 18
			var plate = PanelContainer.new()
			plate.add_theme_stylebox_override("panel", plate_style)
			plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			plate.mouse_filter = Control.MOUSE_FILTER_PASS  # Let drags reach the scroll container
			container.add_child(plate)

			qr_texture_rect = TextureRect.new()
			qr_texture_rect.texture = qr_texture
			qr_texture_rect.custom_minimum_size = Vector2(460, 460)
			qr_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			qr_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			qr_texture_rect.mouse_filter = Control.MOUSE_FILTER_PASS
			plate.add_child(qr_texture_rect)
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
		return  # Already created
	
	# Create full-screen panel for camera
	camera_panel = Panel.new()
	camera_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	camera_panel.z_index = 100  # On top of everything
	camera_panel.visible = false
	var camera_bg = StyleBoxFlat.new()
	camera_bg.bg_color = WastelandStyle.INK
	camera_panel.add_theme_stylebox_override("panel", camera_bg)
	add_child(camera_panel)
	
	# Create camera display
	camera_display = TextureRect.new()
	camera_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	camera_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	camera_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	camera_panel.add_child(camera_display)
	
	var top_padding = DisplayServer.get_display_safe_area().position.y if OS.has_feature("mobile") else 0
	
	# Instruction label - large, outlined so it reads over the camera feed
	var instruction_label = WastelandStyle.label("POINT AT THE HOST'S QR CODE", 44, WastelandStyle.BONE, 4, 10)
	instruction_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	instruction_label.offset_top = top_padding + 80
	instruction_label.offset_bottom = top_padding + 160
	camera_panel.add_child(instruction_label)
	
	# Close button - large and easy to tap, centered near the bottom
	close_camera_button = WastelandStyle.make_button("CLOSE CAMERA", accent, true, Vector2(440, 120), 40)
	close_camera_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	close_camera_button.offset_left = -220
	close_camera_button.offset_right = 220
	close_camera_button.offset_top = -260
	close_camera_button.offset_bottom = -140
	close_camera_button.pressed.connect(_on_close_camera_pressed)
	camera_panel.add_child(close_camera_button)

func _on_close_camera_pressed() -> void:
	"""Close camera and stop scanning"""
	_close_camera()
	status_label.text = "Camera closed"

func _close_camera() -> void:
	"""Stop camera feed and hide overlay"""
	is_scanning = false

	if native_camera:
		native_camera.stop()

	if camera_panel:
		camera_panel.visible = false

	# Resume lobby music now that the camera is gone
	# But only if not in multiplayer mode
	if SoundManager:
		# Check if we're in multiplayer by checking if MultiplayerGameManager exists and is active
		if not (MultiplayerGameManager and MultiplayerGameManager.is_multiplayer):
			SoundManager.play_background_music()
			print("Resumed background music (single player mode)")
		else:
			print("Keeping music stopped (multiplayer mode)")

func _start_camera_feed() -> void:
	"""Start the native camera feed"""
	# Stop music before opening camera to avoid iOS audio-session interruption squelch
	if SoundManager:
		SoundManager.stop_background_music()
	print("Starting camera for QR scanning...")
	status_label.text = "Opening camera..."
	
	# Create camera UI overlay
	_create_camera_overlay()
	
	# Get available cameras and select the first one
	var cameras = native_camera.get_all_cameras()
	var feed_request = FeedRequest.new()
	
	# Set camera ID if available
	if cameras.size() > 0:
		var camera_id = cameras[0].get_camera_id()
		feed_request.set_camera_id(camera_id)
		print("Using camera: ", camera_id)
	
	# Configure feed request
	feed_request.set_width(1280)
	feed_request.set_height(720)
	feed_request.set_frames_to_skip(5)
	feed_request.set_rotation(90)
	feed_request.set_grayscale(false)
	
	# Start camera
	native_camera.start(feed_request)
	
	# Show camera overlay
	camera_panel.visible = true
	is_scanning = true
	
	print("Camera started")

func _on_camera_permission_granted() -> void:
	"""Called when camera permission is granted"""
	status_label.text = "Camera permission granted"
	_start_camera_feed()

func _on_camera_permission_denied() -> void:
	"""Called when camera permission is denied"""
	print("Camera permission denied")
	status_label.text = "Camera permission denied. Please enter IP manually."

func _on_camera_frame_available(frame_info: FrameInfo) -> void:
	"""Called when a new camera frame is available"""
	if not is_scanning:
		return
	
	# Get image from frame
	var img = frame_info.get_image()
	
	if img and img.get_size().x > 0:
		# Display the frame
		if camera_display:
			var texture = ImageTexture.create_from_image(img)
			camera_display.texture = texture
		
		# Scan the image for QR codes
		qr_node.scan_qr_image(img)
