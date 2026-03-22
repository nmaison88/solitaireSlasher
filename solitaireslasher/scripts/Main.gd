extends Control

var _status_label: Label
var _game: Node
var _board: Node

var _multiplayer_ui: Control
var _lobby_ui: Control
var _game_ui: Control
var _multiplayer_lobby: Control
var _undo_button: Button

func _ready() -> void:
	_status_label = get_node("StatusLabel") as Label
	_game = get_node("Game")
	_board = get_node("Board")
	
	_setup_ui()
	# Don't auto-start game, let user choose from menu

func _setup_ui() -> void:
	# Clear existing UI elements first
	for child in get_children():
		if child is Button and child.name.begins_with("menu_"):
			child.queue_free()
	
	# Create main menu buttons
	var host_button = Button.new()
	host_button.name = "menu_host"
	host_button.text = "Host Multiplayer Game"
	host_button.pressed.connect(_on_host_game)
	add_child(host_button)
	
	var join_button = Button.new()
	join_button.name = "menu_join"
	join_button.text = "Join Multiplayer Game"
	join_button.pressed.connect(_on_join_game)
	add_child(join_button)
	
	var single_button = Button.new()
	single_button.name = "menu_single"
	single_button.text = "Single Player"
	single_button.pressed.connect(_on_single_player)
	add_child(single_button)
	
	# Position buttons in top-left corner, away from the game board
	host_button.position = Vector2(10, 10)
	join_button.position = Vector2(10, 50)
	single_button.position = Vector2(10, 90)

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

func _on_single_player() -> void:
	MultiplayerGameManager.start_local_game()
	_setup_single_player_game()

func _start_multiplayer_game() -> void:
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
	
	# New Game button (top right) - FontAwesome icon
	var new_game_button = Button.new()
	new_game_button.name = "new_game"
	new_game_button.position = Vector2(950, 10)
	new_game_button.size = Vector2(50, 50)
	new_game_button.tooltip_text = "New Game"
	new_game_button.pressed.connect(_on_new_game_pressed)
	
	# Add FontAwesome icon as child
	var retry_icon = FontAwesome.new()
	retry_icon.icon_name = "rotate-right"  # or "arrows-rotate" or "refresh"
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
	
	# Back to Menu button (keep text for now, top right below new game)
	var menu_button = Button.new()
	menu_button.name = "menu_button"
	menu_button.text = "Back to Menu"
	menu_button.position = Vector2(850, 70)
	menu_button.pressed.connect(_on_back_to_menu_pressed)
	add_child(menu_button)

func _setup_multiplayer_game() -> void:
	var local_game = MultiplayerGameManager.get_local_game()
	if local_game and is_instance_valid(local_game):
		_game = local_game
		_board.set_game(_game)
		_board.set_multiplayer_manager(MultiplayerGameManager)
		_board.render()

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
	# Show menu buttons again
	for child in get_children():
		if child is Button and child.name.begins_with("menu_"):
			child.visible = true
	
	# Hide game control buttons
	for child in get_children():
		if child is Button and (child.name == "new_game" or child.name == "undo_button" or child.name == "menu_button"):
			child.queue_free()
	
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
	
	# Start multiplayer game
	MultiplayerGameManager.start_local_game()
	_setup_multiplayer_game()
