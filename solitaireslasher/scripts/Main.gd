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
var _sudoku_mirror_mode_enabled: bool = false  # Track if Sudoku mirror mode is active
var _waiting_for_ready: bool = false

# Spider Solitaire
var _spider_board: SpiderBoard
var _spider_mirror_mode_enabled: bool = false  # Track if Spider mirror mode is active

# Game type and difficulty selection
var _player_name_input: LineEdit
var _difficulty_option: OptionButton
var _current_difficulty: String = "Medium"
var _game_type_option: OptionButton
var _current_game_type: String = "Solitaire"  # "Solitaire" or "Sudoku"

# Main menu
const GameCarouselScript = preload("res://scripts/GameCarousel.gd")
const WastelandStyle = preload("res://scripts/WastelandStyle.gd")
const _MENU_GAMES: Array[String] = ["Solitaire", "Sudoku", "Spider"]
const _MENU_GAME_INFO := {
	"Solitaire": {
		"title": WastelandStyle.DISPLAY_NAMES["Solitaire"],
		"tagline": "Carve through the deck. Klondike, no mercy.",
		"accent": WastelandStyle.ACCENTS["Solitaire"],
		"icon": "res://game icons/solitaire_icon.png",
	},
	"Sudoku": {
		"title": WastelandStyle.DISPLAY_NAMES["Sudoku"],
		"tagline": "Nine by nine. Three lives. No second chances.",
		"accent": WastelandStyle.ACCENTS["Sudoku"],
		"icon": "res://game icons/sudoku_icon.png",
	},
	"Spider": {
		"title": WastelandStyle.DISPLAY_NAMES["Spider"],
		"tagline": "Two decks. Eight runs. Don't get tangled.",
		"accent": WastelandStyle.ACCENTS["Spider"],
		"icon": "res://game icons/spider_icon.png",
	},
}
var _menu_bg_material: ShaderMaterial
var _menu_carousel: Carousel
var _menu_game_title: Label
var _menu_game_tagline: Label
var _menu_dots: Array[Panel] = []
var _menu_play_style: StyleBoxFlat
var _menu_selected_index: int = 0
var _menu_accent: Color = Color(0.9, 0.18, 0.14)
var _menu_accent_tween: Tween
var _game_bg_material: ShaderMaterial  # Atmosphere shader for the Solitaire table
var _hud_stats_label: Label  # "MOVES · TIME" readout during single-player Solitaire


func _ready() -> void:
	# Get current theme from PlayerData
	var theme_found = PlayerData.get_theme()
	print("Current theme: ", theme_found)
	
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
	
	# Add background for both Solitaire and Sudoku
	var game_background = ColorRect.new()
	game_background.name = "GameBackground"
	# Set default background color (will be updated based on game type)
	var current_theme = PlayerData.get_theme()
	game_background.color = Color(0.2, 0.4, 0.7) if current_theme == "light" else Color(0.1, 0.1, 0.1)
	game_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_background.z_index = -1  # Behind everything
	game_background.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block input
	add_child(game_background)
	game_background.visible = false
	
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
	
	# Create Spider Solitaire board
	_spider_board = SpiderBoard.new()
	_spider_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	_spider_board.offset_top = 120  # Match solitaire: clear menu + retry buttons (100px + padding)
	_spider_board.visible = false
	add_child(_spider_board)
	_spider_board.game_won.connect(_on_spider_game_won)

	# Apply mobile safe-area offset on top of the base 120px clearance
	if OS.has_feature("mobile"):
		var safe_area = DisplayServer.get_display_safe_area()
		_spider_board.offset_top = safe_area.position.y + 120

	# Hide game elements on startup
	_board.visible = false
	_sudoku_board.visible = false
	_spider_board.visible = false
	_status_label.visible = false
	
	_setup_main_menu()
	_create_hud_stats_label()
	call_deferred("_show_main_menu")
	
	# Connect to NetworkManager signals for disconnect handling
	if NetworkManager:
		NetworkManager.multiplayer.server_disconnected.connect(_on_server_disconnected)
		NetworkManager.player_disconnected.connect(_on_player_disconnected)

func _create_hud_stats_label() -> void:
	"""Top-center MOVES · TIME readout, shown only while a single-player Solitaire board is up"""
	var top_padding := 10.0
	if OS.has_feature("mobile"):
		top_padding = maxf(10.0, DisplayServer.get_display_safe_area().position.y)
	_hud_stats_label = WastelandStyle.label("", 34, Color(WastelandStyle.BONE, 0.85), 3, 6)
	_hud_stats_label.name = "HudStats"
	_hud_stats_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud_stats_label.offset_top = top_padding
	_hud_stats_label.offset_bottom = top_padding + 100
	_hud_stats_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud_stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_stats_label.visible = false
	add_child(_hud_stats_label)

func _process(_delta: float) -> void:
	if not _hud_stats_label:
		return
	var stats_game: Object = null
	if not (MultiplayerGameManager and MultiplayerGameManager.is_multiplayer):
		if _current_game_type == "Solitaire" and _board.visible and is_instance_valid(_game):
			stats_game = _game
		elif _current_game_type == "Spider" and _spider_board.visible and is_instance_valid(_spider_board._game):
			stats_game = _spider_board._game
	_hud_stats_label.visible = stats_game != null
	if stats_game:
		var seconds := int(stats_game.get_game_time())
		_hud_stats_label.text = WastelandStyle.stats_text(stats_game.get_moves_count(), seconds)

func _setup_main_menu() -> void:
	var viewport_size := get_viewport_rect().size
	var top_padding := 0.0
	var left_padding := 0.0
	var bottom_padding := 0.0
	if OS.has_feature("mobile"):
		var safe_area = DisplayServer.get_display_safe_area()
		top_padding = safe_area.position.y
		left_padding = safe_area.position.x
		bottom_padding = DisplayServer.screen_get_size().y - safe_area.end.y

	# Background: theme color tinted by the wasteland shader, plus drifting embers
	var menu_background = ColorRect.new()
	menu_background.name = "MenuBackground"
	var current_theme = PlayerData.get_theme()
	if current_theme == "light":
		menu_background.color = Color(0.2, 0.4, 0.7)  # Blue background
	else:
		menu_background.color = Color(0.1, 0.1, 0.1)  # Dark gray background
	menu_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_background.z_index = -2  # Behind game background
	menu_background.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block input
	_menu_bg_material = ShaderMaterial.new()
	_menu_bg_material.shader = load("res://shaders/menu_wasteland.gdshader")
	menu_background.material = _menu_bg_material
	menu_background.add_child(_create_menu_embers())
	add_child(menu_background)
	menu_background.resized.connect(_on_menu_background_resized)
	_on_menu_background_resized.call_deferred()

	# Add settings button in top left with iPhone notch padding
	var settings_button = Button.new()
	settings_button.name = "settings_button"
	settings_button.position = Vector2(10 + left_padding, 10 + top_padding)
	settings_button.size = Vector2(100, 100)
	settings_button.tooltip_text = "Settings"

	# Make button background transparent
	var transparent_style = StyleBoxFlat.new()
	transparent_style.bg_color = Color(0, 0, 0, 0)  # Fully transparent
	transparent_style.draw_center = false  # Don't draw background
	settings_button.add_theme_stylebox_override("normal", transparent_style)
	settings_button.add_theme_stylebox_override("hover", transparent_style)
	settings_button.add_theme_stylebox_override("pressed", transparent_style)

	# Ensure settings button catches mouse events
	settings_button.mouse_filter = Control.MOUSE_FILTER_STOP

	# Add FontAwesome gear icon for settings (FontAwesome 6 naming)
	var settings_icon = FontAwesome.new()
	settings_icon.icon_name = "gear"
	settings_icon.add_theme_color_override("font_color", WastelandStyle.BONE)
	settings_icon.icon_size = 64
	settings_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_button.add_child(settings_icon)

	settings_button.pressed.connect(_on_settings_button_pressed)
	# Don't add to scene tree yet - will add after menu container

	# Full-screen menu container for maximum swipe area
	_menu_container = VBoxContainer.new()
	_menu_container.name = "MainMenuContainer"
	_menu_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_container.add_theme_constant_override("separation", 0)
	add_child(_menu_container)

	# Now add settings button on top of everything
	add_child(settings_button)

	var top_spacer = Control.new()
	top_spacer.custom_minimum_size = Vector2(0, top_padding + 130)
	_menu_container.add_child(top_spacer)

	var is_mobile := OS.has_feature("mobile")
	var title := WastelandStyle.title("CHOOSE YOUR FATE", 84 if is_mobile else 68)
	_menu_container.add_child(title)

	var subtitle := WastelandStyle.label("— swipe to pick your poison —", 30, WastelandStyle.BONE_MUTED, 2)
	_menu_container.add_child(subtitle)

	# Flexible spacers above the carousel and below the button center that group on tall screens
	var upper_flex = Control.new()
	upper_flex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_container.add_child(upper_flex)

	# Game carousel; GameCarousel scales/dims/tilts items by distance from center
	var item_side := minf(viewport_size.x * 0.6, viewport_size.y * 0.3)
	var game_carousel: Carousel = GameCarouselScript.new()
	game_carousel.name = "GameCarousel"
	game_carousel.custom_minimum_size = Vector2(0, item_side * 1.3)
	game_carousel.item_size = Vector2(item_side, item_side)
	game_carousel.item_seperation = viewport_size.x * 0.02  # Side games peek in from the edges

	# Enable carousel movement and interaction with smooth looping
	game_carousel.carousel_angle = 0  # Horizontal
	game_carousel.allow_loop = true
	game_carousel.display_loop = true
	game_carousel.snap_behavior = Carousel.SNAP_BEHAVIOR.SNAP
	game_carousel.can_drag = true
	game_carousel.drag_outside = true  # Allow drag outside bounds
	game_carousel.enforce_border = false  # No hard stops for smooth looping
	game_carousel.display_range = -1  # Show all items for smoother looping
	game_carousel.snap_carousel_duration = 0.35
	game_carousel.snap_carousel_transtion_type = Tween.TRANS_CUBIC
	game_carousel.snap_carousel_ease_type = Tween.EASE_OUT
	game_carousel.manual_carousel_duration = 0.35
	game_carousel.manual_carousel_transtion_type = Tween.TRANS_CUBIC
	game_carousel.manual_carousel_ease_type = Tween.EASE_OUT

	# Game icons are swipe-only; the ENTER button opens the selected game
	for game in _MENU_GAMES:
		var icon = TextureRect.new()
		icon.texture = load(_MENU_GAME_INFO[game].icon)
		icon.custom_minimum_size = Vector2(item_side, item_side)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.name = game
		icon.mouse_filter = Control.MOUSE_FILTER_PASS  # Let drags reach the carousel
		game_carousel.add_child(icon)

	# Connect to carousel change signals
	game_carousel.manual_end.connect(_on_game_carousel_selection_changed)
	game_carousel.snap_end.connect(_on_game_carousel_selection_changed)
	game_carousel.resized.connect(_update_menu_glow_position)
	game_carousel.item_rect_changed.connect(_update_menu_glow_position)
	_menu_container.add_child(game_carousel)
	_menu_carousel = game_carousel

	# Selected game name and tagline
	_menu_game_title = WastelandStyle.label("", 64 if is_mobile else 54, Color.WHITE, 4, 8)
	_menu_container.add_child(_menu_game_title)

	_menu_game_tagline = WastelandStyle.label("", 32 if is_mobile else 26, Color(WastelandStyle.BONE, 0.85), 1)
	_menu_game_tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_container.add_child(_menu_game_tagline)

	# Page dots
	var dots_spacer = Control.new()
	dots_spacer.custom_minimum_size = Vector2(0, 28)
	_menu_container.add_child(dots_spacer)

	var dots = HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 14)
	_menu_container.add_child(dots)
	_menu_dots.clear()
	for i in range(_MENU_GAMES.size()):
		var dot_style = StyleBoxFlat.new()
		dot_style.set_corner_radius_all(8)
		var dot = Panel.new()
		dot.custom_minimum_size = Vector2(16, 16)
		dot.add_theme_stylebox_override("panel", dot_style)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dots.add_child(dot)
		_menu_dots.append(dot)

	var play_spacer = Control.new()
	play_spacer.custom_minimum_size = Vector2(0, 36)
	_menu_container.add_child(play_spacer)

	# ENTER button: dark metal with an accent-colored border and glow
	var play_button := WastelandStyle.make_button("ENTER", _menu_accent, true, Vector2(440, 112), 48)
	play_button.name = "MenuPlayButton"
	_menu_play_style = play_button.get_theme_stylebox("normal") as StyleBoxFlat
	play_button.pressed.connect(_on_menu_play_pressed)
	_menu_container.add_child(play_button)

	var lower_flex = Control.new()
	lower_flex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_container.add_child(lower_flex)

	var bottom_spacer = Control.new()
	bottom_spacer.custom_minimum_size = Vector2(0, bottom_padding + 70)
	_menu_container.add_child(bottom_spacer)

	# Initialize selection (Solitaire is default, index 0)
	_set_menu_selection(0, false)

func create_carousel_item(item_name: String) -> Control:
	"""Create a carousel item with icon and text"""
	var item = Control.new()
	item.name = item_name
	item.custom_minimum_size = Vector2(350, 350)
	
	# Create vertical container for icon and text
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = VBoxContainer.ALIGNMENT_CENTER
	item.add_child(vbox)
	
	# Add icon
	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(200, 200)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	# Load appropriate icon
	if item_name == "Solitaire":
		var solitaire_texture = load("res://game icons/solitaire_icon.png")
		if solitaire_texture:
			icon.texture = solitaire_texture
	elif item_name == "Sudoku":
		var sudoku_texture = load("res://game icons/sudoku_icon.png")
		if sudoku_texture:
			icon.texture = sudoku_texture
	elif item_name == "Spider":
		var spider_texture = load("res://game icons/spider_icon.png")
		if spider_texture:
			icon.texture = spider_texture
	
	vbox.add_child(icon)
	
	# Add text label
	var label = Label.new()
	label.text = item_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 36)
	vbox.add_child(label)
	
	return item

func create_difficulty_carousel_item(item_name: String) -> Control:
	"""Create a difficulty carousel item with medium text"""
	var item = Control.new()
	item.name = item_name
	item.custom_minimum_size = Vector2(300, 60)
	
	var label = Label.new()
	label.text = item_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 42)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	item.add_child(label)
	
	return item

func _on_game_carousel_selection_changed(index: int = -1) -> void:
	"""Handle game carousel selection change and update icon scales"""
	# If no index provided, get current index from carousel
	var game_carousel = get_node_or_null("MainMenuContainer/GameCarousel")
	if index == -1:
		if game_carousel and game_carousel.get_child_count() > 0:
			index = game_carousel.get_current_carousel_index()
		else:
			return

	if index < 0 or index >= _MENU_GAMES.size():
		return
	_current_game_type = _MENU_GAMES[index]
	print("Game selected: ", _current_game_type)

	# Item scale/dim/tilt is handled continuously by GameCarousel
	if index != _menu_selected_index:
		if SoundManager:
			SoundManager.play_swipe()
		_set_menu_selection(index)

func _set_menu_selection(index: int, animate: bool = true) -> void:
	"""Update the game name, tagline, page dots and accent color for the selected game"""
	_menu_selected_index = index
	var info: Dictionary = _MENU_GAME_INFO[_MENU_GAMES[index]]
	_menu_game_title.text = info.title
	_menu_game_tagline.text = info.tagline

	for i in range(_menu_dots.size()):
		var dot: Panel = _menu_dots[i]
		var dot_style := dot.get_theme_stylebox("panel") as StyleBoxFlat
		dot_style.bg_color = info.accent if i == index else Color(WastelandStyle.BONE, 0.3)
		var dot_width := 44.0 if i == index else 16.0
		if animate:
			create_tween().tween_property(dot, "custom_minimum_size:x", dot_width, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			dot.custom_minimum_size.x = dot_width

	if _menu_accent_tween and _menu_accent_tween.is_valid():
		_menu_accent_tween.kill()
	if animate:
		_menu_game_title.modulate.a = 0.0
		_menu_game_tagline.modulate.a = 0.0
		_menu_accent_tween = create_tween().set_parallel()
		_menu_accent_tween.tween_method(_apply_menu_accent, _menu_accent, info.accent, 0.35)
		_menu_accent_tween.tween_property(_menu_game_title, "modulate:a", 1.0, 0.25)
		_menu_accent_tween.tween_property(_menu_game_tagline, "modulate:a", 1.0, 0.25).set_delay(0.08)
	else:
		_apply_menu_accent(info.accent)

func _apply_menu_accent(color: Color) -> void:
	_menu_accent = color
	if _menu_bg_material:
		_menu_bg_material.set_shader_parameter("glow_color", color)
	_menu_game_title.add_theme_color_override("font_color", color.lightened(0.15))
	_menu_play_style.border_color = color
	_menu_play_style.shadow_color = Color(color, 0.45)

func _on_menu_play_pressed() -> void:
	_current_game_type = _MENU_GAMES[_menu_selected_index]
	_on_game_selected()

func _on_menu_background_resized() -> void:
	var menu_bg := get_node_or_null("MenuBackground") as Control
	if not menu_bg or menu_bg.size.y <= 0.0:
		return
	var embers := menu_bg.get_node_or_null("Embers") as CPUParticles2D
	if embers:
		embers.position = Vector2(menu_bg.size.x * 0.5, menu_bg.size.y + 20.0)
		embers.emission_rect_extents = Vector2(menu_bg.size.x * 0.5, 20.0)
	_menu_bg_material.set_shader_parameter("aspect", menu_bg.size.x / menu_bg.size.y)
	_update_menu_glow_position()

func _update_menu_glow_position() -> void:
	"""Keep the background glow centered behind the carousel's focused item"""
	var menu_bg := get_node_or_null("MenuBackground") as Control
	if not menu_bg or not _menu_carousel or menu_bg.size.y <= 0.0:
		return
	var bg_rect := menu_bg.get_global_rect()
	var center := _menu_carousel.get_global_rect().get_center()
	_menu_bg_material.set_shader_parameter("glow_center", (center - bg_rect.position) / bg_rect.size)
	_menu_bg_material.set_shader_parameter("glow_radius", _menu_carousel.item_size.y * 0.8 / bg_rect.size.y)

func _create_menu_embers() -> CPUParticles2D:
	"""Embers drifting up from the bottom of the menu, mostly orange with a few toxic-green specks"""
	var embers := CPUParticles2D.new()
	embers.name = "Embers"
	embers.amount = 70
	embers.lifetime = 9.0
	embers.preprocess = 9.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.direction = Vector2(0, -1)
	embers.spread = 25.0
	embers.gravity = Vector2(18, -12)  # Gentle wind drift
	embers.initial_velocity_min = 60.0
	embers.initial_velocity_max = 160.0
	embers.scale_amount_min = 0.25
	embers.scale_amount_max = 0.8

	var falloff := Gradient.new()
	falloff.set_color(0, Color.WHITE)
	falloff.set_color(1, Color(1, 1, 1, 0))
	var dot := GradientTexture2D.new()
	dot.width = 32
	dot.height = 32
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	dot.gradient = falloff
	embers.texture = dot

	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.15, Color(1, 1, 1, 0.9))
	fade.add_point(0.7, Color(1, 1, 1, 0.5))
	embers.color_ramp = fade

	var tints := Gradient.new()
	tints.set_color(0, Color(1.0, 0.45, 0.1))
	tints.set_color(1, Color(0.5, 1.0, 0.3))
	tints.add_point(0.8, Color(1.0, 0.7, 0.25))
	embers.color_initial_ramp = tints

	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	embers.material = additive
	return embers

func _on_game_selected() -> void:
	"""Handle game selection from carousel - show game-specific menu"""
	# Hide main menu
	_menu_container.visible = false
	
	# Hide settings button when in game menu
	var settings_button = get_node_or_null("settings_button")
	if settings_button:
		settings_button.visible = false
	
	# Create game-specific menu
	_show_game_menu(_current_game_type)

func _show_game_menu(game_type: String) -> void:
	"""Show game-specific menu with difficulty and multiplayer options"""
	# Create game menu container
	var game_menu = VBoxContainer.new()
	game_menu.name = "GameMenu"
	game_menu.set_anchors_preset(Control.PRESET_CENTER)
	game_menu.anchor_left = 0.5
	game_menu.anchor_top = 0.5
	game_menu.offset_left = -300
	game_menu.offset_top = -400
	game_menu.offset_right = 300
	game_menu.offset_bottom = 400
	game_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	game_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(game_menu)
	
	# Title
	var title = Label.new()
	title.text = game_type
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Larger font for iPhone
	if OS.has_feature("mobile"):
		title.add_theme_font_size_override("font_size", 72)
	else:
		title.add_theme_font_size_override("font_size", 56)
	game_menu.add_child(title)

	# Game description
	var description = Label.new()
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 28)
	description.modulate = Color(0.8, 0.8, 0.8)  # Slightly dimmed text

	match game_type:
		"Solitaire":
			description.text = "Build sequences from King to Ace in the foundation piles"
		"Spider":
			description.text = "Create complete K→A sequences to move cards to foundation"
		"Sudoku":
			description.text = "Fill the grid so each row, column, and box has numbers 1–9"
		_:
			description.text = ""

	if description.text != "":
		game_menu.add_child(description)

	# Add spacing
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 40)
	game_menu.add_child(spacer1)
	
	_make_difficulty_slider(game_menu)
	
	# Add spacing
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 40)
	game_menu.add_child(spacer2)
	
	# Play Single Player button
	var play_button = Button.new()
	play_button.text = "Play Single Player"
	# Larger button for iPhone
	if OS.has_feature("mobile"):
		play_button.custom_minimum_size = Vector2(500, 120)
		play_button.add_theme_font_size_override("font_size", 48)
	else:
		play_button.custom_minimum_size = Vector2(400, 80)
		play_button.add_theme_font_size_override("font_size", 36)
	play_button.pressed.connect(_on_single_player_start.bind(game_type))
	game_menu.add_child(play_button)
	
	# Add spacing
	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 20)
	game_menu.add_child(spacer3)

	# Multiplayer button
	var multiplayer_button = Button.new()
	multiplayer_button.text = "Multiplayer"
	# Larger button for iPhone
	if OS.has_feature("mobile"):
		multiplayer_button.custom_minimum_size = Vector2(500, 120)
		multiplayer_button.add_theme_font_size_override("font_size", 48)
	else:
		multiplayer_button.custom_minimum_size = Vector2(400, 80)
		multiplayer_button.add_theme_font_size_override("font_size", 36)
	multiplayer_button.pressed.connect(_on_show_multiplayer_menu.bind(game_type))
	game_menu.add_child(multiplayer_button)

	# Add spacing
	var spacer4 = Control.new()
	spacer4.custom_minimum_size = Vector2(0, 40)
	game_menu.add_child(spacer4)
	
	# Back button
	var back_button = Button.new()
	back_button.text = "Back"
	# Larger button for iPhone
	if OS.has_feature("mobile"):
		back_button.custom_minimum_size = Vector2(500, 120)
		back_button.add_theme_font_size_override("font_size", 48)
	else:
		back_button.custom_minimum_size = Vector2(400, 80)
		back_button.add_theme_font_size_override("font_size", 36)
	back_button.pressed.connect(_on_game_menu_back)
	game_menu.add_child(back_button)
	
	
func _make_difficulty_slider(parent_vbox: VBoxContainer) -> void:
	"""Build the difficulty HSlider with emoji face indicator and add it to parent_vbox"""
	var difficulties = ["Easy", "Medium", "Hard"]
	var current_index = difficulties.find(_current_difficulty)
	if current_index == -1:
		current_index = 1  # Default Medium

	# Difficulty text label (centered, above face)
	var face_label = Label.new()
	face_label.name = "DifficultyFaceLabel"
	face_label.text = difficulties[current_index]
	# Larger font for iPhone
	if OS.has_feature("mobile"):
		face_label.add_theme_font_size_override("font_size", 56)
	else:
		face_label.add_theme_font_size_override("font_size", 40)
	face_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent_vbox.add_child(face_label)

	# Large face icon (centered, under the text)
	var face_icon = FontAwesome.new()
	face_icon.name = "DifficultyFaceIcon"
	# Much larger icon for iPhone (200 as requested)
	if OS.has_feature("mobile"):
		face_icon.icon_size = 200
	else:
		face_icon.icon_size = 70
	face_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_set_difficulty_face(face_icon, current_index)
	parent_vbox.add_child(face_icon)

	# Slider row: "Easy" label | HSlider | "Hard" label
	var slider_row = HBoxContainer.new()
	slider_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_row.add_theme_constant_override("separation", 16)

	var easy_label = Label.new()
	easy_label.text = "Easy"
	# Larger font for iPhone
	if OS.has_feature("mobile"):
		easy_label.add_theme_font_size_override("font_size", 42)
	else:
		easy_label.add_theme_font_size_override("font_size", 28)
	easy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slider_row.add_child(easy_label)

	var slider = HSlider.new()
	slider.name = "DifficultySlider"
	slider.min_value = 0
	slider.max_value = 2
	slider.step = 1
	slider.value = current_index
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Larger slider for iPhone
	if OS.has_feature("mobile"):
		slider.custom_minimum_size = Vector2(500, 80)  # Much larger for iPhone
	else:
		slider.custom_minimum_size = Vector2(300, 48)
	slider_row.add_child(slider)

	var hard_label = Label.new()
	hard_label.text = "Hard"
	# Larger font for iPhone
	if OS.has_feature("mobile"):
		hard_label.add_theme_font_size_override("font_size", 42)
	else:
		hard_label.add_theme_font_size_override("font_size", 28)
	hard_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slider_row.add_child(hard_label)

	parent_vbox.add_child(slider_row)

	# Difficulty description label (small text explaining the selected difficulty)
	var difficulty_description = Label.new()
	difficulty_description.name = "DifficultyDescription"
	difficulty_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	difficulty_description.add_theme_font_size_override("font_size", 20)
	difficulty_description.modulate = Color(0.7, 0.7, 0.7)  # Dimmed text for secondary info
	difficulty_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	difficulty_description.custom_minimum_size = Vector2(500, 0)

	# Set initial difficulty description
	var difficulty_descriptions = {
		0: "More cards visible, easier puzzle solving",
		1: "Balanced challenge with strategic play",
		2: "Limited visibility, high difficulty"
	}
	difficulty_description.text = difficulty_descriptions.get(current_index, "")
	parent_vbox.add_child(difficulty_description)

	# Wire up: update face icon + label + _current_difficulty on slide
	slider.value_changed.connect(func(val: float) -> void:
		var idx = int(val)
		_current_difficulty = difficulties[idx]
		face_label.text = difficulties[idx]
		_set_difficulty_face(face_icon, idx)
		difficulty_description.text = difficulty_descriptions.get(idx, "")
		print("Difficulty changed to: ", _current_difficulty)
	)

func _set_difficulty_face(icon: FontAwesome, index: int) -> void:
	"""Update a FontAwesome node to show the face for the given difficulty index"""
	match index:
		0: icon.icon_name = "face-smile"   # Easy — happy
		1: icon.icon_name = "face-meh"     # Medium — neutral
		2: icon.icon_name = "face-angry"   # Hard — angry

func _update_game_background(game_type: String) -> void:
	"""Update background color based on game type and theme"""
	var game_bg = get_node_or_null("GameBackground")
	if not game_bg:
		return
	
	var current_theme = PlayerData.get_theme()
	
	# Card games get the wasteland atmosphere: tinted table with the game's accent glowing
	# in the empty lower area. Card backs match the game (oxblood Solitaire, rust Spider).
	game_bg.material = null
	CardView.back_color = CardView.BACK_RUST if game_type == "Spider" else CardView.BACK_OXBLOOD
	if game_type == "Solitaire" or game_type == "Spider":
		if game_type == "Solitaire":
			game_bg.color = Color(0.0, 0.5, 0.2) if current_theme == "light" else Color(0.14, 0.1, 0.09)  # Green felt / warm charcoal
		else:
			game_bg.color = Color(0.0, 0.28, 0.12) if current_theme == "light" else Color(0.11, 0.11, 0.08)  # Green felt / olive charcoal
		if _game_bg_material == null:
			_game_bg_material = ShaderMaterial.new()
			_game_bg_material.shader = load("res://shaders/menu_wasteland.gdshader")
			_game_bg_material.set_shader_parameter("glow_center", Vector2(0.5, 1.0))
			_game_bg_material.set_shader_parameter("glow_radius", 0.4)
			_game_bg_material.set_shader_parameter("glow_strength", 0.3)
		_game_bg_material.set_shader_parameter("glow_color", WastelandStyle.accent_for(game_type))
		var bg_size: Vector2 = game_bg.size
		_game_bg_material.set_shader_parameter("aspect", bg_size.x / maxf(bg_size.y, 1.0))
		game_bg.material = _game_bg_material
	else:  # Sudoku
		# Sky blue for light mode, original dark for dark mode
		if current_theme == "light":
			game_bg.color = Color(0.33, 0.41, 1.0)  # Sky blue
		else:
			game_bg.color = Color(0.1, 0.1, 0.1)  # Original dark gray
	
	print("Updated ", game_type, " background to: ", game_bg.color)

func _on_single_player_start(game_type: String) -> void:
	"""Handle single player start for specific game"""
	# Remove game menu
	var game_menu = get_node_or_null("GameMenu")
	if game_menu:
		game_menu.queue_free()

	# Set the game type
	_current_game_type = game_type

	# Check for saved games and show prompt if any exist
	if PlayerData.has_saved_game(game_type):
		_show_continue_game_dialog_for_type(game_type)
		return  # Return early - setup will be called after user makes a choice

	# Update background based on game type
	_update_game_background(game_type)

	# Hide settings button when game starts
	var settings_button = get_node_or_null("settings_button")
	if settings_button:
		settings_button.visible = false

	# Hide menu button when game starts
	if _menu_button:
		_menu_button.visible = false

	# Start game based on selection
	if game_type == "Solitaire":
		PlayerData.clear_saved_game("Solitaire")
		MultiplayerGameManager.start_local_game(_current_difficulty)
		_setup_single_player_game()
	elif game_type == "Spider":
		_setup_spider_game()
	else:  # Sudoku
		PlayerData.clear_saved_game("Sudoku")
		_setup_single_player_sudoku()

func _on_game_menu_back() -> void:
	"""Handle game menu back button"""
	# Remove game menu
	var game_menu = get_node_or_null("GameMenu")
	if game_menu:
		game_menu.queue_free()
	
	# Show settings button when back to main menu
	var settings_button = get_node_or_null("settings_button")
	if settings_button:
		settings_button.visible = true
	
	# Show main menu
	_menu_container.visible = true

func _on_show_single_player_menu() -> void:
	"""Show single player submenu with carousels for game type and difficulty"""
	# Check for saved games and show continue prompt if any exist
	_check_and_show_saved_games()

	# Hide main menu
	_menu_container.visible = false

	# Hide settings button when in single player menu
	var settings_button = get_node_or_null("settings_button")
	if settings_button:
		settings_button.visible = false

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
	# Larger font for iPhone
	if OS.has_feature("mobile"):
		title.add_theme_font_size_override("font_size", 72)
	else:
		title.add_theme_font_size_override("font_size", 56)
	sp_menu.add_child(title)
	
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 40)
	sp_menu.add_child(spacer1)
	
	# Game Type Carousel (Horizontal) with Icons using FreeControl
	var game_type_label = Label.new()
	game_type_label.text = "Game Type"
	game_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Larger font for iPhone
	if OS.has_feature("mobile"):
		game_type_label.add_theme_font_size_override("font_size", 48)
	else:
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
	
	_make_difficulty_slider(sp_menu)
	
	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 40)
	sp_menu.add_child(spacer3)
	
	# Start button
	var start_button = Button.new()
	start_button.text = "Start Game"
	# Larger button for iPhone
	if OS.has_feature("mobile"):
		start_button.custom_minimum_size = Vector2(500, 120)
		start_button.add_theme_font_size_override("font_size", 48)
	else:
		start_button.custom_minimum_size = Vector2(400, 80)
		start_button.add_theme_font_size_override("font_size", 36)
	start_button.pressed.connect(_on_single_player_start_legacy)
	sp_menu.add_child(start_button)
	
	var spacer4 = Control.new()
	spacer4.custom_minimum_size = Vector2(0, 20)
	sp_menu.add_child(spacer4)
	
	# Back button
	var back_button = Button.new()
	back_button.text = "Back"
	# Larger button for iPhone
	if OS.has_feature("mobile"):
		back_button.custom_minimum_size = Vector2(500, 120)
		back_button.add_theme_font_size_override("font_size", 48)
	else:
		back_button.custom_minimum_size = Vector2(400, 80)
		back_button.add_theme_font_size_override("font_size", 36)
	back_button.pressed.connect(_on_single_player_back)
	sp_menu.add_child(back_button)

func _on_single_player_back() -> void:
	"""Handle single player back button"""
	# Remove single player menu
	var sp_menu = get_node_or_null("SinglePlayerMenu")
	if sp_menu:
		sp_menu.queue_free()
	
	# Show main menu
	_show_main_menu()

func _on_show_multiplayer_menu(game_type: String = "") -> void:
	"""Show multiplayer submenu with Host/Join buttons for specific game"""
	# Hide game menu if coming from there, otherwise hide main menu
	var game_menu = get_node_or_null("GameMenu")
	if game_menu:
		game_menu.visible = false
	else:
		_menu_container.visible = false
	
	# Hide settings button when in multiplayer menu
	var settings_button = get_node_or_null("settings_button")
	if settings_button:
		settings_button.visible = false
	
	# Create multiplayer menu container
	var is_mobile := OS.has_feature("mobile")
	var accent := WastelandStyle.accent_for(game_type)
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
	# Content (e.g. the title on iPhone) can be wider than 500, so grow both ways to stay centered
	mp_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mp_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	mp_menu.add_theme_constant_override("separation", 0)
	add_child(mp_menu)

	# Title: "MULTIPLAYER" heading with the game's name in its accent color below
	mp_menu.add_child(WastelandStyle.title("MULTIPLAYER", 84 if is_mobile else 68))
	if game_type != "":
		mp_menu.add_child(WastelandStyle.label(WastelandStyle.display_name(game_type), 52 if is_mobile else 44, accent.lightened(0.15), 4, 8))
	mp_menu.add_child(WastelandStyle.label("— race a rival on the same Wi-Fi —", 30, WastelandStyle.BONE_MUTED, 2))

	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 80)
	mp_menu.add_child(spacer1)

	# Host button + hint
	var host_button := WastelandStyle.make_button("HOST GAME", accent, true, Vector2(500, 120) if is_mobile else Vector2(440, 104), 48 if is_mobile else 40)
	host_button.pressed.connect(_on_host_game.bind(game_type))
	mp_menu.add_child(host_button)
	var host_hint := WastelandStyle.label("Open a lobby and share a QR code", 28, Color(WastelandStyle.BONE, 0.7), 1)
	host_hint.custom_minimum_size = Vector2(0, 60)
	host_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mp_menu.add_child(host_hint)

	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 30)
	mp_menu.add_child(spacer2)

	# Join button + hint
	var join_button := WastelandStyle.make_button("JOIN GAME", accent, true, Vector2(500, 120) if is_mobile else Vector2(440, 104), 48 if is_mobile else 40)
	join_button.pressed.connect(_on_join_game.bind(game_type))
	mp_menu.add_child(join_button)
	var join_hint := WastelandStyle.label("Scan the host's QR code or enter their IP", 28, Color(WastelandStyle.BONE, 0.7), 1)
	join_hint.custom_minimum_size = Vector2(0, 60)
	join_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mp_menu.add_child(join_hint)

	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 70)
	mp_menu.add_child(spacer3)

	# Back button
	var back_button := WastelandStyle.make_button("BACK", accent, false, Vector2(360, 100) if is_mobile else Vector2(320, 88), 40 if is_mobile else 34)
	back_button.pressed.connect(_on_multiplayer_back)
	mp_menu.add_child(back_button)

	# Fade in
	mp_menu.modulate.a = 0.0
	create_tween().tween_property(mp_menu, "modulate:a", 1.0, 0.3)

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
	pass  # Legacy stub — difficulty now controlled by HSlider via _make_difficulty_slider

func _on_single_player_start_legacy():
	"""Handle single player start button (legacy function)"""
	# Remove single player menu
	var sp_menu = get_node_or_null("SinglePlayerMenu")
	if sp_menu:
		sp_menu.queue_free()
	
	# Hide main menu
	_hide_main_menu()
	
	# Update background based on current game type
	_update_game_background(_current_game_type)
	
	# Hide settings button when game starts
	var settings_button = get_node_or_null("settings_button")
	if settings_button:
		settings_button.visible = false
	
	# Start game based on selection
	if _current_game_type == "Solitaire":
		MultiplayerGameManager.start_local_game(_current_difficulty)
		_setup_single_player_game()
	else:  # Sudoku
		_setup_single_player_sudoku()

func get_current_game_type() -> String:
	"""Get the currently selected game type"""
	return _current_game_type

func _on_multiplayer_back():
	# Remove multiplayer menu
	var mp_menu = get_node_or_null("MultiplayerMenu")
	if mp_menu:
		mp_menu.queue_free()
	
	# Show game menu if it exists, otherwise show main menu
	var game_menu = get_node_or_null("GameMenu")
	if game_menu:
		game_menu.visible = true
	else:
		# Show main menu
		_menu_container.visible = true
	
	# Show settings button when back from multiplayer
	var settings_button = get_node_or_null("settings_button")
	if settings_button:
		settings_button.visible = true

func _on_host_game(game_type: String) -> void:
	# Hide multiplayer menu
	var mp_menu = get_node_or_null("MultiplayerMenu")
	if mp_menu:
		mp_menu.queue_free()

	# Set the current game type for multiplayer
	_current_game_type = game_type

	var player_name = PlayerData.get_player_name()
	if player_name == "":
		player_name = "Player" + str(randi() % 1000)  # Fallback to random if no name set

	# Let MultiplayerLobby.setup_as_host() call NetworkManager.host_game() - don't duplicate it here
	print("Hosting " + game_type + " multiplayer game")
	_show_multiplayer_lobby(true, player_name)

func _on_join_game(game_type: String) -> void:
	# Hide multiplayer menu
	var mp_menu = get_node_or_null("MultiplayerMenu")
	if mp_menu:
		mp_menu.queue_free()
	
	# Set the current game type for multiplayer
	_current_game_type = game_type
	
	# Show lobby with manual IP entry
	var player_name = PlayerData.get_player_name()
	if player_name == "":
		player_name = "Player" + str(randi() % 1000)  # Fallback to random if no name set
	print("Joining " + game_type + " multiplayer game")
	_show_multiplayer_lobby(false, player_name)

func _show_main_menu() -> void:
	# Save current game state before resetting (if game is in progress)
	_save_current_game_if_in_progress()

	# Reset game state when returning to main menu
	_current_game_type = ""
	_current_difficulty = "Medium"
	print("Reset game state: game_type='', difficulty='Medium'")
	
	if _menu_container:
		_menu_container.visible = true
		_menu_container.modulate.a = 0.0
		create_tween().tween_property(_menu_container, "modulate:a", 1.0, 0.35)
	if _menu_carousel:
		_set_menu_selection(_menu_carousel.get_current_carousel_index(), false)
		_update_menu_glow_position()
	
	# Show settings button only on main menu (if it exists)
	var settings_button = get_node_or_null("settings_button")
	if settings_button:
		settings_button.visible = true
	
	# Update menu background to current theme when returning to main menu
	var menu_bg = get_node_or_null("MenuBackground")
	if menu_bg:
		menu_bg.visible = true
		var current_theme = PlayerData.get_theme()
		menu_bg.color = Color(0.2, 0.4, 0.7) if current_theme == "light" else Color(0.1, 0.1, 0.1)
	
	# Hide blue game background when in menu
	var game_bg = get_node_or_null("GameBackground")
	if game_bg:
		game_bg.visible = false
	
	# Hide game boards
	if _board:
		_board.visible = false
	if _spider_board:
		_spider_board.visible = false
	if _sudoku_board:
		_sudoku_board.visible = false

	# Clear and hide status label
	if _status_label:
		_status_label.text = ""
		_status_label.visible = false

	# Hide game control buttons
	for child in get_children():
		if child is Button and (child.name == "new_game" or child.name == "undo_button" or child.name == "menu_button"):
			child.visible = false

	# Start background music when on any menu
	# But only if not in multiplayer mode and if setting is enabled
	if SoundManager:
		if not (MultiplayerGameManager and MultiplayerGameManager.is_multiplayer):
			if PlayerData.is_background_music_enabled():
				SoundManager.play_background_music()
				print("Started background music (single player mode)")
			else:
				print("Background music disabled in settings")
		else:
			print("Keeping music stopped (multiplayer mode)")

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
		if _spider_board:
			_spider_board.visible = false
	elif _current_game_type == "Spider":
		_board.visible = false
		_sudoku_board.visible = false
		if _spider_board:
			_spider_board.visible = true
	else:  # Sudoku
		_board.visible = false
		_sudoku_board.visible = true
		if _spider_board:
			_spider_board.visible = false
	
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
	elif _current_game_type == "Spider":
		_setup_spider_game()
	else:  # Sudoku
		_setup_single_player_sudoku()

func _start_multiplayer_game() -> void:
	_hide_main_menu()
	
	# Hide settings button when multiplayer game starts
	var settings_button = get_node_or_null("settings_button")
	if settings_button:
		settings_button.visible = false

	# Note: start_multiplayer_race() is already called by the lobby before this signal is emitted.
	# Just set up the game UI here.
	_setup_multiplayer_game()

func _setup_single_player_game() -> void:
	print("Setting up single player game...")

	# Stop background music when entering a game
	if SoundManager:
		SoundManager.play_game_start()

	# Hide main menu container
	_hide_main_menu()
	
	# Hide settings button when game starts
	var settings_button = get_node_or_null("settings_button")
	if settings_button:
		settings_button.visible = false
	
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

	# Stop background music when entering a game
	if SoundManager:
		SoundManager.play_game_start()

	# Hide main menu container
	_hide_main_menu()
	
	# Hide settings button when game starts
	var settings_button = get_node_or_null("settings_button")
	if settings_button:
		settings_button.visible = false
	
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
	if not _sudoku_board.play_again_requested.is_connected(_new_game):
		_sudoku_board.play_again_requested.connect(_new_game)
	if not _sudoku_board.main_menu_requested.is_connected(_show_main_menu):
		_sudoku_board.main_menu_requested.connect(_show_main_menu)
	
	# Hide menu buttons
	_hide_menu_buttons()
	
	# Show game buttons (menu button only, no undo for Sudoku)
	_show_new_game_button()
	
	print("Sudoku game setup complete")

func _on_sudoku_completed() -> void:
	print("Sudoku puzzle completed!")
	_status_label.text = "Puzzle Completed!"
	PlayerData.clear_saved_game("Sudoku")
	if SoundManager:
		SoundManager.play_win()

func _on_sudoku_game_over() -> void:
	print("Sudoku game over - out of lives")
	_status_label.text = "Game Over - Out of Lives"
	PlayerData.clear_saved_game("Sudoku")  # Clear save on game over/loss
	if SoundManager:
		SoundManager.play_lose()

func _setup_spider_game() -> void:
	print("Setting up Spider Solitaire...")

	if SoundManager:
		SoundManager.play_game_start()

	_hide_main_menu()

	var settings_button = get_node_or_null("settings_button")
	if settings_button:
		settings_button.visible = false

	_status_label.text = ""

	_spider_board.new_game(_current_difficulty)

	_hide_menu_buttons()
	_show_new_game_button()

	print("Spider Solitaire setup complete")

func _on_spider_game_won() -> void:
	print("Spider Solitaire won!")
	_status_label.text = "You Win!"
	_status_label.visible = true
	PlayerData.clear_saved_game("Spider")
	if SoundManager:
		SoundManager.play_win()

func _hide_menu_buttons():
	for child in get_children():
		if child is Button and (child.name.begins_with("menu_") or child.name == "leave_game_button"):
			child.visible = false
		elif child is Label and child.name == "PlayerStatusLabel":
			child.visible = false

func _circle_style(bg: Color, size: float) -> StyleBoxFlat:
	"""Round HUD button: dark metal with a faint bone rim; darker bg alphas read as pressed/disabled"""
	var s = StyleBoxFlat.new()
	s.bg_color = WastelandStyle.METAL_DARK if bg.a > 0.5 else Color(WastelandStyle.METAL, 0.85 if bg.a > 0.3 else 0.4)
	s.set_border_width_all(3)
	s.border_color = Color(WastelandStyle.BONE, 0.35 if bg.a > 0.3 else 0.15)
	s.set_corner_radius_all(int(size / 2.0))
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 6
	return s

func _show_new_game_button():
	# Remove existing game control buttons if any (immediate removal to prevent duplicates)
	print("DEBUG: _show_new_game_button() called")
	var buttons_to_remove = []
	var labels_to_remove = []
	for child in get_children():
		if child is Button and (child.name == "new_game" or child.name == "undo_button" or child.name == "menu_button" or child.name == "leave_game_button"):
			buttons_to_remove.append(child)
		elif child is Label and child.name == "PlayerStatusLabel":
			labels_to_remove.append(child)
	
	for button in buttons_to_remove:
		remove_child(button)
		button.queue_free()
	
	for label in labels_to_remove:
		remove_child(label)
		label.queue_free()
	
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
	
	new_game_button.position = Vector2(900, top_padding)
	new_game_button.size = Vector2(100, 100)
	new_game_button.add_theme_stylebox_override("normal",   _circle_style(Color(0, 0, 0, 0.45), 100))
	new_game_button.add_theme_stylebox_override("hover",    _circle_style(Color(0, 0, 0, 0.45), 100))
	new_game_button.add_theme_stylebox_override("pressed",  _circle_style(Color(0, 0, 0, 0.65), 100))
	new_game_button.add_theme_stylebox_override("disabled", _circle_style(Color(0, 0, 0, 0.25), 100))
	
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
		forfeit_icon.icon_size = 56
		forfeit_icon.add_theme_color_override("font_color", WastelandStyle.BONE)
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
		retry_icon.icon_size = 52
		retry_icon.add_theme_color_override("font_color", WastelandStyle.BONE)
		retry_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		retry_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		new_game_button.add_child(retry_icon)
	
	add_child(new_game_button)
	
	# Undo button (bottom centre) — circle bg + icon + "Undo" label
	var undo_button = Button.new()
	undo_button.name = "undo_button"
	undo_button.anchor_left   = 0.5
	undo_button.anchor_right  = 0.5
	undo_button.anchor_top    = 1.0
	undo_button.anchor_bottom = 1.0
	undo_button.offset_left   = -50
	undo_button.offset_right  = 50
	undo_button.offset_top    = -160  # 160px above bottom → 50px breathing room
	undo_button.offset_bottom = -50
	undo_button.custom_minimum_size = Vector2(100, 110)
	undo_button.tooltip_text = "Undo Last Move"
	undo_button.pressed.connect(_on_undo_pressed)
	undo_button.visible = (_current_game_type == "Solitaire")
	undo_button.add_theme_stylebox_override("normal",   _circle_style(Color(0, 0, 0, 0.45), 100))
	undo_button.add_theme_stylebox_override("hover",    _circle_style(Color(0, 0, 0, 0.45), 100))
	undo_button.add_theme_stylebox_override("pressed",  _circle_style(Color(0, 0, 0, 0.65), 100))
	undo_button.add_theme_stylebox_override("disabled", _circle_style(Color(0, 0, 0, 0.25), 100))

	var undo_vbox = VBoxContainer.new()
	undo_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	undo_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	undo_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	undo_button.add_child(undo_vbox)

	var undo_icon = FontAwesome.new()
	undo_icon.icon_name = "rotate-left"
	undo_icon.icon_type = "solid"
	undo_icon.icon_size = 56
	undo_icon.add_theme_color_override("font_color", WastelandStyle.BONE)
	undo_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	undo_vbox.add_child(undo_icon)

	var undo_label = WastelandStyle.label("UNDO", 18, Color(WastelandStyle.BONE, 0.8), 2)
	undo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	undo_vbox.add_child(undo_label)

	# Pivot at center for scale animation
	undo_button.pivot_offset = Vector2(50, 55)

	# Click animation: squish on press, spring back on release
	var _undo_tween: Tween = null
	undo_button.button_down.connect(func() -> void:
		if undo_button.disabled:
			return
		if _undo_tween and _undo_tween.is_valid():
			_undo_tween.kill()
		_undo_tween = undo_button.create_tween()
		_undo_tween.set_ease(Tween.EASE_OUT)
		_undo_tween.set_trans(Tween.TRANS_CUBIC)
		_undo_tween.tween_property(undo_button, "scale", Vector2(0.88, 0.88), 0.08)
	)
	undo_button.button_up.connect(func() -> void:
		if _undo_tween and _undo_tween.is_valid():
			_undo_tween.kill()
		_undo_tween = undo_button.create_tween()
		_undo_tween.set_ease(Tween.EASE_OUT)
		_undo_tween.set_trans(Tween.TRANS_BACK)
		_undo_tween.tween_property(undo_button, "scale", Vector2(1.0, 1.0), 0.22)
	)

	add_child(undo_button)

	# Store reference to undo button for state updates
	_undo_button = undo_button
	if _current_game_type == "Solitaire":
		_update_undo_button_state()
	
	# Menu button (top left) - FontAwesome icon
	var menu_button = Button.new()
	menu_button.name = "menu_button"
	
	# Adjust position for Sudoku to avoid number selector overlap
	var menu_x = 10
	var menu_y = top_padding
	if _current_game_type == "Sudoku":
		# In Sudoku mode, position menu button higher to avoid number selector
		menu_y = top_padding - 50  # Move up higher
	
	menu_button.position = Vector2(menu_x, menu_y)
	menu_button.size = Vector2(100, 100)  # 2x larger (was 50x50)
	menu_button.tooltip_text = "Main Menu"
	menu_button.pressed.connect(_on_back_to_menu_pressed)
	
	menu_button.add_theme_stylebox_override("normal",   _circle_style(Color(0, 0, 0, 0.45), 100))
	menu_button.add_theme_stylebox_override("hover",    _circle_style(Color(0, 0, 0, 0.45), 100))
	menu_button.add_theme_stylebox_override("pressed",  _circle_style(Color(0, 0, 0, 0.65), 100))
	menu_button.add_theme_stylebox_override("disabled", _circle_style(Color(0, 0, 0, 0.25), 100))

	var menu_icon = FontAwesome.new()
	menu_icon.icon_name = "chevron-left"
	menu_icon.icon_type = "solid"
	menu_icon.icon_size = 48
	menu_icon.add_theme_color_override("font_color", WastelandStyle.BONE)
	menu_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_button.add_child(menu_icon)
	
	add_child(menu_button)
	_menu_button = menu_button

func _setup_multiplayer_game() -> void:
	# Stop background music when entering a game
	if SoundManager:
		SoundManager.play_game_start()
	# Setup based on current game type
	if _current_game_type == "Sudoku":
		_setup_multiplayer_sudoku()
	elif _current_game_type == "Spider":
		_setup_multiplayer_spider()
	else:  # Solitaire
		# Ensure MultiplayerGameManager has the correct game type for synchronization
		MultiplayerGameManager.current_game_type = "Solitaire"
		# Always set up buttons and signals — game may not be ready yet (mirror-mode client
		# is waiting for mirror data), but the UI and signal wiring must happen now.
		_show_new_game_button()
		_setup_multiplayer_ui()
		if not MultiplayerGameManager.player_status_changed.is_connected(_on_player_status_changed):
			MultiplayerGameManager.player_status_changed.connect(_on_player_status_changed)
		if not MultiplayerGameManager.last_player_standing.is_connected(_on_last_player_standing):
			MultiplayerGameManager.last_player_standing.connect(_on_last_player_standing)
		if not MultiplayerGameManager.race_ended.is_connected(_on_multiplayer_race_ended):
			MultiplayerGameManager.race_ended.connect(_on_multiplayer_race_ended)
		if not MultiplayerGameManager.all_players_ready.is_connected(_on_all_players_ready):
			MultiplayerGameManager.all_players_ready.connect(_on_all_players_ready)
		# race_started fires when the game is fully ready (both initial round and new rounds)
		if not MultiplayerGameManager.race_started.is_connected(_on_multiplayer_race_board_ready):
			MultiplayerGameManager.race_started.connect(_on_multiplayer_race_board_ready)

		# If the game is already ready (signal may have fired before connection), call handler immediately
		if MultiplayerGameManager.local_game and is_instance_valid(MultiplayerGameManager.local_game):
			print("Game already ready, calling board setup immediately")
			_on_multiplayer_race_board_ready()

		print("Multiplayer Solitaire setup initiated - is_multiplayer: ", MultiplayerGameManager.is_multiplayer)

func _on_multiplayer_race_board_ready() -> void:
	"""Called each time a multiplayer Solitaire game is ready (initial round + every new round).
	Wires the board to the current local_game and resets round UI."""
	var local_game = MultiplayerGameManager.get_local_game()
	if not (local_game and is_instance_valid(local_game)):
		return
	_game = local_game
	_board.set_game(_game)
	_board.set_multiplayer_manager(MultiplayerGameManager)
	_board.render()  # Render the board to display cards
	if not _game.card_moved.is_connected(_on_multiplayer_card_moved):
		_game.card_moved.connect(_on_multiplayer_card_moved)
	_board.mouse_filter = Control.MOUSE_FILTER_STOP
	# Re-enable forfeit button and reset status label for the new round
	for child in get_children():
		if child is Button and child.name == "new_game":
			child.disabled = false
			child.tooltip_text = "Forfeit (Mark as Jammed)"
	if _player_status_label:
		_player_status_label.text = "Race in progress..."
	print("Multiplayer Solitaire board wired - new round ready")

func _on_multiplayer_sudoku_race_ready() -> void:
	"""Called each time a multiplayer Sudoku game is ready (initial round + every new round).
	Sets up the board with the current Sudoku game and resets round UI."""
	# For Sudoku, after race_started is emitted, call _setup_multiplayer_sudoku() to wire the new puzzle
	# This handles the mirror data flow: host generates puzzle, sends it, client receives it, game is set up
	_setup_multiplayer_sudoku()
	if _player_status_label:
		_player_status_label.text = "Race in progress..."
	print("Multiplayer Sudoku board wired - new round ready")

func _on_new_game_pressed() -> void:
	# Play retry sound
	if SoundManager:
		SoundManager.play_retry()
	_new_game()

func _new_game() -> void:
	if _current_game_type == "Sudoku":
		# Restart Sudoku game
		_setup_single_player_sudoku()
	elif _current_game_type == "Spider":
		_spider_board.new_game(_current_difficulty)
	elif MultiplayerGameManager and is_instance_valid(MultiplayerGameManager):
		if MultiplayerGameManager.is_multiplayer:
			if MultiplayerGameManager.is_host_player():
				MultiplayerGameManager.start_multiplayer_race()
				_setup_multiplayer_game()
		else:
			MultiplayerGameManager.start_local_game(_current_difficulty)
			_setup_single_player_game()

func _on_undo_pressed() -> void:
	if _game and is_instance_valid(_game) and _game.can_undo():
		await _board.animate_undo()
		_update_undo_button_state()

func _update_undo_button_state() -> void:
	if _undo_button and is_instance_valid(_undo_button):
		var can = _game and is_instance_valid(_game) and _game.can_undo()
		_undo_button.disabled = not can
		_undo_button.modulate.a = 1.0 if can else 0.38
		# Reset scale in case it was mid-animation when disabled
		if not can:
			_undo_button.scale = Vector2(1.0, 1.0)

func _on_card_moved(_from_pile: String, _to_pile: String, _card_count: int) -> void:
	# Update undo button state after any card move
	_update_undo_button_state()

func _cleanup_game_state() -> void:
	"""Clean up all game state before starting a new game or returning to menu"""
	# Clear the boards
	_board.set_game(null)
	_board.render()
	
	# Hide all boards
	_board.visible = false
	_sudoku_board.visible = false
	if _spider_board:
		_spider_board.visible = false
	
	# Hide and clear status label
	_status_label.visible = false
	_status_label.text = ""
	
	# Hide and remove game control buttons (including leave game button)
	for child in get_children():
		if child is Button and (child.name == "new_game" or child.name == "undo_button" or child.name == "menu_button" or child.name == "leave_game_button"):
			child.visible = false
			child.queue_free()
		elif child is Label and child.name == "PlayerStatusLabel":
			child.visible = false
			child.queue_free()
	
	# Hide multiplayer lobby if visible
	if _multiplayer_lobby and is_instance_valid(_multiplayer_lobby):
		_multiplayer_lobby.visible = false
	
	# Hide any ready notifications
	if _last_standing_notification and is_instance_valid(_last_standing_notification):
		_last_standing_notification.queue_free()
	
	# Clean up any game menus that might still be visible
	var game_menu = get_node_or_null("GameMenu")
	if game_menu:
		game_menu.queue_free()
	
	var sp_menu = get_node_or_null("SinglePlayerMenu")
	if sp_menu:
		sp_menu.queue_free()
	
	var mp_menu = get_node_or_null("MultiplayerMenu")
	if mp_menu:
		mp_menu.queue_free()

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

func _on_leave_game_button_pressed() -> void:
	"""Show confirmation dialog before leaving multiplayer game"""
	_show_leave_confirmation_dialog()

func _show_leave_confirmation_dialog() -> void:
	"""Create and show a confirmation dialog for leaving the game (matching ready screen style)"""
	# Create notification panel (matching ready screen style)
	var dialog = Panel.new()
	dialog.name = "LeaveConfirmationDialog"
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.anchor_left = 0.5
	dialog.anchor_top = 0.5
	dialog.anchor_right = 0.5
	dialog.anchor_bottom = 0.5
	dialog.offset_left = -250
	dialog.offset_top = -180
	dialog.offset_right = 250
	dialog.offset_bottom = 180
	dialog.z_index = 1000
	add_child(dialog)

	# Style panel with professional appearance
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.98)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.6, 0.6, 0.6)
	dialog.add_theme_stylebox_override("panel", style)

	# Create layout matching ready screen
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 25)
	dialog.add_child(vbox)

	# Add padding
	var top_spacer = Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(top_spacer)

	# Title
	var title = Label.new()
	title.text = "Leave Game?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)

	# Message
	var message = Label.new()
	message.text = "Are you sure you want to leave?\nYour progress will be lost."
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size", 28)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(message)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(spacer)

	# Button container for side-by-side buttons
	var button_hbox = HBoxContainer.new()
	button_hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(button_hbox)

	# Center spacer
	var left_spacer = Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_hbox.add_child(left_spacer)

	# Stay button
	var stay_button = Button.new()
	stay_button.text = "Stay"
	stay_button.custom_minimum_size = Vector2(140, 70)
	stay_button.add_theme_font_size_override("font_size", 32)
	var stay_style = StyleBoxFlat.new()
	stay_style.bg_color = Color(0.3, 0.5, 0.3)
	stay_style.corner_radius_top_left = 12
	stay_style.corner_radius_top_right = 12
	stay_style.corner_radius_bottom_left = 12
	stay_style.corner_radius_bottom_right = 12
	stay_button.add_theme_stylebox_override("normal", stay_style)
	stay_button.add_theme_color_override("font_color", Color.WHITE)
	stay_button.pressed.connect(func(): dialog.queue_free())
	button_hbox.add_child(stay_button)

	# Leave button
	var leave_button = Button.new()
	leave_button.text = "Leave"
	leave_button.custom_minimum_size = Vector2(140, 70)
	leave_button.add_theme_font_size_override("font_size", 32)
	var leave_style = StyleBoxFlat.new()
	leave_style.bg_color = Color(0.7, 0.3, 0.3)
	leave_style.corner_radius_top_left = 12
	leave_style.corner_radius_top_right = 12
	leave_style.corner_radius_bottom_left = 12
	leave_style.corner_radius_bottom_right = 12
	leave_button.add_theme_stylebox_override("normal", leave_style)
	leave_button.add_theme_color_override("font_color", Color.WHITE)
	leave_button.pressed.connect(func():
		dialog.queue_free()
		_on_leave_game_pressed()
	)
	button_hbox.add_child(leave_button)

	# Right spacer
	var right_spacer = Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_hbox.add_child(right_spacer)

	# Bottom spacer
	var bottom_spacer = Control.new()
	bottom_spacer.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(bottom_spacer)

func _on_back_to_menu_pressed() -> void:
	# Clean up game state
	_cleanup_game_state()

	# Properly leave multiplayer session (closes sockets, clears state)
	if NetworkManager and is_instance_valid(NetworkManager):
		NetworkManager.leave_game()

	# Show main menu
	_show_main_menu()
	
	# Clear the board
	_board.set_game(null)
	_board.render()

func _show_multiplayer_lobby(as_host: bool, player_name: String) -> void:
	# Stop background music when entering multiplayer lobby
	if SoundManager:
		SoundManager.play_game_start()
	# Hide main menu
	if _menu_container:
		_menu_container.visible = false
	
	# Keep the menu backdrop behind the lobby, with the glow moved up behind the lobby title
	var menu_bg = get_node_or_null("MenuBackground")
	if menu_bg:
		menu_bg.visible = true
	if _menu_bg_material:
		_menu_bg_material.set_shader_parameter("glow_center", Vector2(0.5, 0.12))
		_menu_bg_material.set_shader_parameter("glow_color", WastelandStyle.accent_for(_current_game_type))
	
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
		print("Cleaning up existing lobby before creating new one")
		_multiplayer_lobby.queue_free()
		_multiplayer_lobby = null
		# Wait for cleanup to complete
		await get_tree().process_frame
	
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
	
	# Run full cleanup to ensure everything is properly hidden
	_cleanup_game_state()
	
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
	_update_game_background(game_type)
	
	# Set multiplayer flag before starting game
	MultiplayerGameManager.is_multiplayer = true
	
	# Start appropriate game type
	if game_type == "Sudoku":
		_setup_multiplayer_sudoku()
	else:  # Solitaire
		# Check if mirror mode is enabled before starting new game
		var mirror_mode_enabled = false
		
		# For host, use the stored setting (host doesn't receive its own broadcast)
		if MultiplayerGameManager.network_manager.is_host:
			mirror_mode_enabled = MultiplayerGameManager.mirror_mode_enabled
			print("Main: Host using stored mirror mode setting: ", mirror_mode_enabled)
		# For client, check received settings
		elif NetworkManager.game_settings.has("mirror_mode"):
			mirror_mode_enabled = NetworkManager.game_settings["mirror_mode"]
			print("Main: Client using received mirror mode setting: ", mirror_mode_enabled)
		
		if not mirror_mode_enabled:
			# Host already created the game in start_multiplayer_race(), only client needs to create
			if not MultiplayerGameManager.network_manager.is_host:
				MultiplayerGameManager.start_local_game(difficulty)
				print("Main: Client creating game in non-mirror mode")
			else:
				print("Main: Host skipping start_local_game() - game already created in start_multiplayer_race()")
		else:
			print("Main: Mirror mode enabled, skipping start_local_game()")

		_setup_multiplayer_game()

func set_sudoku_mirror_mode(enabled: bool) -> void:
	"""Set the Sudoku mirror mode flag to prevent double game creation"""
	_sudoku_mirror_mode_enabled = enabled
	print("Main: Sudoku mirror mode flag set to: ", enabled)


func set_spider_mirror_mode(enabled: bool) -> void:
	"""Set the Spider mirror mode flag to prevent double game creation"""
	_spider_mirror_mode_enabled = enabled
	print("Main: Spider mirror mode flag set to: ", enabled)


func _setup_multiplayer_sudoku() -> void:
	"""Setup multiplayer Sudoku game"""
	print("Setting up multiplayer Sudoku...")
	print("DEBUG: _sudoku_mirror_mode_enabled: ", _sudoku_mirror_mode_enabled)
	print("DEBUG: _pending_mirror_data empty: ", MultiplayerGameManager._pending_mirror_data.is_empty())
	print("DEBUG: is_host: ", MultiplayerGameManager.network_manager.is_host)

	# Set game type in MultiplayerGameManager
	MultiplayerGameManager.current_game_type = "Sudoku"

	# Clear status label
	_status_label.text = ""

	# Always set up buttons and signals first — game may not be ready yet (mirror-mode client
	# waiting for mirror data), but the UI and signal wiring must happen now.
	# Connect multiplayer signals
	if not MultiplayerGameManager.player_status_changed.is_connected(_on_player_status_changed):
		MultiplayerGameManager.player_status_changed.connect(_on_player_status_changed)
	if not MultiplayerGameManager.last_player_standing.is_connected(_on_last_player_standing):
		MultiplayerGameManager.last_player_standing.connect(_on_last_player_standing)
	if not MultiplayerGameManager.race_ended.is_connected(_on_multiplayer_race_ended):
		MultiplayerGameManager.race_ended.connect(_on_multiplayer_race_ended)
	if not MultiplayerGameManager.all_players_ready.is_connected(_on_all_players_ready):
		MultiplayerGameManager.all_players_ready.connect(_on_all_players_ready)
	# race_started fires when the game is fully ready (initial round + new rounds with mirror data)
	if not MultiplayerGameManager.race_started.is_connected(_on_multiplayer_sudoku_race_ready):
		MultiplayerGameManager.race_started.connect(_on_multiplayer_sudoku_race_ready)

	# If the game is already ready (signal may have fired before connection), call handler immediately
	if MultiplayerGameManager.local_game and is_instance_valid(MultiplayerGameManager.local_game):
		print("Sudoku game already ready, calling setup immediately")
		_on_multiplayer_sudoku_race_ready()

	# Hide menu buttons
	_hide_menu_buttons()

	# Show game buttons (menu button only, no undo for Sudoku)
	_show_new_game_button()

	# Setup multiplayer UI
	_setup_multiplayer_ui()

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
	# Check if mirror mode is enabled and we need to wait for data
	var mirror_mode_enabled = false
	if NetworkManager.game_settings.has("mirror_mode"):
		mirror_mode_enabled = NetworkManager.game_settings["mirror_mode"]

	# If mirror mode is already enabled (from receive_mirror_data), use the pending data
	if _sudoku_mirror_mode_enabled and not MultiplayerGameManager._pending_mirror_data.is_empty():
		print("Client: Using pending mirror data for Sudoku (flag set)")
		print("DEBUG: Pending mirror data keys: ", MultiplayerGameManager._pending_mirror_data.keys())
		var mirror_data = MultiplayerGameManager._pending_mirror_data.duplicate(true)  # Duplicate to prevent clearing issues
		if mirror_data.has("puzzle"):
			print("DEBUG: Mirror data has puzzle, using it")
		else:
			print("DEBUG: Mirror data missing puzzle key!")
		# Clear pending data after duplicating
		MultiplayerGameManager._pending_mirror_data.clear()
		_sudoku_mirror_mode_enabled = false  # Reset flag
		# Create game with mirror data
		print("DEBUG: About to call _sudoku_game.new_game with mirror_data keys: ", mirror_data.keys())
		_sudoku_game.new_game(difficulty_level, true, mirror_data)
		_sudoku_board.set_game(_sudoku_game)
		print("Sudoku game created with mirror data (flag path)")
		# Connect game signals
		if not _sudoku_game.puzzle_completed.is_connected(_on_multiplayer_sudoku_completed):
			_sudoku_game.puzzle_completed.connect(_on_multiplayer_sudoku_completed)
		if not _sudoku_game.game_over.is_connected(_on_multiplayer_sudoku_game_over):
			_sudoku_game.game_over.connect(_on_multiplayer_sudoku_game_over)
		print("Multiplayer Sudoku game setup complete (flag path)")
		return

	if mirror_mode_enabled and MultiplayerGameManager._pending_mirror_data.is_empty() and not MultiplayerGameManager.network_manager.is_host:
		# Client with mirror mode enabled but no data yet - wait for it
		print("Client: Mirror mode enabled for Sudoku but no data yet, waiting...")
		# Buttons and signals are already set up above, so just return here
		return
	
	# Check if we have pending mirror data (client) or need to generate (host)
	if MultiplayerGameManager.network_manager.is_host:
		# Host: generate game and send mirror data to clients
		print("Host: Generating new Sudoku puzzle for mirror mode")
		_sudoku_game.new_game(difficulty_level, true)
		var host_mirror_data = _sudoku_game.get_mirror_data()
		MultiplayerGameManager.network_manager.send_mirror_data(host_mirror_data)
		print("Host: Generated Sudoku game and sent mirror data")
		_sudoku_board.set_game(_sudoku_game)
	else:
		# Client: check if we have mirror data or need to generate fallback
		if not MultiplayerGameManager._pending_mirror_data.is_empty():
			# Client: use mirror data from host
			print("Client: Using mirror data for Sudoku game")
			var mirror_data = MultiplayerGameManager._pending_mirror_data
			_sudoku_game.new_game(difficulty_level, true, mirror_data)
			MultiplayerGameManager._pending_mirror_data.clear()  # Clear after use
		else:
			# Fallback: generate normally
			print("Client: Fallback - generating Sudoku game normally")
			_sudoku_game.new_game(difficulty_level, true)
		_sudoku_board.set_game(_sudoku_game)

	# Connect Sudoku game signals
	if not _sudoku_game.puzzle_completed.is_connected(_on_multiplayer_sudoku_completed):
		_sudoku_game.puzzle_completed.connect(_on_multiplayer_sudoku_completed)
	if not _sudoku_game.game_over.is_connected(_on_multiplayer_sudoku_game_over):
		_sudoku_game.game_over.connect(_on_multiplayer_sudoku_game_over)

	print("Multiplayer Sudoku game setup complete")
	# TODO: Send completion to server for race tracking

func _on_multiplayer_sudoku_completed() -> void:
	"""Handle Sudoku completion in multiplayer"""
	print("Multiplayer Sudoku puzzle completed!")
	_status_label.text = "Puzzle Completed!"
	if SoundManager:
		SoundManager.play_win()

	# Report completion to multiplayer race system
	var completion_time = _sudoku_game.get_game_time() if _sudoku_game else 0.0
	NetworkManager.report_race_completion(completion_time)

func _on_multiplayer_sudoku_game_over() -> void:
	"""Handle Sudoku game over in multiplayer"""
	print("Multiplayer Sudoku game over - out of lives")
	_status_label.text = "Game Over - Out of Lives"
	if SoundManager:
		SoundManager.play_lose()

	# Report to multiplayer race system that player is jammed
	MultiplayerGameManager.forfeit_player()

func _setup_multiplayer_spider() -> void:
	"""Setup multiplayer Spider Solitaire game"""
	print("Setting up multiplayer Spider...")
	print("DEBUG: _spider_mirror_mode_enabled: ", _spider_mirror_mode_enabled)
	print("DEBUG: _pending_mirror_data empty: ", MultiplayerGameManager._pending_mirror_data.is_empty())
	print("DEBUG: is_host: ", MultiplayerGameManager.network_manager.is_host)

	# Set game type in MultiplayerGameManager
	MultiplayerGameManager.current_game_type = "Spider"

	# Clear status label
	_status_label.text = ""

	# Always set up buttons and signals first
	# Connect multiplayer signals
	if not MultiplayerGameManager.player_status_changed.is_connected(_on_player_status_changed):
		MultiplayerGameManager.player_status_changed.connect(_on_player_status_changed)
	if not MultiplayerGameManager.last_player_standing.is_connected(_on_last_player_standing):
		MultiplayerGameManager.last_player_standing.connect(_on_last_player_standing)
	if not MultiplayerGameManager.race_ended.is_connected(_on_multiplayer_race_ended):
		MultiplayerGameManager.race_ended.connect(_on_multiplayer_race_ended)
	if not MultiplayerGameManager.all_players_ready.is_connected(_on_all_players_ready):
		MultiplayerGameManager.all_players_ready.connect(_on_all_players_ready)
	# race_started fires when the game is fully ready
	if not MultiplayerGameManager.race_started.is_connected(_on_multiplayer_spider_race_ready):
		MultiplayerGameManager.race_started.connect(_on_multiplayer_spider_race_ready)

	# Hide menu buttons
	_hide_menu_buttons()

	# Show game buttons (menu button only)
	_show_new_game_button()

	# Setup multiplayer UI
	_setup_multiplayer_ui()

	# Get difficulty level
	var difficulty_string = _current_difficulty  # "Easy", "Medium", or "Hard"

	# Check if mirror mode is enabled
	var mirror_mode_enabled = false
	if MultiplayerGameManager.network_manager.is_host:
		# Host uses the stored mirror mode setting from MultiplayerGameManager
		mirror_mode_enabled = MultiplayerGameManager.mirror_mode_enabled
	elif NetworkManager.game_settings.has("mirror_mode"):
		# Client uses the setting from the host
		mirror_mode_enabled = NetworkManager.game_settings["mirror_mode"]

	# If mirror mode is already enabled (from receive_mirror_data), use the pending data
	if _spider_mirror_mode_enabled and not MultiplayerGameManager._pending_mirror_data.is_empty():
		print("Client: Using pending mirror data for Spider (flag set)")
		var mirror_data = MultiplayerGameManager._pending_mirror_data.duplicate(true)
		if mirror_data.has("deck"):
			print("DEBUG: Mirror data has deck, using it")
		else:
			print("DEBUG: Mirror data missing deck key!")
		# Clear pending data after duplicating
		MultiplayerGameManager._pending_mirror_data.clear()
		_spider_mirror_mode_enabled = false  # Reset flag
		# Initialize board and create game with mirror data
		_spider_board.new_game(difficulty_string)
		_spider_board._game.new_game_mirror(mirror_data)
		_spider_board.render()
		print("Spider game created with mirror data (flag path)")
		# Connect game signals
		if not _spider_board.game_won.is_connected(_on_multiplayer_spider_completed):
			_spider_board.game_won.connect(_on_multiplayer_spider_completed)
		if not _spider_board._game.card_moved.is_connected(_on_multiplayer_spider_card_moved):
			_spider_board._game.card_moved.connect(_on_multiplayer_spider_card_moved)
		print("Multiplayer Spider game setup complete (flag path)")
		return

	if mirror_mode_enabled and MultiplayerGameManager._pending_mirror_data.is_empty() and not MultiplayerGameManager.network_manager.is_host:
		# Client with mirror mode enabled but no data yet - wait for it
		print("Client: Mirror mode enabled for Spider but no data yet, waiting...")
		return

	# Check if we have pending mirror data (client) or need to generate (host)
	if MultiplayerGameManager.network_manager.is_host:
		# Host: generate game and send mirror data to clients
		_spider_board.new_game(difficulty_string)
		if mirror_mode_enabled:
			print("Host: Generating new Spider deck for mirror mode")
			var host_mirror_data = _spider_board._game.get_mirror_data()
			NetworkManager.send_mirror_data({"game_type": "Spider", "mirror_data": host_mirror_data})
			print("Host: Generated Spider game and sent mirror data")
		else:
			print("Host: Mirror mode disabled, generating random game")
	else:
		# Client: check if we have mirror data or need to generate fallback
		if not MultiplayerGameManager._pending_mirror_data.is_empty():
			# Client: use mirror data from host
			print("Client: Using mirror data for Spider game")
			var mirror_data = MultiplayerGameManager._pending_mirror_data
			_spider_board.new_game(difficulty_string)
			_spider_board._game.new_game_mirror(mirror_data)
			MultiplayerGameManager._pending_mirror_data.clear()  # Clear after use
		else:
			# Fallback: generate normally
			print("Client: Fallback - generating Spider game normally")
			_spider_board.new_game(difficulty_string)

	# Connect Spider game signals
	if _spider_board._game:
		if not _spider_board.game_won.is_connected(_on_multiplayer_spider_completed):
			_spider_board.game_won.connect(_on_multiplayer_spider_completed)
		if not _spider_board._game.card_moved.is_connected(_on_multiplayer_spider_card_moved):
			_spider_board._game.card_moved.connect(_on_multiplayer_spider_card_moved)

	print("Multiplayer Spider game setup complete")

func _on_multiplayer_spider_race_ready() -> void:
	"""Called when multiplayer Spider race is ready"""
	_setup_multiplayer_spider()
	if _player_status_label:
		_player_status_label.text = "Race in progress..."

func _on_multiplayer_spider_completed() -> void:
	"""Handle Spider completion in multiplayer"""
	print("Multiplayer Spider game completed!")
	_status_label.text = "Game Won!"
	if SoundManager:
		SoundManager.play_win()

	# Report completion to multiplayer race system
	var completion_time = (Time.get_ticks_msec() / 1000.0) - MultiplayerGameManager.race_start_time
	NetworkManager.report_race_completion(completion_time)

	if _player_status_label:
		_player_status_label.text = "You won! Waiting for others..."

func _on_multiplayer_spider_card_moved() -> void:
	"""Handle card move event for Spider in multiplayer"""
	# Check if player is jammed
	if MultiplayerGameManager._pending_mirror_data.is_empty() or not _spider_board or not _spider_board._game:
		return
	MultiplayerGameManager.check_player_status()

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
	
	# Leave game button (top right, next to menu button) - FontAwesome times-circle icon
	var leave_button = Button.new()
	leave_button.name = "leave_game_button"
	var bottom_padding = 0
	var left_padding = 0
	if DisplayServer.get_name() == "iOS":
		var safe_area = DisplayServer.get_display_safe_area()
		bottom_padding = safe_area.size.y - get_viewport().get_visible_rect().size.y
		left_padding = safe_area.position.x
	# Position leave button to the right of the menu button (top area)
	var top_padding = 10
	if OS.has_feature("mobile"):
		var safe_area = DisplayServer.get_display_safe_area()
		top_padding = max(10, safe_area.position.y)
	
	# Position to the right of the menu button (which is at 10, top_padding with size 100x100)
	var leave_x = 120 + left_padding  # Right of menu button (10 + 100 + 10 spacing)
	var leave_y = top_padding  # Same vertical level as menu button
	
	leave_button.position = Vector2(leave_x, leave_y)
	leave_button.size = Vector2(100, 100)
	leave_button.tooltip_text = "Leave Game"
	leave_button.pressed.connect(_on_leave_game_button_pressed)
	
	# Make button background transparent
	var leave_transparent_style = StyleBoxFlat.new()
	leave_transparent_style.bg_color = Color(0, 0, 0, 0)  # Fully transparent
	leave_transparent_style.draw_center = false  # Don't draw background
	leave_button.add_theme_stylebox_override("normal", leave_transparent_style)
	leave_button.add_theme_stylebox_override("hover", leave_transparent_style)
	leave_button.add_theme_stylebox_override("pressed", leave_transparent_style)
	leave_button.add_theme_stylebox_override("disabled", leave_transparent_style)
	
	# Add FontAwesome circle-xmark icon (FontAwesome 6 naming)
	var leave_icon = FontAwesome.new()
	leave_icon.icon_name = "circle-xmark"
	leave_icon.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))  # Red color
	leave_icon.icon_size = 64
	leave_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leave_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	leave_button.add_child(leave_icon)
	
	add_child(leave_button)

func _on_multiplayer_race_ended(winner_id: int, winner_name: String, time: float) -> void:
	"""Handle race completion - disable gameplay and show ready screen"""
	print("DEBUG: _on_multiplayer_race_ended called - winner_id: ", winner_id, ", winner_name: ", winner_name)
	# Disable all game interactions for Solitaire, Sudoku, and Spider
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _sudoku_board:
		_sudoku_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _spider_board:
		_spider_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
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
	_last_standing_notification.z_index = 1000  # Ensure it appears above board/cards
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
	print("DEBUG: _on_player_status_changed called - Player ", player_id, " status changed to: ", status)
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
	_last_standing_notification.z_index = 1000  # Ensure it appears above board/cards
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

	# Use the game type from MultiplayerGameManager, which is synced across all players
	var current_game_type = MultiplayerGameManager.current_game_type
	if current_game_type.is_empty():
		# Fallback to local game type if not set
		current_game_type = _current_game_type
	print("DEBUG: _on_all_players_ready - current_game_type from MGM: ", MultiplayerGameManager.current_game_type, ", fallback: ", _current_game_type)

	# Re-enable board interactions for current game type
	if current_game_type == "Sudoku":
		if _sudoku_board:
			_sudoku_board.mouse_filter = Control.MOUSE_FILTER_STOP
			# Render to clear any win/game-over overlays from the previous round
			_sudoku_board.render()

		# Check if mirror mode is enabled for restart
		var mirror_mode_enabled = false
		if MultiplayerGameManager.network_manager.is_host:
			mirror_mode_enabled = MultiplayerGameManager.mirror_mode_enabled
			print("Main: Host restart using stored mirror mode setting: ", mirror_mode_enabled)
		elif NetworkManager.game_settings.has("mirror_mode"):
			mirror_mode_enabled = NetworkManager.game_settings["mirror_mode"]
			print("Main: Client restart using received mirror mode setting: ", mirror_mode_enabled)

		if mirror_mode_enabled and not MultiplayerGameManager.network_manager.is_host:
			# Client: Reset mirror mode state and wait for new data
			_sudoku_mirror_mode_enabled = true
			MultiplayerGameManager._pending_mirror_data.clear()
			print("Main: Client reset mirror mode state for restart")

		# For mirror mode Sudoku, board re-setup happens via race_started signal after _start_new_round()
		# sends the new puzzle. This is called next (indirectly through MultiplayerGameManager._check_all_players_ready).
		# Just reset the status label here.
		if _player_status_label:
			_player_status_label.text = "Race in progress..."
	elif current_game_type == "Spider":
		if _spider_board:
			_spider_board.mouse_filter = Control.MOUSE_FILTER_STOP

		# Re-enable forfeit button
		for child in get_children():
			if child is Button and child.name == "new_game":
				child.disabled = false
				child.tooltip_text = "Forfeit (Mark as Jammed)"

		if _player_status_label:
			_player_status_label.text = "Race in progress..."
	else:  # Solitaire
		# Re-enable board interactions after forfeit
		if _board:
			_board.mouse_filter = Control.MOUSE_FILTER_STOP

		# Re-enable forfeit button
		for child in get_children():
			if child is Button and child.name == "new_game":
				child.disabled = false
				child.tooltip_text = "Forfeit (Mark as Jammed)"

		# Board re-setup happens in _on_multiplayer_race_board_ready()
		# which fires when MultiplayerGameManager.race_started is emitted after _start_new_round()
		if _player_status_label:
			_player_status_label.text = "Race in progress..."

func _on_forfeit_pressed() -> void:
	"""Handle forfeit button press in multiplayer"""
	# Mark player as jammed
	MultiplayerGameManager.forfeit_player()

	# Disable all game interactions
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _current_game_type == "Sudoku":
		_sudoku_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif _current_game_type == "Spider":
		if _spider_board:
			_spider_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
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

func _on_settings_button_pressed() -> void:
	"""Show the settings page over the menu backdrop"""
	var existing_settings = get_node_or_null("SettingsMenu")
	if existing_settings:
		existing_settings.queue_free()
	
	# Hide main menu
	_menu_container.visible = false
	
	# Hide settings button to prevent duplicate clicks
	var settings_button = get_node_or_null("settings_button")
	if settings_button:
		settings_button.visible = false
	
	var is_mobile := OS.has_feature("mobile")
	var accent := _menu_accent
	var viewport_size := get_viewport_rect().size
	var top_padding: float = DisplayServer.get_display_safe_area().position.y if is_mobile else 0.0
	
	# Full-screen page; the menu background shows through
	var settings_root = MarginContainer.new()
	settings_root.name = "SettingsMenu"
	settings_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_root.add_theme_constant_override("margin_top", int(top_padding) + 60)
	settings_root.add_theme_constant_override("margin_bottom", 60)
	add_child(settings_root)
	
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_root.add_child(scroll)
	
	var center = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	
	var settings_menu = VBoxContainer.new()
	settings_menu.custom_minimum_size = Vector2(minf(viewport_size.x - 100.0, 760.0), 0)
	settings_menu.add_theme_constant_override("separation", 28)
	center.add_child(settings_menu)
	
	settings_menu.add_child(WastelandStyle.title("SETTINGS", 84 if is_mobile else 68))
	settings_menu.add_child(WastelandStyle.label("— tune the wasteland —", 30, WastelandStyle.BONE_MUTED, 2))
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	settings_menu.add_child(spacer)
	
	# Player card: name + save
	var player_box = _settings_card(settings_menu, "PLAYER", accent)
	var name_row = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 18)
	player_box.add_child(name_row)
	
	var player_name_input = LineEdit.new()
	player_name_input.placeholder_text = "Enter your name"
	player_name_input.text = PlayerData.get_player_name()
	player_name_input.custom_minimum_size = Vector2(0, 96)
	player_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_name_input.max_length = 20
	WastelandStyle.style_line_edit(player_name_input, accent)
	name_row.add_child(player_name_input)
	
	var save_name_button = WastelandStyle.make_button("SAVE", accent, true, Vector2(180, 96), 34)
	save_name_button.pressed.connect(_on_save_player_name.bind(player_name_input, save_name_button))
	name_row.add_child(save_name_button)
	
	# Appearance card
	var appearance_box = _settings_card(settings_menu, "APPEARANCE", accent)
	var dark_mode_toggle = CheckButton.new()
	dark_mode_toggle.text = "DARK MODE"
	dark_mode_toggle.button_pressed = (PlayerData.get_theme() == "dark")
	WastelandStyle.style_switch(dark_mode_toggle, accent)
	dark_mode_toggle.toggled.connect(_on_dark_mode_toggled)
	appearance_box.add_child(dark_mode_toggle)
	
	# Sound card
	var sound_box = _settings_card(settings_menu, "SOUND", accent)
	var music_toggle = CheckButton.new()
	music_toggle.text = "BACKGROUND MUSIC"
	music_toggle.button_pressed = PlayerData.is_background_music_enabled()
	WastelandStyle.style_switch(music_toggle, accent)
	music_toggle.toggled.connect(_on_background_music_toggled)
	sound_box.add_child(music_toggle)
	
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	settings_menu.add_child(spacer2)
	
	var back_button = WastelandStyle.make_button("BACK", accent, false, Vector2(360, 104), 40)
	back_button.pressed.connect(_on_settings_back)
	settings_menu.add_child(back_button)
	
	# Fade in
	settings_root.modulate.a = 0.0
	create_tween().tween_property(settings_root, "modulate:a", 1.0, 0.3)

func _settings_card(parent: Control, heading: String, accent: Color) -> VBoxContainer:
	"""Add a titled card to the settings page and return its content box"""
	var card = WastelandStyle.card(accent)
	parent.add_child(card)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	card.add_child(box)
	box.add_child(WastelandStyle.section_header(heading))
	return box

func _on_save_player_name(name_input: LineEdit, save_button: Button = null) -> void:
	"""Save player name from input field"""
	var new_name = name_input.text.strip_edges()
	if new_name != "":
		PlayerData.set_player_name(new_name)
		print("Player name saved: ", new_name)
		if save_button:
			save_button.text = "SAVED"
			get_tree().create_timer(1.2).timeout.connect(func():
				if is_instance_valid(save_button):
					save_button.text = "SAVE")

func _on_dark_mode_toggled(toggled_on: bool) -> void:
	"""Handle dark mode toggle"""
	var new_theme = "dark" if toggled_on else "light"
	print("Toggle clicked: ", toggled_on, " -> New theme: ", new_theme)
	PlayerData.set_theme(new_theme)
	
	# Update backgrounds immediately
	var game_bg = get_node_or_null("GameBackground")
	var menu_bg = get_node_or_null("MenuBackground")
	
	print("Updating backgrounds...")
	if game_bg:
		# Update game background based on current game type
		if _current_game_type != "":
			_update_game_background(_current_game_type)
		else:
			# No game type set, use default
			game_bg.color = Color(0.2, 0.4, 0.7) if new_theme == "light" else Color(0.1, 0.1, 0.1)
		print("Game background updated to: ", game_bg.color)
	
	if menu_bg:
		menu_bg.color = Color(0.2, 0.4, 0.7) if new_theme == "light" else Color(0.1, 0.1, 0.1)
		print("Menu background updated to: ", menu_bg.color)
	
	# Update Sudoku board theme if it exists
	if _sudoku_board:
		_sudoku_board.update_theme()
		print("Sudoku board theme updated")
	
	print("Theme changed to: ", new_theme)

func _on_background_music_toggled(toggled_on: bool) -> void:
	"""Handle background music toggle"""
	PlayerData.set_background_music_enabled(toggled_on)
	print("Background music toggled: ", toggled_on)

	if toggled_on:
		# Start playing background music
		if SoundManager:
			SoundManager.play_background_music()
	else:
		# Stop background music
		if SoundManager:
			SoundManager.stop_background_music()

func _on_settings_back() -> void:
	"""Handle settings back button"""
	print("DEBUG: Settings back button PRESSED!")
	
	var settings_menu = get_node_or_null("SettingsMenu")
	if settings_menu:
		settings_menu.queue_free()
	
	# Show settings button again
	var settings_button = get_node_or_null("settings_button")
	if settings_button:
		settings_button.visible = true
		print("DEBUG: Settings button made visible")
	
	# Show main menu (this will update the background to current theme)
	print("DEBUG: Settings back - calling _show_main_menu")
	_show_main_menu()
	
	# Force update menu background to ensure theme change is visible
	var menu_bg = get_node_or_null("MenuBackground")
	if menu_bg:
		var current_theme = PlayerData.get_theme()
		menu_bg.color = Color(0.2, 0.4, 0.7) if current_theme == "light" else Color(0.1, 0.1, 0.1)
		menu_bg.visible = true
		print("DEBUG: Menu background updated to: ", menu_bg.color, " visible: ", menu_bg.visible)
	
	print("DEBUG: Settings back function completed")

func _save_current_game_if_in_progress() -> void:
	"""Save the current game state if a game is in progress and has been played meaningfully (1+ min)"""
	if _current_game_type.is_empty():
		return  # No game in progress

	# Only save if game has been played for at least 1 minute (meaningful progress)
	if not _has_game_been_played_meaningfully():
		print("Game not played long enough, not saving")
		return

	match _current_game_type:
		"Solitaire":
			if _game:
				var save_data = _game.get_save_data()
				PlayerData.save_game("Solitaire", save_data)
				print("Saved Solitaire game")
		"Spider":
			if _spider_board and _spider_board._game:
				var save_data = _spider_board._game.get_save_data()
				PlayerData.save_game("Spider", save_data)
				print("Saved Spider game")
		"Sudoku":
			if _sudoku_game:
				var save_data = _sudoku_game.get_save_data()
				PlayerData.save_game("Sudoku", save_data)
				print("Saved Sudoku game")

func _has_game_been_played_meaningfully() -> bool:
	"""Check if the current game has been played meaningfully (1+ min for all games)"""
	var min_play_time = 60.0  # 1 minute in seconds

	match _current_game_type:
		"Solitaire":
			if _game:
				var play_time = _game.get_game_time()
				return play_time >= min_play_time
		"Spider":
			if _spider_board and _spider_board._game:
				var play_time = _spider_board._game.get_game_time()
				return play_time >= min_play_time
		"Sudoku":
			if _sudoku_game:
				var play_time = _sudoku_game.get_game_time()
				return play_time >= min_play_time

	return false

func _check_and_show_saved_games() -> void:
	"""Check for saved games and show continue/new game prompt"""
	# Check each game type for saved games
	var saved_games: Array = []
	if PlayerData.has_saved_game("Solitaire"):
		saved_games.append("Solitaire")
	if PlayerData.has_saved_game("Spider"):
		saved_games.append("Spider")
	if PlayerData.has_saved_game("Sudoku"):
		saved_games.append("Sudoku")

	if saved_games.is_empty():
		return  # No saved games, proceed normally

	# Show dialog asking to continue or start new
	_show_continue_game_dialog(saved_games)

func _check_and_show_saved_games_for_type(game_type: String) -> void:
	"""Check for saved game of a specific type and show continue/new game prompt"""
	if not PlayerData.has_saved_game(game_type):
		return  # No saved game for this type, proceed normally

	# Show dialog asking to continue or start new
	_show_continue_game_dialog_for_type(game_type)

func _show_continue_game_dialog(saved_games: Array) -> void:
	"""Show dialog offering to continue or start new game"""
	# Create notification panel matching ready notification style
	var dialog = Panel.new()
	dialog.name = "ContinueGameDialog"
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.anchor_left = 0.5
	dialog.anchor_top = 0.5
	dialog.anchor_right = 0.5
	dialog.anchor_bottom = 0.5
	dialog.offset_left = -350
	dialog.offset_top = -220
	dialog.offset_right = 350
	dialog.offset_bottom = 220
	dialog.z_index = 1000
	add_child(dialog)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 25)
	dialog.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Saved Games Found"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)

	# Message
	var message = Label.new()
	message.text = "You have saved games in progress.\nWhat would you like to do?"
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size", 28)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(message)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(spacer)

	# Continue button - positioned on left side
	var continue_btn = Button.new()
	continue_btn.text = "Continue"
	continue_btn.custom_minimum_size = Vector2(160, 70)
	continue_btn.add_theme_font_size_override("font_size", 28)
	continue_btn.pressed.connect(func():
		_handle_continue_game(saved_games[0])  # Continue the first saved game
		dialog.queue_free()
	)
	continue_btn.anchor_left = 0.25
	continue_btn.anchor_right = 0.25
	continue_btn.anchor_top = 0.75
	continue_btn.anchor_bottom = 0.75
	continue_btn.offset_left = -80
	continue_btn.offset_right = 80
	continue_btn.offset_top = -35
	continue_btn.offset_bottom = 35
	dialog.add_child(continue_btn)

	# New Game button - positioned on right side
	var new_game_btn = Button.new()
	new_game_btn.text = "New Game"
	new_game_btn.custom_minimum_size = Vector2(160, 70)
	new_game_btn.add_theme_font_size_override("font_size", 28)
	new_game_btn.pressed.connect(func():
		# Clear all saves and proceed with new game
		for game_type in saved_games:
			PlayerData.clear_saved_game(game_type)
		dialog.queue_free()
	)
	new_game_btn.anchor_left = 0.75
	new_game_btn.anchor_right = 0.75
	new_game_btn.anchor_top = 0.75
	new_game_btn.anchor_bottom = 0.75
	new_game_btn.offset_left = -80
	new_game_btn.offset_right = 80
	new_game_btn.offset_top = -35
	new_game_btn.offset_bottom = 35
	dialog.add_child(new_game_btn)

func _show_continue_game_dialog_for_type(game_type: String) -> void:
	"""Show dialog offering to continue or start new game for a specific type"""
	# Create notification panel matching ready notification style
	var dialog = Panel.new()
	dialog.name = "ContinueGameDialog"
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.anchor_left = 0.5
	dialog.anchor_top = 0.5
	dialog.anchor_right = 0.5
	dialog.anchor_bottom = 0.5
	dialog.offset_left = -350
	dialog.offset_top = -220
	dialog.offset_right = 350
	dialog.offset_bottom = 220
	dialog.z_index = 1000
	add_child(dialog)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 25)
	dialog.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Saved Game Found"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)

	# Message
	var message = Label.new()
	message.text = "You have a saved %s game in progress.\nWhat would you like to do?" % game_type
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size", 28)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(message)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(spacer)

	# Continue button - positioned on left side
	var continue_btn = Button.new()
	continue_btn.text = "Continue"
	continue_btn.custom_minimum_size = Vector2(160, 70)
	continue_btn.add_theme_font_size_override("font_size", 28)
	continue_btn.pressed.connect(func():
		_handle_continue_game(game_type)
		dialog.queue_free()
	)
	continue_btn.anchor_left = 0.25
	continue_btn.anchor_right = 0.25
	continue_btn.anchor_top = 0.75
	continue_btn.anchor_bottom = 0.75
	continue_btn.offset_left = -80
	continue_btn.offset_right = 80
	continue_btn.offset_top = -35
	continue_btn.offset_bottom = 35
	dialog.add_child(continue_btn)

	# New Game button - positioned on right side
	var new_game_btn = Button.new()
	new_game_btn.text = "New Game"
	new_game_btn.custom_minimum_size = Vector2(160, 70)
	new_game_btn.add_theme_font_size_override("font_size", 28)
	new_game_btn.pressed.connect(func():
		PlayerData.clear_saved_game(game_type)
		_start_new_game_after_dialog(game_type)
		dialog.queue_free()
	)
	new_game_btn.anchor_left = 0.75
	new_game_btn.anchor_right = 0.75
	new_game_btn.anchor_top = 0.75
	new_game_btn.anchor_bottom = 0.75
	new_game_btn.offset_left = -80
	new_game_btn.offset_right = 80
	new_game_btn.offset_top = -35
	new_game_btn.offset_bottom = 35
	dialog.add_child(new_game_btn)

func _start_new_game_after_dialog(game_type: String) -> void:
	"""Start a new game after the continue/new game dialog is handled"""
	# Update background based on game type
	_update_game_background(game_type)

	# Hide settings button when game starts
	var settings_button = get_node_or_null("settings_button")
	if settings_button:
		settings_button.visible = false

	# Hide menu button when game starts
	if _menu_button:
		_menu_button.visible = false

	# Start game based on selection
	if game_type == "Solitaire":
		PlayerData.clear_saved_game("Solitaire")
		MultiplayerGameManager.start_local_game(_current_difficulty)
		_setup_single_player_game()
	elif game_type == "Spider":
		_setup_spider_game()
	else:  # Sudoku
		PlayerData.clear_saved_game("Sudoku")
		_setup_single_player_sudoku()

func _handle_continue_game(game_type: String) -> void:
	"""Load and continue the specified saved game"""
	var save_data = PlayerData.load_game(game_type)
	_current_game_type = game_type
	var difficulty = save_data.get("difficulty", "Medium")
	# Convert difficulty to string if it's an integer (for Sudoku compatibility)
	if difficulty is int:
		match difficulty:
			1: _current_difficulty = "Easy"
			3: _current_difficulty = "Medium"
			5: _current_difficulty = "Hard"
			_: _current_difficulty = "Medium"
	else:
		_current_difficulty = str(difficulty)

	print("Continuing saved game: ", game_type)
	_hide_main_menu()
	_update_game_background(game_type)

	match game_type:
		"Solitaire":
			# Create the game first (normally done by start_local_game)
			MultiplayerGameManager.start_local_game(_current_difficulty)
			_setup_single_player_game()
			# Load saved state into the game
			if _game and not save_data.is_empty():
				_game.restore_from_save(save_data)
				_board.render()
		"Spider":
			_setup_spider_game()
			# Load saved state into the game
			if _spider_board and _spider_board._game and not save_data.is_empty():
				_spider_board._game.restore_from_save(save_data)
				_spider_board.render()
		"Sudoku":
			_setup_single_player_sudoku()
			# Load saved state into the game
			if _sudoku_game and not save_data.is_empty():
				_sudoku_game.restore_from_save(save_data)
				_sudoku_board.render()
