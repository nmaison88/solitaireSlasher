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

# Sudoku-specific variables
var _sudoku_game: SudokuGame
var _sudoku_board: SudokuBoard
var _waiting_for_ready: bool = false

# Game type and difficulty selection
var _player_name_input: LineEdit
var _difficulty_option: OptionButton
var _current_difficulty: String = "Medium"
var _game_type_option: OptionButton
var _current_game_type: String = "Solitaire"  # "Solitaire" or "Sudoku"

func _ready() -> void:
	# Force portrait orientation on mobile devices
	if OS.has_feature("mobile"):
		print("=== FORCING PORTRAIT ORIENTATION ===")
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
		print("Orientation set to: ", DisplayServer.screen_get_orientation(DisplayServer.SCREEN_OF_MAIN_WINDOW))
		print("Window size: ", DisplayServer.window_get_size())
		print("Viewport size: ", get_viewport().size)
		
		# Get safe area to avoid notch
		var safe_area = DisplayServer.get_display_safe_area()
		print("Safe area: ", safe_area)
	
	_status_label = get_node("StatusLabel") as Label
	_game = get_node("Game")
	_board = get_node("Board")
	
	# Add top padding for safe area (iPhone notch) and larger buttons
	if OS.has_feature("mobile"):
		var safe_area = DisplayServer.get_display_safe_area()
		var top_padding = safe_area.position.y
		print("Adding top padding: ", top_padding)
		
		# Offset Board to avoid notch and larger buttons (100px buttons + padding)
		_board.offset_top = top_padding + 120  # Extra 120px for larger buttons
		
		# Offset StatusLabel to avoid notch and buttons
		_status_label.offset_top = 48 + top_padding + 120
	
	# Add blue background for both Solitaire and Sudoku
	var game_background = ColorRect.new()
	game_background.name = "GameBackground"
	game_background.color = Color(0.2, 0.4, 0.7)  # Blue background
	game_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_background.z_index = -1  # Behind everything
	game_background.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block input
	game_background.visible = false
	add_child(game_background)
	
	# Create Sudoku game and board
	_sudoku_game = SudokuGame.new()
	add_child(_sudoku_game)
	
	_sudoku_board = SudokuBoard.new()
	_sudoku_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sudoku_board.visible = false
	add_child(_sudoku_board)
	
	# Add top padding for Sudoku board to avoid notch and larger buttons
	if OS.has_feature("mobile"):
		var safe_area = DisplayServer.get_display_safe_area()
		var top_padding = safe_area.position.y
		_sudoku_board.offset_top = top_padding + 120  # Extra 120px for larger buttons
	
	# Hide game elements on startup
	_board.visible = false
	_sudoku_board.visible = false
	_status_label.visible = false
	
	_setup_main_menu()
	_show_main_menu()
	
	# Connect to NetworkManager signals for disconnect handling
	if NetworkManager:
		NetworkManager.multiplayer.server_disconnected.connect(_on_server_disconnected)
		NetworkManager.player_disconnected.connect(_on_player_disconnected)

func _setup_main_menu() -> void:
	# Add blue background for menu
	var menu_background = ColorRect.new()
	menu_background.name = "MenuBackground"
	menu_background.color = Color(0.2, 0.4, 0.7)  # Blue background
	menu_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_background.z_index = -2  # Behind game background
	menu_background.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block input
	add_child(menu_background)
	
	# Create centered menu container
	_menu_container = VBoxContainer.new()
	_menu_container.name = "MainMenuContainer"
	_menu_container.set_anchors_preset(Control.PRESET_CENTER)
	_menu_container.anchor_left = 0.5
	_menu_container.anchor_top = 0.5
	_menu_container.anchor_right = 0.5
	_menu_container.anchor_bottom = 0.5
	_menu_container.offset_left = -250
	_menu_container.offset_top = -350
	_menu_container.offset_right = 250
	_menu_container.offset_bottom = 350
	_menu_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu_container.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_menu_container)
	
	# Add title
	var title = Label.new()
	title.text = "Solitaire Slasher"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	_menu_container.add_child(title)
	
	# Add spacing
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 60)
	_menu_container.add_child(spacer1)
	
	# Create main menu buttons
	var single_button = Button.new()
	single_button.name = "menu_single"
	single_button.text = "Single Player"
	single_button.custom_minimum_size = Vector2(400, 100)
	single_button.add_theme_font_size_override("font_size", 36)
	single_button.pressed.connect(_on_show_single_player_menu)
	_menu_container.add_child(single_button)
	
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	_menu_container.add_child(spacer2)
	
	var multiplayer_button = Button.new()
	multiplayer_button.name = "menu_multiplayer"
	multiplayer_button.text = "Multiplayer"
	multiplayer_button.custom_minimum_size = Vector2(400, 100)
	multiplayer_button.add_theme_font_size_override("font_size", 36)
	multiplayer_button.pressed.connect(_on_show_multiplayer_menu)
	_menu_container.add_child(multiplayer_button)
	
	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 20)
	_menu_container.add_child(spacer3)
	
	var settings_button = Button.new()
	settings_button.name = "menu_settings"
	settings_button.text = "Settings"
	settings_button.custom_minimum_size = Vector2(400, 100)
	settings_button.add_theme_font_size_override("font_size", 36)
	settings_button.disabled = true  # Will implement later
	_menu_container.add_child(settings_button)

func _on_show_single_player_menu() -> void:
	"""Show single player submenu with carousels for game type and difficulty"""
	# Hide main menu
	_menu_container.visible = false
	
	# Create single player menu container - wider to accommodate larger carousel
	var sp_menu = VBoxContainer.new()
	sp_menu.name = "SinglePlayerMenu"
	sp_menu.set_anchors_preset(Control.PRESET_CENTER)
	sp_menu.anchor_left = 0.5
	sp_menu.anchor_top = 0.5
	sp_menu.anchor_right = 0.5
	sp_menu.anchor_bottom = 0.5
	sp_menu.offset_left = -450  # Wider to fit 800px carousel
	sp_menu.offset_top = -400
	sp_menu.offset_right = 450
	sp_menu.offset_bottom = 400
	add_child(sp_menu)
	
	# Title
	var title = Label.new()
	title.text = "Single Player"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	sp_menu.add_child(title)
	
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 40)
	sp_menu.add_child(spacer1)
	
	# Game Type Carousel (Horizontal) with Icons using FreeControl
	var game_type_label = Label.new()
	game_type_label.text = "Game Type"
	game_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_type_label.add_theme_font_size_override("font_size", 36)
	sp_menu.add_child(game_type_label)
	
	# Create carousel container - MUCH LARGER and more prominent
	var game_carousel = Carousel.new()
	game_carousel.custom_minimum_size = Vector2(800, 400)
	game_carousel.item_size = Vector2(350, 350)
	game_carousel.item_seperation = 100
	game_carousel.carousel_angle = 0  # Horizontal
	game_carousel.allow_loop = true
	game_carousel.display_loop = true
	game_carousel.snap_behavior = Carousel.SNAP_BEHAVIOR.SNAP
	game_carousel.can_drag = true
	game_carousel.manual_end.connect(_on_game_carousel_changed)
	game_carousel.snap_end.connect(_on_game_carousel_changed)
	
	# Add game icons as TextureRect children - LARGER
	var solitaire_icon = TextureRect.new()
	solitaire_icon.texture = load("res://game icons/solitaire_icon.png")
	solitaire_icon.custom_minimum_size = Vector2(350, 350)
	solitaire_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	solitaire_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	solitaire_icon.name = "Solitaire"
	game_carousel.add_child(solitaire_icon)
	
	var sudoku_icon = TextureRect.new()
	sudoku_icon.texture = load("res://game icons/sudoku_icon.png")
	sudoku_icon.custom_minimum_size = Vector2(350, 350)
	sudoku_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	sudoku_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sudoku_icon.name = "Sudoku"
	game_carousel.add_child(sudoku_icon)
	
	sp_menu.add_child(game_carousel)
	
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 40)
	sp_menu.add_child(spacer2)
	
	# Difficulty Carousel (Vertical) using FreeControl
	var difficulty_label = Label.new()
	difficulty_label.text = "Difficulty"
	difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	difficulty_label.add_theme_font_size_override("font_size", 36)
	sp_menu.add_child(difficulty_label)
	
	# Create vertical carousel for difficulty
	var difficulty_carousel = Carousel.new()
	difficulty_carousel.custom_minimum_size = Vector2(400, 250)
	difficulty_carousel.item_size = Vector2(300, 60)
	difficulty_carousel.item_seperation = 20
	difficulty_carousel.carousel_angle = 90  # Vertical
	difficulty_carousel.allow_loop = true
	difficulty_carousel.display_loop = true
	difficulty_carousel.snap_behavior = Carousel.SNAP_BEHAVIOR.SNAP
	difficulty_carousel.can_drag = true
	difficulty_carousel.starting_index = 1  # Default to Medium
	difficulty_carousel.manual_end.connect(_on_difficulty_carousel_changed)
	difficulty_carousel.snap_end.connect(_on_difficulty_carousel_changed)
	
	# Add difficulty labels as children
	for i in range(3):
		var diff = ["Easy", "Medium", "Hard"][i]
		var diff_label = Label.new()
		diff_label.text = diff
		diff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		diff_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		diff_label.custom_minimum_size = Vector2(300, 60)
		# Selected item (Medium at index 1) starts larger
		if i == 1:
			diff_label.add_theme_font_size_override("font_size", 56)
		else:
			diff_label.add_theme_font_size_override("font_size", 36)
		diff_label.name = diff
		difficulty_carousel.add_child(diff_label)
	
	sp_menu.add_child(difficulty_carousel)
	
	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 40)
	sp_menu.add_child(spacer3)
	
	# Start button
	var start_button = Button.new()
	start_button.text = "Start Game"
	start_button.custom_minimum_size = Vector2(400, 80)
	start_button.add_theme_font_size_override("font_size", 36)
	start_button.pressed.connect(_on_single_player_start)
	sp_menu.add_child(start_button)
	
	var spacer4 = Control.new()
	spacer4.custom_minimum_size = Vector2(0, 20)
	sp_menu.add_child(spacer4)
	
	# Back button
	var back_button = Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(400, 80)
	back_button.add_theme_font_size_override("font_size", 36)
	back_button.pressed.connect(_on_single_player_back)
	sp_menu.add_child(back_button)

func _on_show_multiplayer_menu() -> void:
	"""Show multiplayer submenu with Host/Join buttons"""
	# Hide main menu
	_menu_container.visible = false
	
	# Create multiplayer menu container
	var mp_menu = VBoxContainer.new()
	mp_menu.name = "MultiplayerMenu"
	mp_menu.set_anchors_preset(Control.PRESET_CENTER)
	mp_menu.anchor_left = 0.5
	mp_menu.anchor_top = 0.5
	mp_menu.anchor_right = 0.5
	mp_menu.anchor_bottom = 0.5
	mp_menu.offset_left = -250
	mp_menu.offset_top = -250
	mp_menu.offset_right = 250
	mp_menu.offset_bottom = 250
	add_child(mp_menu)
	
	# Title
	var title = Label.new()
	title.text = "Multiplayer"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	mp_menu.add_child(title)
	
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 60)
	mp_menu.add_child(spacer1)
	
	# Host button
	var host_button = Button.new()
	host_button.text = "Host Multiplayer"
	host_button.custom_minimum_size = Vector2(400, 100)
	host_button.add_theme_font_size_override("font_size", 36)
	host_button.pressed.connect(_on_host_game)
	mp_menu.add_child(host_button)
	
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	mp_menu.add_child(spacer2)
	
	# Join button
	var join_button = Button.new()
	join_button.text = "Join Multiplayer"
	join_button.custom_minimum_size = Vector2(400, 100)
	join_button.add_theme_font_size_override("font_size", 36)
	join_button.pressed.connect(_on_join_game)
	mp_menu.add_child(join_button)
	
	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 60)
	mp_menu.add_child(spacer3)
	
	# Back button
	var back_button = Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(400, 80)
	back_button.add_theme_font_size_override("font_size", 36)
	back_button.pressed.connect(_on_multiplayer_back)
	mp_menu.add_child(back_button)

func _on_game_carousel_changed():
	# Get the current index from the carousel
	var sp_menu = get_node_or_null("SinglePlayerMenu")
	if sp_menu:
		for child in sp_menu.get_children():
			if child is Carousel and child.get_child_count() > 0:
				var first_child = child.get_child(0)
				if first_child.name == "Solitaire" or first_child.name == "Sudoku":
					var current_index = child.get_current_carousel_index()
					var game_names = ["Solitaire", "Sudoku"]
					if current_index >= 0 and current_index < game_names.size():
						_current_game_type = game_names[current_index]
						print("Game type changed to: ", _current_game_type)
					break

func _on_difficulty_carousel_changed():
	# Get the current index from the difficulty carousel
	var sp_menu = get_node_or_null("SinglePlayerMenu")
	if sp_menu:
		for child in sp_menu.get_children():
			if child is Carousel and child.get_child_count() > 0:
				var first_child = child.get_child(0)
				if first_child.name == "Easy" or first_child.name == "Medium" or first_child.name == "Hard":
					var current_index = child.get_current_carousel_index()
					var difficulties = ["Easy", "Medium", "Hard"]
					if current_index >= 0 and current_index < difficulties.size():
						_current_difficulty = difficulties[current_index]
						print("Difficulty changed to: ", _current_difficulty)
						
						# Update font sizes - make selected item larger
						for i in range(child.get_child_count()):
							var label = child.get_child(i)
							if label is Label:
								if i == current_index:
									label.add_theme_font_size_override("font_size", 56)  # Selected
								else:
									label.add_theme_font_size_override("font_size", 36)  # Not selected
					break

func _on_single_player_start():
	# Remove single player menu
	var sp_menu = get_node_or_null("SinglePlayerMenu")
	if sp_menu:
		sp_menu.queue_free()
	
	# Start the game
	_on_single_player()

func _on_single_player_back():
	# Remove single player menu
	var sp_menu = get_node_or_null("SinglePlayerMenu")
	if sp_menu:
		sp_menu.queue_free()
	
	# Show main menu
	_menu_container.visible = true

func _on_multiplayer_back():
	# Remove multiplayer menu
	var mp_menu = get_node_or_null("MultiplayerMenu")
	if mp_menu:
		mp_menu.queue_free()
	
	# Show main menu
	_menu_container.visible = true

func _on_host_game() -> void:
	# Hide multiplayer menu
	var mp_menu = get_node_or_null("MultiplayerMenu")
	if mp_menu:
		mp_menu.queue_free()
	
	var player_name = "Player" + str(randi() % 1000)
	if NetworkManager.host_game(player_name):
		print("Hosting multiplayer game")
		_show_multiplayer_lobby(true, player_name)
	else:
		print("Failed to host game")

func _on_join_game() -> void:
	# Hide multiplayer menu
	var mp_menu = get_node_or_null("MultiplayerMenu")
	if mp_menu:
		mp_menu.queue_free()
	
	# Show lobby with manual IP entry
	_show_multiplayer_lobby(false, "Player" + str(randi() % 1000))

func _show_main_menu() -> void:
	if _menu_container:
		_menu_container.visible = true
	_board.visible = false
	_sudoku_board.visible = false
	_status_label.visible = false
	
	# Show menu background
	var menu_bg = get_node_or_null("MenuBackground")
	if menu_bg:
		menu_bg.visible = true
	
	# Hide blue game background when in menu
	var game_bg = get_node_or_null("GameBackground")
	if game_bg:
		game_bg.visible = false
	
	# Hide game control buttons
	for child in get_children():
		if child is Button and (child.name == "new_game" or child.name == "undo_button" or child.name == "menu_button"):
			child.visible = false

func _hide_main_menu() -> void:
	if _menu_container:
		_menu_container.visible = false
	
	# Hide menu background
	var menu_bg = get_node_or_null("MenuBackground")
	if menu_bg:
		menu_bg.visible = false
	
	# Show blue background for game
	var game_bg = get_node_or_null("GameBackground")
	if game_bg:
		game_bg.visible = true
	
	# Show appropriate board based on game type
	if _current_game_type == "Solitaire":
		_board.visible = true
		_sudoku_board.visible = false
	else:  # Sudoku
		_board.visible = false
		_sudoku_board.visible = true
	
	_status_label.visible = true

func _on_game_type_changed(index: int) -> void:
	"""Handle game type selection change"""
	match index:
		0:
			_current_game_type = "Solitaire"
		1:
			_current_game_type = "Sudoku"
	print("Game type changed to: ", _current_game_type)

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
	# Clean up any existing game state
	_cleanup_game_state()
	
	_hide_main_menu()
	
	if _current_game_type == "Solitaire":
		MultiplayerGameManager.start_local_game(_current_difficulty)
		_setup_single_player_game()
	else:  # Sudoku
		_setup_single_player_sudoku()

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

func _setup_single_player_sudoku() -> void:
	print("Setting up single player Sudoku...")
	
	# Clear status label
	_status_label.text = ""
	
	# Get difficulty level (1=Easy, 3=Medium, 5=Hard)
	var difficulty_level = 3  # Default to Medium
	match _current_difficulty:
		"Easy":
			difficulty_level = 1
		"Medium":
			difficulty_level = 3
		"Hard":
			difficulty_level = 5
	
	# Start new Sudoku game
	_sudoku_game.new_game(difficulty_level, true)
	_sudoku_board.set_game(_sudoku_game)
	
	# Connect signals
	if not _sudoku_game.puzzle_completed.is_connected(_on_sudoku_completed):
		_sudoku_game.puzzle_completed.connect(_on_sudoku_completed)
	if not _sudoku_game.game_over.is_connected(_on_sudoku_game_over):
		_sudoku_game.game_over.connect(_on_sudoku_game_over)
	
	# Hide menu buttons
	_hide_menu_buttons()
	
	# Show game buttons (menu button only, no undo for Sudoku)
	_show_new_game_button()
	
	print("Sudoku game setup complete")

func _on_sudoku_completed() -> void:
	print("Sudoku puzzle completed!")
	_status_label.text = "Puzzle Completed!"
	if SoundManager:
		SoundManager.play_win()

func _on_sudoku_game_over() -> void:
	print("Sudoku game over - out of lives")
	_status_label.text = "Game Over - Out of Lives"
	if SoundManager:
		SoundManager.play_lose()

func _hide_menu_buttons():
	for child in get_children():
		if child is Button and child.name.begins_with("menu_"):
			child.visible = false

func _show_new_game_button():
	# Remove existing game control buttons if any (immediate removal to prevent duplicates)
	var buttons_to_remove = []
	for child in get_children():
		if child is Button and (child.name == "new_game" or child.name == "undo_button" or child.name == "menu_button"):
			buttons_to_remove.append(child)
	
	for button in buttons_to_remove:
		remove_child(button)
		button.queue_free()
	
	# Clear undo button reference
	_undo_button = null
	
	# New Game/Forfeit button (top right) - FontAwesome icon
	# In multiplayer mode, this becomes a forfeit button
	var new_game_button = Button.new()
	new_game_button.name = "new_game"
	
	# Get safe area padding for iPhone notch/rounded corners
	var top_padding = 10
	if OS.has_feature("mobile"):
		var safe_area = DisplayServer.get_display_safe_area()
		top_padding = max(10, safe_area.position.y)
	
	new_game_button.position = Vector2(900, top_padding)  # Moved left and down for safe area
	new_game_button.size = Vector2(100, 100)  # 2x larger (was 50x50)
	
	# Make button background transparent
	var new_game_transparent_style = StyleBoxFlat.new()
	new_game_transparent_style.bg_color = Color(0, 0, 0, 0)  # Fully transparent
	new_game_transparent_style.draw_center = false  # Don't draw background
	new_game_button.add_theme_stylebox_override("normal", new_game_transparent_style)
	new_game_button.add_theme_stylebox_override("hover", new_game_transparent_style)
	new_game_button.add_theme_stylebox_override("pressed", new_game_transparent_style)
	new_game_button.add_theme_stylebox_override("disabled", new_game_transparent_style)
	
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
		forfeit_icon.icon_size = 64  # 2x larger (was 32)
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
		retry_icon.icon_size = 64  # 2x larger (was 32)
		retry_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		retry_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		new_game_button.add_child(retry_icon)
	
	add_child(new_game_button)
	
	# Undo button (bottom center) - FontAwesome icon
	# Only show for Solitaire, not Sudoku
	var undo_button = Button.new()
	undo_button.name = "undo_button"
	
	# Use anchors to position at bottom center, works on any screen size
	undo_button.anchor_left = 0.5
	undo_button.anchor_right = 0.5
	undo_button.anchor_top = 1.0
	undo_button.anchor_bottom = 1.0
	undo_button.offset_left = -50  # Half of button width (100/2)
	undo_button.offset_right = 50   # Half of button width (100/2)
	undo_button.offset_top = -120  # Button height + padding from bottom
	undo_button.offset_bottom = -20  # Padding from bottom
	undo_button.custom_minimum_size = Vector2(100, 100)  # 2x larger (was 50x50)
	undo_button.tooltip_text = "Undo Last Move"
	undo_button.pressed.connect(_on_undo_pressed)
	undo_button.visible = (_current_game_type == "Solitaire")  # Hide for Sudoku
	
	print("Undo button positioned with anchors at bottom center")
	
	# Make button background transparent
	var transparent_style = StyleBoxFlat.new()
	transparent_style.bg_color = Color(0, 0, 0, 0)  # Fully transparent
	transparent_style.draw_center = false  # Don't draw background
	undo_button.add_theme_stylebox_override("normal", transparent_style)
	undo_button.add_theme_stylebox_override("hover", transparent_style)
	undo_button.add_theme_stylebox_override("pressed", transparent_style)
	undo_button.add_theme_stylebox_override("disabled", transparent_style)
	
	# Add FontAwesome icon as child
	var undo_icon = FontAwesome.new()
	undo_icon.icon_name = "rotate-left"
	undo_icon.icon_type = "solid"
	undo_icon.icon_size = 64  # 2x larger (was 32)
	undo_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	undo_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	undo_button.add_child(undo_icon)
	
	add_child(undo_button)
	
	# Store reference to undo button for state updates
	_undo_button = undo_button
	if _current_game_type == "Solitaire":
		_update_undo_button_state()
	
	# Menu button (top left) - FontAwesome icon
	var menu_button = Button.new()
	menu_button.name = "menu_button"
	menu_button.position = Vector2(10, top_padding)  # Use safe area padding
	menu_button.size = Vector2(100, 100)  # 2x larger (was 50x50)
	menu_button.tooltip_text = "Main Menu"
	menu_button.pressed.connect(_on_back_to_menu_pressed)
	
	# Make button background transparent
	var menu_transparent_style = StyleBoxFlat.new()
	menu_transparent_style.bg_color = Color(0, 0, 0, 0)  # Fully transparent
	menu_transparent_style.draw_center = false  # Don't draw background
	menu_button.add_theme_stylebox_override("normal", menu_transparent_style)
	menu_button.add_theme_stylebox_override("hover", menu_transparent_style)
	menu_button.add_theme_stylebox_override("pressed", menu_transparent_style)
	menu_button.add_theme_stylebox_override("disabled", menu_transparent_style)
	
	# Add FontAwesome icon as child
	var menu_icon = FontAwesome.new()
	menu_icon.icon_name = "bars"  # Hamburger menu icon
	menu_icon.icon_type = "solid"
	menu_icon.icon_size = 64  # 2x larger (was 32)
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
	if _current_game_type == "Sudoku":
		# Restart Sudoku game
		_setup_single_player_sudoku()
	elif MultiplayerGameManager and is_instance_valid(MultiplayerGameManager):
		if MultiplayerGameManager.is_multiplayer:
			if MultiplayerGameManager.is_host_player():
				MultiplayerGameManager.start_multiplayer_race()
				_setup_multiplayer_game()
		else:
			MultiplayerGameManager.start_local_game(_current_difficulty)
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

func _cleanup_game_state() -> void:
	"""Clean up all game state before starting a new game or returning to menu"""
	# Clear the boards
	_board.set_game(null)
	_board.render()
	
	# Hide both boards
	_board.visible = false
	_sudoku_board.visible = false
	
	# Hide status label
	_status_label.visible = false
	
	# Hide and remove game control buttons (including leave game button)
	for child in get_children():
		if child is Button and (child.name == "new_game" or child.name == "undo_button" or child.name == "menu_button" or child.name == "leave_game_button"):
			child.visible = false
			child.queue_free()
	
	# Hide multiplayer lobby if visible
	if _multiplayer_lobby and is_instance_valid(_multiplayer_lobby):
		_multiplayer_lobby.visible = false
	
	# Hide any ready notifications
	if _last_standing_notification and is_instance_valid(_last_standing_notification):
		_last_standing_notification.queue_free()
		_last_standing_notification = null
	
	# Hide player status label
	if _player_status_label and is_instance_valid(_player_status_label):
		_player_status_label.visible = false

func _on_server_disconnected() -> void:
	"""Handle when host closes the server (host left the game)"""
	print("Host has left the game - returning to main menu")
	
	# Show notification
	if _status_label:
		_status_label.text = "Host left the game"
		_status_label.visible = true
	
	# Clean up and return to menu
	_cleanup_game_state()
	_show_main_menu()

func _on_player_disconnected(player_id: int) -> void:
	"""Handle when a client disconnects (player dropped out)"""
	if NetworkManager and NetworkManager.is_host:
		print("Player ", player_id, " dropped out of the game")
		# Update player status display if visible
		_update_player_status_display()
	# Note: Clients will get server_disconnected if host leaves, not this signal

func _on_leave_game_pressed() -> void:
	"""Handle leave game button press during multiplayer"""
	print("Leave game pressed")
	
	if NetworkManager and is_instance_valid(NetworkManager):
		if NetworkManager.is_host:
			# Host is leaving - close the server and disconnect all clients
			print("Host leaving game - closing server")
			NetworkManager.leave_game()
		else:
			# Client is leaving - just disconnect from host
			print("Client leaving game")
			NetworkManager.leave_game()
	
	# Clean up and return to menu
	_cleanup_game_state()
	_show_main_menu()

func _on_back_to_menu_pressed() -> void:
	# Clean up game state
	_cleanup_game_state()
	
	# Disconnect from multiplayer if connected
	if NetworkManager and is_instance_valid(NetworkManager):
		if NetworkManager.multiplayer_peer:
			NetworkManager.multiplayer_peer.close()
			NetworkManager.multiplayer_peer = null
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer = null
		NetworkManager.is_host = false
		NetworkManager.players.clear()
	
	# Show main menu
	_show_main_menu()
	
	# Clear the board
	_board.set_game(null)
	_board.render()

func _show_multiplayer_lobby(as_host: bool, player_name: String) -> void:
	# Hide main menu
	if _menu_container:
		_menu_container.visible = false
	
	# Hide menu background
	var menu_bg = get_node_or_null("MenuBackground")
	if menu_bg:
		menu_bg.visible = false
	
	# IMPORTANT: Hide all game boards when showing lobby
	_board.visible = false
	_sudoku_board.visible = false
	_status_label.visible = false
	
	# Hide game background
	var game_bg = get_node_or_null("GameBackground")
	if game_bg:
		game_bg.visible = false
	
	# Hide any game control buttons
	for child in get_children():
		if child is Button and (child.name == "new_game" or child.name == "undo_button" or child.name == "menu_button"):
			child.visible = false
	
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
	
	# Show main menu again
	_show_main_menu()

func _on_multiplayer_game_started(game_type: String, difficulty: String) -> void:
	# Clean up any previous game state
	_cleanup_game_state()
	
	# Hide lobby
	if _multiplayer_lobby:
		_multiplayer_lobby.visible = false
	
	# Store game type and difficulty from host
	_current_game_type = game_type
	_current_difficulty = difficulty
	print("Starting multiplayer game - Type: ", game_type, ", Difficulty: ", difficulty)
	
	# Hide main menu and start multiplayer game
	_hide_main_menu()
	
	# Set multiplayer flag before starting game
	MultiplayerGameManager.is_multiplayer = true
	
	# Start appropriate game type
	if game_type == "Sudoku":
		_setup_multiplayer_sudoku()
	else:  # Solitaire
		MultiplayerGameManager.start_local_game(difficulty)
		_setup_multiplayer_game()

func _setup_multiplayer_sudoku() -> void:
	"""Setup multiplayer Sudoku game"""
	print("Setting up multiplayer Sudoku...")
	
	# Set game type in MultiplayerGameManager
	MultiplayerGameManager.current_game_type = "Sudoku"
	
	# Clear status label
	_status_label.text = ""
	
	# Get difficulty level (1=Easy, 3=Medium, 5=Hard)
	var difficulty_level = 3  # Default to Medium
	match _current_difficulty:
		"Easy":
			difficulty_level = 1
		"Medium":
			difficulty_level = 3
		"Hard":
			difficulty_level = 5
	
	# Start new Sudoku game
	_sudoku_game.new_game(difficulty_level, true)
	_sudoku_board.set_game(_sudoku_game)
	
	# Connect signals
	if not _sudoku_game.puzzle_completed.is_connected(_on_multiplayer_sudoku_completed):
		_sudoku_game.puzzle_completed.connect(_on_multiplayer_sudoku_completed)
	if not _sudoku_game.game_over.is_connected(_on_multiplayer_sudoku_game_over):
		_sudoku_game.game_over.connect(_on_multiplayer_sudoku_game_over)
	
	# Connect multiplayer signals
	if not MultiplayerGameManager.player_status_changed.is_connected(_on_player_status_changed):
		MultiplayerGameManager.player_status_changed.connect(_on_player_status_changed)
	if not MultiplayerGameManager.last_player_standing.is_connected(_on_last_player_standing):
		MultiplayerGameManager.last_player_standing.connect(_on_last_player_standing)
	if not MultiplayerGameManager.race_ended.is_connected(_on_multiplayer_race_ended):
		MultiplayerGameManager.race_ended.connect(_on_multiplayer_race_ended)
	if not MultiplayerGameManager.all_players_ready.is_connected(_on_all_players_ready):
		MultiplayerGameManager.all_players_ready.connect(_on_all_players_ready)
	
	# Hide menu buttons
	_hide_menu_buttons()
	
	# Show game buttons (menu button only, no undo for Sudoku)
	_show_new_game_button()
	
	# Setup multiplayer UI
	_setup_multiplayer_ui()
	
	print("Multiplayer Sudoku game setup complete")

func _on_multiplayer_sudoku_completed() -> void:
	"""Handle Sudoku completion in multiplayer"""
	print("Multiplayer Sudoku puzzle completed!")
	_status_label.text = "Puzzle Completed!"
	if SoundManager:
		SoundManager.play_win()
	# TODO: Send completion to server for race tracking

func _on_multiplayer_sudoku_game_over() -> void:
	"""Handle Sudoku game over in multiplayer"""
	print("Multiplayer Sudoku game over - out of lives")
	_status_label.text = "Game Over - Out of Lives"
	if SoundManager:
		SoundManager.play_lose()

func _setup_multiplayer_ui() -> void:
	"""Setup UI elements specific to multiplayer mode"""
	# Player status label (top center)
	_player_status_label = Label.new()
	_player_status_label.name = "PlayerStatusLabel"
	_player_status_label.position = Vector2(400, 10)
	_player_status_label.size = Vector2(200, 30)
	_player_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_status_label.text = "Race in progress..."
	add_child(_player_status_label)
	
	# Leave game button (top right) - FontAwesome times-circle icon
	var leave_button = Button.new()
	leave_button.name = "leave_game_button"
	var top_padding = 0
	if DisplayServer.get_name() == "iOS":
		var safe_area = DisplayServer.get_display_safe_area()
		top_padding = safe_area.position.y
	leave_button.position = Vector2(get_viewport().get_visible_rect().size.x - 110, top_padding)
	leave_button.size = Vector2(100, 100)
	leave_button.tooltip_text = "Leave Game"
	leave_button.pressed.connect(_on_leave_game_pressed)
	
	# Make button background transparent
	var leave_transparent_style = StyleBoxFlat.new()
	leave_transparent_style.bg_color = Color(0, 0, 0, 0)  # Fully transparent
	leave_transparent_style.draw_center = false  # Don't draw background
	leave_button.add_theme_stylebox_override("normal", leave_transparent_style)
	leave_button.add_theme_stylebox_override("hover", leave_transparent_style)
	leave_button.add_theme_stylebox_override("pressed", leave_transparent_style)
	leave_button.add_theme_stylebox_override("disabled", leave_transparent_style)
	
	# Add FontAwesome times-circle icon
	var leave_icon = FontAwesome.new()
	leave_icon.icon_name = "times-circle"
	leave_icon.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))  # Red color
	leave_icon.icon_size = 64
	leave_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leave_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	leave_button.add_child(leave_icon)
	
	add_child(leave_button)

func _on_multiplayer_race_ended(winner_id: int, winner_name: String, time: float) -> void:
	"""Handle race completion - disable gameplay and show ready screen"""
	# Disable all game interactions for both Solitaire and Sudoku
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _sudoku_board:
		_sudoku_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Disable all game buttons
	for child in get_children():
		if child is Button and (child.name == "new_game" or child.name == "undo_button"):
			child.disabled = true
	
	# Show ready notification to all players
	_show_ready_notification(winner_id)

func _show_ready_notification(winner_id: int) -> void:
	"""Show notification with ready button after race ends"""
	# Remove old notification if exists
	if _last_standing_notification:
		_last_standing_notification.queue_free()
	
	# Create notification panel (larger for mobile)
	_last_standing_notification = Panel.new()
	_last_standing_notification.name = "RaceEndedNotification"
	_last_standing_notification.set_anchors_preset(Control.PRESET_CENTER)
	_last_standing_notification.anchor_left = 0.5
	_last_standing_notification.anchor_top = 0.5
	_last_standing_notification.anchor_right = 0.5
	_last_standing_notification.anchor_bottom = 0.5
	_last_standing_notification.offset_left = -300
	_last_standing_notification.offset_top = -200
	_last_standing_notification.offset_right = 300
	_last_standing_notification.offset_bottom = 200
	add_child(_last_standing_notification)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 30)
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
	title.add_theme_font_size_override("font_size", 56)
	vbox.add_child(title)
	
	var message = Label.new()
	if winner_id == -1:
		message.text = "All players are jammed. Ready up for next round!"
	elif winner_id == local_player_id:
		message.text = "Congratulations! You completed the game first!"
	else:
		message.text = "Another player has won the race."
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size", 32)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(message)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)
	
	# Ready button (larger for mobile)
	_ready_button = Button.new()
	_ready_button.text = "Ready for Next Round"
	_ready_button.custom_minimum_size = Vector2(400, 80)
	_ready_button.add_theme_font_size_override("font_size", 36)
	_ready_button.pressed.connect(_on_ready_pressed)
	vbox.add_child(_ready_button)

func _on_player_status_changed(player_id: int, status: String) -> void:
	"""Handle player status changes"""
	print("Player ", player_id, " status changed to: ", status)
	# Update UI to show player statuses
	_update_player_status_display()

func _on_last_player_standing(player_id: int) -> void:
	"""Show notification when player is last one standing"""
	# Create notification panel (larger for mobile)
	_last_standing_notification = Panel.new()
	_last_standing_notification.name = "LastStandingNotification"
	_last_standing_notification.set_anchors_preset(Control.PRESET_CENTER)
	_last_standing_notification.anchor_left = 0.5
	_last_standing_notification.anchor_top = 0.5
	_last_standing_notification.anchor_right = 0.5
	_last_standing_notification.anchor_bottom = 0.5
	_last_standing_notification.offset_left = -300
	_last_standing_notification.offset_top = -200
	_last_standing_notification.offset_right = 300
	_last_standing_notification.offset_bottom = 200
	add_child(_last_standing_notification)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 30)
	_last_standing_notification.add_child(vbox)
	
	var title = Label.new()
	title.text = "Last Player Standing!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	vbox.add_child(title)
	
	var message = Label.new()
	message.text = "All other players are jammed or finished.\nYou can continue playing or start next round."
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size", 32)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(message)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer)
	
	# Ready button (larger for mobile)
	_ready_button = Button.new()
	_ready_button.text = "Ready for Next Round"
	_ready_button.custom_minimum_size = Vector2(400, 80)
	_ready_button.add_theme_font_size_override("font_size", 36)
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
	
	# Hide ready notification
	if _last_standing_notification:
		_last_standing_notification.queue_free()
		_last_standing_notification = null
	
	# Re-enable board interactions for current game type
	if _current_game_type == "Sudoku":
		if _sudoku_board:
			_sudoku_board.mouse_filter = Control.MOUSE_FILTER_STOP
		# Setup new Sudoku game
		_setup_multiplayer_sudoku()
	else:  # Solitaire
		_board.mouse_filter = Control.MOUSE_FILTER_STOP
		
		# Setup new Solitaire game
		var local_game = MultiplayerGameManager.get_local_game()
		if local_game and is_instance_valid(local_game):
			_game = local_game
			_board.set_game(_game)
			_board.render()
			
			# Reconnect card moved signal
			if not _game.card_moved.is_connected(_on_multiplayer_card_moved):
				_game.card_moved.connect(_on_multiplayer_card_moved)
	
	# Re-enable game buttons
	for child in get_children():
		if child is Button and child.name == "new_game":
			child.disabled = false
			child.tooltip_text = "Forfeit (Mark as Jammed)"
	
	# Reset status label
	if _player_status_label:
		_player_status_label.text = "Race in progress..."

func _on_forfeit_pressed() -> void:
	"""Handle forfeit button press in multiplayer"""
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
