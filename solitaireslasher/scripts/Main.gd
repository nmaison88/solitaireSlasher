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
var _player_name_input: LineEdit
var _difficulty_option: OptionButton
var _current_difficulty: String = "Medium"

func _ready() -> void:
	_status_label = get_node("StatusLabel") as Label
	_game = get_node("Game")
	_board = get_node("Board")
	
	# Add safe area margin for iPhone notch - move cards below top buttons
	# Buttons are 200x180 starting at y=110, ending at y=290, add 20px margin
	_board.position.y = 310
	
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
	_menu_container.offset_left = -200  # 2x larger (was -100)
	_menu_container.offset_top = -400  # 2x larger (was -200)
	_menu_container.offset_right = 200  # 2x larger (was 100)
	_menu_container.offset_bottom = 400  # 2x larger (was 200)
	_menu_container.add_theme_constant_override("separation", 20)  # 2x larger (was 10)
	add_child(_menu_container)
	
	# Title
	var title = Label.new()
	title.text = "Solitaire Slasher"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)  # 2x larger (was 32)
	_menu_container.add_child(title)
	
	# Player name input
	var name_label = Label.new()
	name_label.text = "Your Name:"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 32)  # 2x larger
	_menu_container.add_child(name_label)
	
	_player_name_input = LineEdit.new()
	_player_name_input.placeholder_text = "Enter your name"
	_player_name_input.text = PlayerData.get_player_name()  # Load saved name
	_player_name_input.custom_minimum_size = Vector2(400, 60)  # 2x larger (was 200x30)
	_player_name_input.add_theme_font_size_override("font_size", 32)  # 2x larger text
	_player_name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_container.add_child(_player_name_input)
	
	# Difficulty selection
	var difficulty_label = Label.new()
	difficulty_label.text = "Difficulty:"
	difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	difficulty_label.add_theme_font_size_override("font_size", 32)  # 2x larger (was 16 default)
	_menu_container.add_child(difficulty_label)
	
	_difficulty_option = OptionButton.new()
	_difficulty_option.add_item("Easy (Draw 1)")
	_difficulty_option.add_item("Medium (Draw 3)")
	_difficulty_option.add_item("Hard (Draw 3, Limited)")
	_difficulty_option.select(1)  # Default to Medium
	_difficulty_option.custom_minimum_size = Vector2(400, 60)  # 2x larger (was 200x30)
	_difficulty_option.add_theme_font_size_override("font_size", 32)  # 2x larger text
	_difficulty_option.item_selected.connect(_on_difficulty_changed)
	_menu_container.add_child(_difficulty_option)
	
	# Single Player button
	var single_player_button = Button.new()
	single_player_button.custom_minimum_size = Vector2(400, 80)  # 2x larger (was 200x40)
	single_player_button.pressed.connect(_on_single_player)
	
	var sp_hbox = HBoxContainer.new()
	sp_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	sp_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	single_player_button.add_child(sp_hbox)
	
	var sp_icon = FontAwesome.new()
	sp_icon.icon_name = "user"
	sp_icon.icon_type = "solid"
	sp_icon.icon_size = 40  # 2x larger (was 20)
	sp_hbox.add_child(sp_icon)
	
	var sp_spacer = Control.new()
	sp_spacer.custom_minimum_size = Vector2(20, 0)  # 2x larger (was 10)
	sp_hbox.add_child(sp_spacer)
	
	var sp_label = Label.new()
	sp_label.text = "Single Player"
	sp_label.add_theme_font_size_override("font_size", 32)  # 2x larger
	sp_hbox.add_child(sp_label)
	
	_menu_container.add_child(single_player_button)
	
	# Host Multiplayer button
	var host_button = Button.new()
	host_button.custom_minimum_size = Vector2(400, 80)  # 2x larger (was 200x40)
	host_button.pressed.connect(_on_host_game)
	
	var host_hbox = HBoxContainer.new()
	host_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	host_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	host_button.add_child(host_hbox)
	
	var host_icon = FontAwesome.new()
	host_icon.icon_name = "users"
	host_icon.icon_type = "solid"
	host_icon.icon_size = 40  # 2x larger (was 20)
	host_hbox.add_child(host_icon)
	
	var host_spacer = Control.new()
	host_spacer.custom_minimum_size = Vector2(20, 0)  # 2x larger (was 10)
	host_hbox.add_child(host_spacer)
	
	var host_label = Label.new()
	host_label.text = "Host Multiplayer"
	host_label.add_theme_font_size_override("font_size", 32)  # 2x larger
	host_hbox.add_child(host_label)
	
	_menu_container.add_child(host_button)
	
	# Join Multiplayer button
	var join_button = Button.new()
	join_button.custom_minimum_size = Vector2(400, 80)  # 2x larger (was 200x40)
	join_button.pressed.connect(_on_join_game)
	
	var join_hbox = HBoxContainer.new()
	join_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	join_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	join_button.add_child(join_hbox)
	
	var join_icon = FontAwesome.new()
	join_icon.icon_name = "user-plus"
	join_icon.icon_type = "solid"
	join_icon.icon_size = 40  # 2x larger (was 20)
	join_hbox.add_child(join_icon)
	
	var join_spacer = Control.new()
	join_spacer.custom_minimum_size = Vector2(20, 0)  # 2x larger (was 10)
	join_hbox.add_child(join_spacer)
	
	var join_label = Label.new()
	join_label.text = "Join Multiplayer"
	join_label.add_theme_font_size_override("font_size", 32)  # 2x larger
	join_hbox.add_child(join_label)
	
	_menu_container.add_child(join_button)

func _on_host_game() -> void:
	var player_name = _player_name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player" + str(randi() % 1000)
	
	# Save player name
	PlayerData.set_player_name(player_name)
	
	if NetworkManager.host_game(player_name):
		print("Hosting multiplayer game as: ", player_name)
		_show_multiplayer_lobby(true, player_name)
	else:
		print("Failed to host game")

func _on_join_game() -> void:
	var player_name = _player_name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player" + str(randi() % 1000)
	
	# Save player name
	PlayerData.set_player_name(player_name)
	
	# Show lobby with manual IP entry
	print("Joining multiplayer game as: ", player_name)
	_show_multiplayer_lobby(false, player_name)

func _show_main_menu() -> void:
	if _menu_container:
		_menu_container.visible = true
	_board.visible = false
	_status_label.visible = false
	# Hide and remove game buttons when showing menu
	for child in get_children():
		if child is Button and (child.name == "new_game" or child.name == "undo_button" or child.name == "menu_button"):
			child.queue_free()  # Remove buttons instead of just hiding them

func _hide_main_menu() -> void:
	if _menu_container:
		_menu_container.visible = false
	_board.visible = true
	_status_label.visible = true

func _on_difficulty_changed(index: int) -> void:
	"""Handle difficulty selection change"""
	match index:
		0:
			_current_difficulty = "Easy"
		1:
			_current_difficulty = "Medium"
		2:
			_current_difficulty = "Hard"
	print("Difficulty changed to: ", _current_difficulty)

func _on_single_player() -> void:
	MultiplayerGameManager.is_multiplayer = false
	MultiplayerGameManager.start_local_game()
	_hide_main_menu()  # Hide menu and show board
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
		# Set difficulty before rendering
		_game.set_difficulty(_current_difficulty)
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
	new_game_button.position = Vector2(812, 110)  # Moved down 100px for notch, adjusted for larger size
	new_game_button.size = Vector2(200, 180)  # Match undo button size
	new_game_button.flat = true  # Remove button background
	
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
		forfeit_icon.icon_size = 100  # Match undo icon size
		forfeit_icon.modulate = Color(1.0, 0.9, 0.0)  # Yellow color
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
		retry_icon.icon_size = 100  # Match undo icon size
		retry_icon.modulate = Color(1.0, 0.9, 0.0)  # Yellow color
		retry_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		retry_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		new_game_button.add_child(retry_icon)
	
	add_child(new_game_button)
	
	# Undo button (bottom quarter of screen) - FontAwesome icon with label below
	var undo_button = Button.new()
	undo_button.name = "undo_button"
	undo_button.position = Vector2(412, 1050)  # Bottom 4th of screen (1366 * 0.75 = 1025), centered
	undo_button.size = Vector2(200, 180)  # 2x larger (was 100x90)
	undo_button.flat = true  # Remove button background
	undo_button.tooltip_text = "Undo Last Move"
	undo_button.pressed.connect(_on_undo_pressed)
	
	# Create VBox container for vertical icon + text layout
	var undo_vbox = VBoxContainer.new()
	undo_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	undo_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	undo_button.add_child(undo_vbox)
	
	# Add FontAwesome icon
	var undo_icon = FontAwesome.new()
	undo_icon.icon_name = "rotate-left"
	undo_icon.icon_type = "solid"
	undo_icon.icon_size = 100  # 2x larger (was 50)
	undo_icon.modulate = Color(1.0, 0.9, 0.0)  # Yellow color
	undo_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	undo_vbox.add_child(undo_icon)
	
	# Add small spacer
	var undo_spacer = Control.new()
	undo_spacer.custom_minimum_size = Vector2(0, 8)  # 2x larger (was 4)
	undo_vbox.add_child(undo_spacer)
	
	# Add text label below icon
	var undo_label = Label.new()
	undo_label.text = "Undo"
	undo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	undo_label.add_theme_font_size_override("font_size", 32)  # 2x larger (was 16)
	undo_label.modulate = Color(1.0, 0.9, 0.0)  # Yellow color to match icon
	undo_vbox.add_child(undo_label)
	
	add_child(undo_button)
	
	# Store reference to undo button for state updates
	_undo_button = undo_button
	_update_undo_button_state()
	
	# Menu button (top left) - FontAwesome icon
	var menu_button = Button.new()
	menu_button.name = "menu_button"
	menu_button.position = Vector2(10, 110)  # Moved down 100px for notch
	menu_button.size = Vector2(200, 180)  # Match undo button size
	menu_button.flat = true  # Remove button background
	menu_button.tooltip_text = "Main Menu"
	menu_button.pressed.connect(_on_back_to_menu_pressed)
	
	# Add FontAwesome icon as child
	var menu_icon = FontAwesome.new()
	menu_icon.icon_name = "bars"  # Hamburger menu icon
	menu_icon.icon_type = "solid"
	menu_icon.icon_size = 100  # Match undo icon size
	menu_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_button.add_child(menu_icon)
	
	add_child(menu_button)
	_menu_button = menu_button

func _setup_multiplayer_game() -> void:
	var local_game = MultiplayerGameManager.get_local_game()
	if local_game and is_instance_valid(local_game):
		_game = local_game
		# Set difficulty before rendering
		_game.set_difficulty(_current_difficulty)
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
	# Hide main menu
	if _menu_container:
		_menu_container.visible = false
	
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
	
	NetworkManager.leave_game()
	
	# Show main menu again
	_show_main_menu()

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
