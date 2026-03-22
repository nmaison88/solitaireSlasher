extends Control

var _status_label: Label
var _game: Node
var _board: Node

var _multiplayer_ui: Control
var _lobby_ui: Control
var _game_ui: Control
var _multiplayer_lobby: Control
var _undo_button: Button
var _menu_container: VBoxContainer
var _menu_button: Button
var _player_status_label: Label
var _ready_button: Button
var _last_standing_notification: Panel
var _waiting_for_ready: bool = false  # Flag to prevent status updates during ready phase

func _ready() -> void:
	_status_label = get_node("StatusLabel") as Label
	_game = get_node("Game")
	_board = get_node("Board")
	
	# Hide game elements on startup
	_board.visible = false
	_status_label.visible = false
	
	_setup_main_menu()
	_show_main_menu()

func _setup_main_menu() -> void:
	# Create centered menu container
	_menu_container = VBoxContainer.new()
	_menu_container.name = "MainMenuContainer"
	_menu_container.set_anchors_preset(Control.PRESET_CENTER)
	_menu_container.anchor_left = 0.5
	_menu_container.anchor_top = 0.5
	_menu_container.anchor_right = 0.5
	_menu_container.anchor_bottom = 0.5
	_menu_container.offset_left = -100
	_menu_container.offset_top = -150
	_menu_container.offset_right = 100
	_menu_container.offset_bottom = 150
	_menu_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu_container.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_menu_container)
	
	# Add title
	var title = Label.new()
	title.text = "Solitaire Slasher"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	_menu_container.add_child(title)
	
	# Add spacing
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 40)
	_menu_container.add_child(spacer1)
	
	# Create menu buttons
	var single_button = Button.new()
	single_button.name = "menu_single"
	single_button.text = "Single Player"
	single_button.custom_minimum_size = Vector2(200, 50)
	single_button.pressed.connect(_on_single_player)
	_menu_container.add_child(single_button)
	
	var host_button = Button.new()
	host_button.name = "menu_host"
	host_button.text = "Host Multiplayer"
	host_button.custom_minimum_size = Vector2(200, 50)
	host_button.pressed.connect(_on_host_game)
	_menu_container.add_child(host_button)
	
	var join_button = Button.new()
	join_button.name = "menu_join"
	join_button.text = "Join Multiplayer"
	join_button.custom_minimum_size = Vector2(200, 50)
	join_button.pressed.connect(_on_join_game)
	_menu_container.add_child(join_button)

func _on_host_game() -> void:
	var player_name = "Player" + str(randi() % 1000)
	if NetworkManager.host_game(player_name):
		print("Hosting multiplayer game")
		_show_multiplayer_lobby(true, player_name)
	else:
		print("Failed to host game")

func _on_join_game() -> void:
	# Show lobby with manual IP entry
	_show_multiplayer_lobby(false, "Player" + str(randi() % 1000))

func _show_main_menu() -> void:
	if _menu_container:
		_menu_container.visible = true
	_board.visible = false
	_status_label.visible = false
	
	# Hide game control buttons
	for child in get_children():
		if child is Button and (child.name == "new_game" or child.name == "undo_button" or child.name == "menu_button"):
			child.visible = false

func _hide_main_menu() -> void:
	if _menu_container:
		_menu_container.visible = false
	_board.visible = true
	_status_label.visible = true

func _on_single_player() -> void:
	_hide_main_menu()
	MultiplayerGameManager.start_local_game()
	_setup_single_player_game()

func _start_multiplayer_game() -> void:
	_hide_main_menu()
	if MultiplayerGameManager.is_host_player():
		MultiplayerGameManager.start_multiplayer_race()
	_setup_multiplayer_game()

func _setup_single_player_game() -> void:
	print("Setting up single player game...")
	var local_game = MultiplayerGameManager.get_local_game()
	if local_game and is_instance_valid(local_game):
		print("Got local game, setting up board")
		_game = local_game
		_board.set_game(_game)
		_board.render()
		# Hide menu buttons to avoid interfering with game
		_hide_menu_buttons()
		# Show new game button
		_show_new_game_button()
		# Connect to game signals to update undo button state
		if not _game.card_moved.is_connected(_on_card_moved):
			_game.card_moved.connect(_on_card_moved)
	else:
		print("Failed to get local game or game is invalid")

func _hide_menu_buttons():
	for child in get_children():
		if child is Button and child.name.begins_with("menu_"):
			child.visible = false

func _show_new_game_button():
	# Remove existing game control buttons if any
	for child in get_children():
		if child is Button and (child.name == "new_game" or child.name == "undo_button" or child.name == "menu_button"):
			child.queue_free()
	
	# New Game/Forfeit button (top right) - FontAwesome icon
	# In multiplayer mode, this becomes a forfeit button
	var new_game_button = Button.new()
	new_game_button.name = "new_game"
	new_game_button.position = Vector2(950, 10)
	new_game_button.size = Vector2(50, 50)
	
	var is_multiplayer_mode = MultiplayerGameManager and MultiplayerGameManager.is_multiplayer
	print("Creating game button - is_multiplayer: ", is_multiplayer_mode)
	
	if is_multiplayer_mode:
		# Forfeit button in multiplayer
		new_game_button.tooltip_text = "Forfeit (Mark as Jammed)"
		new_game_button.pressed.connect(_on_forfeit_pressed)
		
		# Add flag icon for forfeit
		var forfeit_icon = FontAwesome.new()
		forfeit_icon.icon_name = "flag"
		forfeit_icon.icon_type = "solid"
		forfeit_icon.icon_size = 32
		forfeit_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		forfeit_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		new_game_button.add_child(forfeit_icon)
	else:
		# Retry button in single player
		new_game_button.tooltip_text = "New Game"
		new_game_button.pressed.connect(_on_new_game_pressed)
		
		# Add retry icon
		var retry_icon = FontAwesome.new()
		retry_icon.icon_name = "rotate-right"
		retry_icon.icon_type = "solid"
		retry_icon.icon_size = 32
		retry_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		retry_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		new_game_button.add_child(retry_icon)
	
	add_child(new_game_button)
	
	# Undo button (bottom center) - FontAwesome icon
	var undo_button = Button.new()
	undo_button.name = "undo_button"
	undo_button.position = Vector2(487, 700)  # Bottom center (1024/2 - 25)
	undo_button.size = Vector2(50, 50)
	undo_button.tooltip_text = "Undo Last Move"
	undo_button.pressed.connect(_on_undo_pressed)
	
	# Add FontAwesome icon as child
	var undo_icon = FontAwesome.new()
	undo_icon.icon_name = "rotate-left"  # or "arrow-rotate-left"
	undo_icon.icon_type = "solid"
	undo_icon.icon_size = 32
	undo_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	undo_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	undo_button.add_child(undo_icon)
	
	add_child(undo_button)
	
	# Store reference to undo button for state updates
	_undo_button = undo_button
	_update_undo_button_state()
	
	# Menu button (top left) - FontAwesome icon
	var menu_button = Button.new()
	menu_button.name = "menu_button"
	menu_button.position = Vector2(10, 10)
	menu_button.size = Vector2(50, 50)
	menu_button.tooltip_text = "Main Menu"
	menu_button.pressed.connect(_on_back_to_menu_pressed)
	
	# Add FontAwesome icon as child
	var menu_icon = FontAwesome.new()
	menu_icon.icon_name = "bars"  # Hamburger menu icon
	menu_icon.icon_type = "solid"
	menu_icon.icon_size = 32
	menu_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_button.add_child(menu_icon)
	
	add_child(menu_button)
	_menu_button = menu_button

func _setup_multiplayer_game() -> void:
	var local_game = MultiplayerGameManager.get_local_game()
	if local_game and is_instance_valid(local_game):
		_game = local_game
		_board.set_game(_game)
		_board.set_multiplayer_manager(MultiplayerGameManager)
		_board.render()
		
		# IMPORTANT: Recreate buttons AFTER is_multiplayer is set to true
		# This ensures forfeit button is created instead of retry button
		_show_new_game_button()
		
		# Setup multiplayer-specific UI
		_setup_multiplayer_ui()
		# Connect to multiplayer signals
		if not MultiplayerGameManager.player_status_changed.is_connected(_on_player_status_changed):
			MultiplayerGameManager.player_status_changed.connect(_on_player_status_changed)
		if not MultiplayerGameManager.last_player_standing.is_connected(_on_last_player_standing):
			MultiplayerGameManager.last_player_standing.connect(_on_last_player_standing)
		if not MultiplayerGameManager.race_ended.is_connected(_on_multiplayer_race_ended):
			MultiplayerGameManager.race_ended.connect(_on_multiplayer_race_ended)
		if not MultiplayerGameManager.all_players_ready.is_connected(_on_all_players_ready):
			MultiplayerGameManager.all_players_ready.connect(_on_all_players_ready)
		if not _game.card_moved.is_connected(_on_multiplayer_card_moved):
			_game.card_moved.connect(_on_multiplayer_card_moved)
		
		print("Multiplayer game setup complete - is_multiplayer: ", MultiplayerGameManager.is_multiplayer)

func _on_new_game_pressed() -> void:
	# Play retry sound
	if SoundManager:
		SoundManager.play_retry()
	_new_game()

func _new_game() -> void:
	if MultiplayerGameManager and is_instance_valid(MultiplayerGameManager):
		if MultiplayerGameManager.is_multiplayer:
			if MultiplayerGameManager.is_host_player():
				MultiplayerGameManager.start_multiplayer_race()
				_setup_multiplayer_game()
		else:
			MultiplayerGameManager.start_local_game()
			_setup_single_player_game()

func _on_undo_pressed() -> void:
	if _game and is_instance_valid(_game):
		if _game.undo():
			_board.render()
			_update_undo_button_state()
			print("Undo successful")
		else:
			print("Cannot undo - no moves to undo or already undone")

func _update_undo_button_state() -> void:
	if _undo_button and is_instance_valid(_undo_button):
		if _game and is_instance_valid(_game):
			_undo_button.disabled = not _game.can_undo()
		else:
			_undo_button.disabled = true

func _on_card_moved(_from_pile: String, _to_pile: String, _card_count: int) -> void:
	# Update undo button state after any card move
	_update_undo_button_state()

func _on_back_to_menu_pressed() -> void:
	# Clean up network connections
	if NetworkManager and is_instance_valid(NetworkManager):
		if NetworkManager.multiplayer_peer:
			NetworkManager.multiplayer_peer.close()
			NetworkManager.multiplayer_peer = null
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer = null
		NetworkManager.is_host = false
		NetworkManager.players.clear()
	
	# Hide game control buttons
	for child in get_children():
		if child is Button and (child.name == "new_game" or child.name == "undo_button" or child.name == "menu_button"):
			child.queue_free()
	
	# Show main menu
	_show_main_menu()
	
	# Clear the board
	_board.set_game(null)
	_board.render()

func _show_multiplayer_lobby(as_host: bool, player_name: String) -> void:
	# Hide menu buttons
	_hide_menu_buttons()
	
	# Create and show lobby UI
	if _multiplayer_lobby:
		_multiplayer_lobby.queue_free()
	
	var lobby_script = load("res://scripts/MultiplayerLobby.gd")
	_multiplayer_lobby = Control.new()
	_multiplayer_lobby.set_script(lobby_script)
	_multiplayer_lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_multiplayer_lobby)
	
	# Wait for _ready to be called
	await get_tree().process_frame
	
	# Setup lobby based on role
	if as_host:
		_multiplayer_lobby.setup_as_host(player_name)
	else:
		_multiplayer_lobby.setup_as_client(player_name)
	
	# Connect signals
	_multiplayer_lobby.lobby_closed.connect(_on_lobby_closed)
	_multiplayer_lobby.game_started.connect(_on_multiplayer_game_started)

func _on_lobby_closed() -> void:
	if _multiplayer_lobby:
		_multiplayer_lobby.queue_free()
		_multiplayer_lobby = null
	
	# Show menu buttons again
	for child in get_children():
		if child is Button and child.name.begins_with("menu_"):
			child.visible = true

func _on_multiplayer_game_started() -> void:
	# Hide lobby
	if _multiplayer_lobby:
		_multiplayer_lobby.visible = false
	
	# Hide main menu and start multiplayer game
	_hide_main_menu()
	
	# Set multiplayer flag before starting game
	MultiplayerGameManager.is_multiplayer = true
	
	MultiplayerGameManager.start_local_game()
	_setup_multiplayer_game()

func _setup_multiplayer_ui() -> void:
	"""Setup UI elements specific to multiplayer mode"""
	# Player status label (bottom right, above undo button)
	_player_status_label = Label.new()
	_player_status_label.name = "PlayerStatusLabel"
	_player_status_label.position = Vector2(700, 650)  # Bottom right, above undo button
	_player_status_label.size = Vector2(300, 30)
	_player_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_player_status_label.text = "Playing: 0 | Jammed: 0 | Completed: 0"
	add_child(_player_status_label)

func _on_multiplayer_race_ended(winner_id: int, winner_name: String, time: float) -> void:
	"""Handle race completion - disable gameplay and show ready screen"""
	# Set waiting for ready flag to prevent status updates
	_waiting_for_ready = true
	
	# Disable all game interactions
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Disable all game buttons
	for child in get_children():
		if child is Button and (child.name == "new_game" or child.name == "undo_button"):
			child.disabled = true
	
	# Show ready notification
	_show_ready_notification(winner_id)

func _show_ready_notification(winner_id: int) -> void:
	"""Show notification with ready button after race ends"""
	# Remove old notification if exists
	if _last_standing_notification:
		_last_standing_notification.queue_free()
	
	# Create notification panel
	_last_standing_notification = Panel.new()
	_last_standing_notification.name = "RaceEndedNotification"
	_last_standing_notification.set_anchors_preset(Control.PRESET_CENTER)
	_last_standing_notification.anchor_left = 0.5
	_last_standing_notification.anchor_top = 0.5
	_last_standing_notification.anchor_right = 0.5
	_last_standing_notification.anchor_bottom = 0.5
	_last_standing_notification.offset_left = -200
	_last_standing_notification.offset_top = -100
	_last_standing_notification.offset_right = 200
	_last_standing_notification.offset_bottom = 100
	add_child(_last_standing_notification)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_last_standing_notification.add_child(vbox)
	
	var title = Label.new()
	var local_player_id = MultiplayerGameManager.get_local_player_id()
	
	if winner_id == -1:
		# No winner - all players jammed
		title.text = "Round Ended"
	elif winner_id == local_player_id:
		title.text = "You Won!"
	else:
		title.text = "Race Ended"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)
	
	var message = Label.new()
	if winner_id == -1:
		message.text = "All players are jammed. Ready up for next round!"
	elif winner_id == local_player_id:
		message.text = "Congratulations! You completed the game first!"
	else:
		message.text = "Another player has won the race."
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(message)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)
	
	# Ready button
	_ready_button = Button.new()
	_ready_button.text = "Ready for Next Round"
	_ready_button.custom_minimum_size = Vector2(200, 40)
	_ready_button.pressed.connect(_on_ready_pressed)
	vbox.add_child(_ready_button)

func _on_player_status_changed(player_id: int, status: String) -> void:
	"""Handle player status changes"""
	print("Player ", player_id, " status changed to: ", status)
	# Update UI to show player statuses
	_update_player_status_display()

func _on_last_player_standing(player_id: int) -> void:
	"""Show notification when player is last one standing"""
	# Create notification panel
	_last_standing_notification = Panel.new()
	_last_standing_notification.name = "LastStandingNotification"
	_last_standing_notification.set_anchors_preset(Control.PRESET_CENTER)
	_last_standing_notification.anchor_left = 0.5
	_last_standing_notification.anchor_top = 0.5
	_last_standing_notification.anchor_right = 0.5
	_last_standing_notification.anchor_bottom = 0.5
	_last_standing_notification.offset_left = -200
	_last_standing_notification.offset_top = -100
	_last_standing_notification.offset_right = 200
	_last_standing_notification.offset_bottom = 100
	add_child(_last_standing_notification)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_last_standing_notification.add_child(vbox)
	
	var title = Label.new()
	title.text = "Last Player Standing!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)
	
	var message = Label.new()
	message.text = "All other players are jammed or finished.\nYou can continue playing or start next round."
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(message)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)
	
	# Ready button
	_ready_button = Button.new()
	_ready_button.text = "Ready for Next Round"
	_ready_button.custom_minimum_size = Vector2(200, 40)
	_ready_button.pressed.connect(_on_ready_pressed)
	vbox.add_child(_ready_button)

func _on_ready_pressed() -> void:
	"""Handle ready button press"""
	MultiplayerGameManager.set_player_ready(true)
	if _ready_button:
		_ready_button.disabled = true
		_ready_button.text = "Waiting for others..."
	
	if _player_status_label:
		_player_status_label.text = "Waiting for all players to be ready..."

func _on_all_players_ready() -> void:
	"""Called when all players are ready to start new round"""
	print("All players ready - starting new round")
	
	# Clear waiting for ready flag
	_waiting_for_ready = false
	
	# Hide ready notification
	if _last_standing_notification:
		_last_standing_notification.queue_free()
		_last_standing_notification = null
	
	# Re-enable board interactions
	_board.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Setup new game
	var local_game = MultiplayerGameManager.get_local_game()
	if local_game and is_instance_valid(local_game):
		_game = local_game
		_board.set_game(_game)
		_board.render()
		
		# Reconnect card moved signal
		if not _game.card_moved.is_connected(_on_multiplayer_card_moved):
			_game.card_moved.connect(_on_multiplayer_card_moved)
	
	# Reset status label - will be updated by _update_player_status_display()
	if _player_status_label:
		_player_status_label.text = "Playing: 0 | Jammed: 0 | Completed: 0"

func _on_forfeit_pressed() -> void:
	"""Handle forfeit button press in multiplayer"""
	# Play lose sound
	if SoundManager:
		SoundManager.play_lose()
	
	# Mark player as jammed
	MultiplayerGameManager.forfeit_player()
	
	# Disable all game interactions
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Disable forfeit button
	for child in get_children():
		if child is Button and child.name == "new_game":
			child.disabled = true
			child.tooltip_text = "You have forfeited"
	
	# Show notification
	if _player_status_label:
		_player_status_label.text = "You have forfeited - waiting for others..."

func _on_multiplayer_card_moved(_from_pile: String, _to_pile: String, _card_count: int) -> void:
	"""Check player status after each move in multiplayer"""
	MultiplayerGameManager.check_player_status()
	_update_undo_button_state()

func _update_player_status_display() -> void:
	"""Update the player status label with current game state"""
	if not _player_status_label or not MultiplayerGameManager.is_multiplayer:
		return
	
	# Don't update status display if we're waiting for players to be ready
	if _waiting_for_ready:
		return
	
	var statuses = MultiplayerGameManager.player_statuses
	var playing = 0
	var jammed = 0
	var completed = 0
	
	for status in statuses.values():
		match status:
			MultiplayerGameManager.PlayerStatus.PLAYING:
				playing += 1
			MultiplayerGameManager.PlayerStatus.JAMMED:
				jammed += 1
			MultiplayerGameManager.PlayerStatus.COMPLETED:
				completed += 1
	
	_player_status_label.text = "Playing: %d | Jammed: %d | Completed: %d" % [playing, jammed, completed]
