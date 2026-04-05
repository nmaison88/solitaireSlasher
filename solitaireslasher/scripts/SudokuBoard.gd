extends Control
class_name SudokuBoard

var game: SudokuGame
var grid_buttons = []  # 9x9 array of buttons
var selected_cell: Vector2i = Vector2i(-1, -1)

# UI elements
var grid_container: GridContainer
var number_selector: GridContainer
var hearts_container: HBoxContainer
var heart_icons = []  # Array of 3 heart labels
var game_over_overlay: Panel
var win_overlay: Panel
var border_overlay: Control  # Overlay for 3x3 subgrid borders
var erase_button: Button  # Erase button for incorrect values
var _number_buttons: Dictionary = {}  # number (1-9) -> Button reference

# Theme colors
var theme_colors: Dictionary = {}

const GRID_SIZE = 9
var cell_size: float  # Dynamic cell size calculated based on screen
var number_button_size: float  # Dynamic button size
var spacing: int = 2  # Grid spacing

signal game_completed

func _init_theme_colors() -> void:
	"""Initialize theme colors based on player settings"""
	var theme_mode = PlayerData.get_theme()
	
	if theme_mode == "light":
		theme_colors = {
			"cell": Color(0.75, 0.80, 0.90),  # Light blue-gray
			"text": Color(0.0, 0.0, 0.0),  # Black text
			"user_text": Color(0.0, 0.0, 0.0),  # Black text for user input (better visibility)
			"highlight_row": Color(0.85, 0.90, 1.0),  # Bright blue
			"highlight_match": Color(0.60, 0.70, 1.0),  # Darker blue
			"selected": Color(0.7, 0.85, 1.0),  # Light blue highlight
			"border": Color(0.0, 0.0, 0.0)  # Black borders for 3x3 subgrids
		}
	else:  # dark mode
		theme_colors = {
			"cell": Color(0.2, 0.2, 0.2),  # Dark gray cells
			"text": Color(1.0, 1.0, 1.0),  # White text
			"user_text": Color(1.0, 1.0, 1.0),  # White text for user input (matching seeded text)
			"highlight_row": Color(0, 0.1, 0.2, 0.5),  # Dark blue highlight
			"highlight_match": Color(0.1, 0.2, 0.4),  # Darker blue
			"selected": Color(0.3, 0.4, 0.6),  # Medium blue
			"border": Color(0.0, 0.0, 0.0)  # Black borders for 3x3 subgrids
		}

func _ready():
	print("=== SudokuBoard._ready() called ===")
	_init_theme_colors()
	_create_ui()

func _create_ui():
	print("=== SudokuBoard._create_ui() called ===")
	
	# SECTION 1: Dynamic sizing calculation
	var viewport_rect = get_viewport_rect()
	var screen_width = viewport_rect.size.x
	var screen_height = viewport_rect.size.y
	
	# Compute board size using the formula
	var board_size = min(screen_width, screen_height * 0.6)
	
	# Compute cell size
	cell_size = (board_size - spacing * (GRID_SIZE - 1)) / GRID_SIZE
	number_button_size = cell_size
	
	print("Dynamic sizing - Screen: ", Vector2(screen_width, screen_height), " Board size: ", board_size, " Cell size: ", cell_size)
	
	# Hearts container (lives) - positioned above the Sudoku grid
	hearts_container = HBoxContainer.new()
	hearts_container.custom_minimum_size = Vector2(0, 90)  # Height for hearts
	hearts_container.add_theme_constant_override("separation", 20)
	hearts_container.alignment = BoxContainer.ALIGNMENT_CENTER  # Center horizontally
	
	# SECTION 5: Make hearts responsive
	hearts_container.anchor_left = 0.0
	hearts_container.anchor_right = 1.0
	hearts_container.offset_left = 0
	hearts_container.offset_right = 0
	hearts_container.offset_top = screen_height * 0.05
	hearts_container.offset_bottom = hearts_container.offset_top + 80
	
	add_child(hearts_container)
	print("Hearts container added above grid at y=220")
	
	# Create 3 heart icons using FontAwesome - just red hearts, no background circles
	for i in range(3):
		# Create FontAwesome heart icon directly (no background panel)
		var heart_icon = FontAwesome.new()
		heart_icon.icon_name = "heart"
		heart_icon.icon_type = "solid"
		heart_icon.icon_size = 60  # Larger since no background
		heart_icon.modulate = Color(1.0, 0.0, 0.0)  # Red heart
		heart_icon.custom_minimum_size = Vector2(80, 80)
		heart_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		hearts_container.add_child(heart_icon)
		heart_icons.append(heart_icon)
		
		print("Heart ", i + 1, " created as red FontAwesome icon (no background)")
	
	# Ensure hearts container is visible
	hearts_container.z_index = 10
	hearts_container.visible = true
	print("Hearts container created at position: ", hearts_container.position)
	
	# Create game over overlay (hidden by default)
	game_over_overlay = Panel.new()
	game_over_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over_overlay.visible = false
	add_child(game_over_overlay)
	
	# Matrix-style shader background
	var shader_bg = ColorRect.new()
	shader_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# Load and apply shader
	var shader = load("res://shaders/matrix_background.gdshader")
	var shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	shader_material.set_shader_parameter("columns", 40.0)
	shader_material.set_shader_parameter("rows", 30.0)
	shader_material.set_shader_parameter("speed", 3.0)
	shader_material.set_shader_parameter("char_color", Color(1.0, 0.0, 0.0, 1.0))  # Red for lose
	shader_material.set_shader_parameter("bg_color", Color(0.0, 0.0, 0.0, 0.9))
	shader_bg.material = shader_material
	shader_bg.z_index = 0
	game_over_overlay.add_child(shader_bg)
	
	# "YOU LOST!" text in center (on top of shader) - larger for mobile
	var lost_label = Label.new()
	lost_label.text = "YOU LOST!"
	lost_label.add_theme_font_size_override("font_size", 128)
	lost_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))  # White text
	lost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lost_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	lost_label.z_index = 1
	game_over_overlay.add_child(lost_label)
	
	# Create win overlay (hidden by default)
	win_overlay = Panel.new()
	win_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_overlay.visible = false
	add_child(win_overlay)
	
	# Matrix-style shader background for win (green/cyan)
	var win_shader_bg = ColorRect.new()
	win_shader_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var win_shader = load("res://shaders/matrix_background.gdshader")
	var win_shader_material = ShaderMaterial.new()
	win_shader_material.shader = win_shader
	win_shader_material.set_shader_parameter("columns", 40.0)
	win_shader_material.set_shader_parameter("rows", 30.0)
	win_shader_material.set_shader_parameter("speed", 3.0)
	win_shader_material.set_shader_parameter("char_color", Color(0.0, 1.0, 0.8, 1.0))  # Cyan for win
	win_shader_material.set_shader_parameter("bg_color", Color(0.0, 0.0, 0.0, 0.9))
	win_shader_bg.material = win_shader_material
	win_shader_bg.z_index = 0
	win_overlay.add_child(win_shader_bg)
	
	# "YOU WON!" text in center - larger for mobile
	var win_label = Label.new()
	win_label.text = "YOU WON!"
	win_label.add_theme_font_size_override("font_size", 128)
	win_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))  # White text
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	win_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_label.z_index = 1
	win_overlay.add_child(win_label)
	
	# Main grid container for the 9x9 Sudoku grid
	# Board: 9 cells * 80px + 8 gaps * 2px = 720 + 16 = 736px width
	# Screen width: 1024px, center: (1024 - 736) / 2 = 144px
	# Board height: 9 cells * 80px + 8 gaps * 2px = 736px
	# SECTION 2: Make grid_container responsive
	var grid_width = cell_size * GRID_SIZE + spacing * (GRID_SIZE - 1)
	
	grid_container = GridContainer.new()
	grid_container.columns = GRID_SIZE
	
	# Set position to center horizontally and place near top
	var grid_x = (screen_width - grid_width) / 2
	var grid_y = screen_height * 0.15
	grid_container.position = Vector2(grid_x, grid_y)
	
	grid_container.add_theme_constant_override("h_separation", spacing)
	grid_container.add_theme_constant_override("v_separation", spacing)
	add_child(grid_container)
	
	print("Grid positioned at: ", Vector2(grid_x, grid_y), " with width: ", grid_width)
	
	# SECTION 6: Make erase button responsive
	erase_button = Button.new()
	var button_width = 100
	var button_height = 80
	erase_button.custom_minimum_size = Vector2(button_width, button_height)
	
	# Place it below the grid
	var erase_x = (screen_width - button_width) / 2
	var erase_y = grid_container.position.y + grid_width + 20
	erase_button.position = Vector2(erase_x, erase_y)
	erase_button.disabled = true  # Start disabled
	erase_button.pressed.connect(_on_erase_pressed)
	
	# Add FontAwesome eraser icon
	var erase_icon = FontAwesome.new()
	erase_icon.icon_name = "eraser"
	erase_icon.icon_type = "solid"
	erase_icon.icon_size = 48
	erase_icon.modulate = Color(1.0, 1.0, 1.0)  # White icon
	erase_icon.position = Vector2(26, 16)  # Center in button
	erase_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	erase_button.add_child(erase_icon)
	add_child(erase_button)
	
	# SECTION 7: Make number selector responsive
	number_selector = GridContainer.new()
	number_selector.columns = 9
	
	# Use same spacing as grid to match width exactly
	number_selector.add_theme_constant_override("h_separation", spacing)
	
	# Align horizontally with the grid (same x position)
	var selector_x = (screen_width - grid_width) / 2
	
	# Place vertically below erase button
	var selector_y = erase_button.position.y + 100
	number_selector.position = Vector2(selector_x, selector_y)
	add_child(number_selector)
	
	print("Number selector positioned at: ", Vector2(selector_x, selector_y))
	
	# Create number buttons 1-9 with responsive sizing
	for i in range(1, 10):
		var btn = Button.new()
		btn.text = str(i)
		btn.custom_minimum_size = Vector2(number_button_size, number_button_size)  # Back to original size
		var font_size = int(number_button_size * 0.3)  # Smaller font to fit in original buttons
		btn.add_theme_font_size_override("font_size", font_size)
		btn.pressed.connect(_on_number_selected.bind(i))
		_number_buttons[i] = btn  # Store reference for disabling when complete
		number_selector.add_child(btn)
	
	# SECTION 4: Fix border overlay scaling
	border_overlay = Control.new()
	border_overlay.position = grid_container.position  # Match grid_container position
	border_overlay.size = Vector2(grid_width, grid_width)  # Match grid size
	border_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Pass through clicks
	border_overlay.z_index = 100  # Draw on top of everything
	border_overlay.draw.connect(_draw_border_overlay)
	add_child(border_overlay)

func _draw_border_overlay():
	"""Draw thick borders for 3x3 subgrids on top of everything"""
	if not border_overlay:
		return
	
	# Use the dynamic spacing value
	var gap_size = spacing
	
	# Draw thick borders for 3x3 subgrids using computed values
	var step = cell_size * 3 + gap_size * 3  # 3 cells + 3 gaps
	var full_size = cell_size * 9 + gap_size * 8  # 9 cells + 8 gaps
	
	# Vertical lines (at x = step and x = step * 2)
	border_overlay.draw_rect(Rect2(step - 2, 0, 4, full_size), theme_colors["border"])
	border_overlay.draw_rect(Rect2(step * 2 - 2, 0, 4, full_size), theme_colors["border"])
	
	# Horizontal lines (at y = step and y = step * 2)
	border_overlay.draw_rect(Rect2(0, step - 2, full_size, 4), theme_colors["border"])
	border_overlay.draw_rect(Rect2(0, step * 2 - 2, full_size, 4), theme_colors["border"])

func set_game(sudoku_game: SudokuGame):
	game = sudoku_game
	if game:
		# Disconnect existing signals first to avoid reconnection errors
		if game.cell_filled.is_connected(_on_cell_filled):
			game.cell_filled.disconnect(_on_cell_filled)
		if game.puzzle_completed.is_connected(_on_puzzle_completed):
			game.puzzle_completed.disconnect(_on_puzzle_completed)
		if game.life_lost.is_connected(_on_life_lost):
			game.life_lost.disconnect(_on_life_lost)
		if game.game_over.is_connected(_on_game_over):
			game.game_over.disconnect(_on_game_over)
		
		# Now connect signals
		game.cell_filled.connect(_on_cell_filled)
		game.puzzle_completed.connect(_on_puzzle_completed)
		game.life_lost.connect(_on_life_lost)
		game.game_over.connect(_on_game_over)
		_update_hearts(game.lives)
		render()

func render():
	if not game:
		return

	# Reset all number buttons to enabled state for new game
	_reset_number_buttons()

	# Hide game over overlay if visible
	if game_over_overlay:
		game_over_overlay.visible = false

	# Hide win overlay if visible
	if win_overlay:
		win_overlay.visible = false

	# Reset hearts to full
	_update_hearts(3)
	
	# Clear existing buttons
	for child in grid_container.get_children():
		child.queue_free()
	grid_buttons.clear()
	
	# Create 9x9 grid of buttons
	for row in range(GRID_SIZE):
		var button_row = []
		for col in range(GRID_SIZE):
			var btn = _create_cell_button(row, col)
			grid_container.add_child(btn)
			button_row.append(btn)
		grid_buttons.append(button_row)
	
	# Redraw border overlay on top
	if border_overlay:
		border_overlay.queue_redraw()

func _create_cell_button(row: int, col: int) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(cell_size, cell_size)
	var font_size = int(cell_size * 0.6)
	btn.add_theme_font_size_override("font_size", font_size)
	
	var value = game.get_cell_value(row, col)
	if value != 0:
		btn.text = str(value)
	
	# Create stylebox with proper borders for 3x3 subgrids
	var stylebox = StyleBoxFlat.new()
	
	# Set background color and text color based on whether it's editable
	if not game.is_cell_editable(row, col):
		# Pre-filled cells - can be selected but not edited
		stylebox.bg_color = theme_colors.get("cell", Color(0.2, 0.2, 0.2))
		btn.add_theme_color_override("font_color", theme_colors.get("text", Color(1,1,1)))
		btn.pressed.connect(_on_cell_pressed.bind(Vector2i(row, col)))  # Allow selection
	else:
		# Editable cells - can be selected and edited
		stylebox.bg_color = theme_colors.get("cell", Color(0.2, 0.2, 0.2))
		btn.pressed.connect(_on_cell_pressed.bind(Vector2i(row, col)))
		btn.add_theme_color_override("font_color", theme_colors.get("user_text", Color(0.0, 0.0, 1.0)))
	
	# Add thicker borders for 3x3 subgrids (every 3rd row/column)
	# Normal borders: 1px, Subgrid borders: 4px
	stylebox.border_color = Color(0.0, 0.0, 0.0)  # Black border for strong contrast
	stylebox.draw_center = true  # Ensure background is drawn
	
	# Top border
	if row % 3 == 0:
		stylebox.border_width_top = 4  # Thick border at top of subgrid
	else:
		stylebox.border_width_top = 1  # Normal border
	
	# Left border
	if col % 3 == 0:
		stylebox.border_width_left = 4  # Thick border at left of subgrid
	else:
		stylebox.border_width_left = 1  # Normal border
	
	# Right border (thick at end of subgrid)
	if (col + 1) % 3 == 0 or col == GRID_SIZE - 1:
		stylebox.border_width_right = 4
	else:
		stylebox.border_width_right = 1
	
	# Bottom border (thick at end of subgrid)
	if (row + 1) % 3 == 0 or row == GRID_SIZE - 1:
		stylebox.border_width_bottom = 4
	else:
		stylebox.border_width_bottom = 1
	
	btn.add_theme_stylebox_override("normal", stylebox)
	btn.add_theme_stylebox_override("hover", stylebox)
	btn.add_theme_stylebox_override("pressed", stylebox)
	btn.add_theme_stylebox_override("disabled", stylebox)
	
	return btn

func _on_cell_pressed(pos: Vector2i):
	selected_cell = pos
	_highlight_selected_cell()
	_update_erase_button_state()

func _highlight_selected_cell():
	# Get the value of the selected cell (if any)
	var selected_value = 0
	if selected_cell != Vector2i(-1, -1):
		var selected_btn = grid_buttons[selected_cell.x][selected_cell.y]
		if selected_btn.text != "":
			selected_value = int(selected_btn.text)
	
	# Clear previous highlights and apply new ones
	for row_idx in range(grid_buttons.size()):
		for col_idx in range(grid_buttons[row_idx].size()):
			var btn = grid_buttons[row_idx][col_idx]
			if btn:
				var stylebox = StyleBoxFlat.new()
				
				# Determine background color based on highlighting rules
				var bg_color = theme_colors.get("cell", Color(0.2, 0.2, 0.2))
				
				# Check if this cell should be highlighted
				if selected_cell != Vector2i(-1, -1):
					# Highlight row and column (brighter highlight)
					if row_idx == selected_cell.x or col_idx == selected_cell.y:
						bg_color = theme_colors.get("highlight_row", Color(0, 0.1, 0.2, 0.5))
					
					# Highlight matching numbers (even darker highlight) - overrides row/column
					if selected_value > 0 and btn.text == str(selected_value):
						bg_color = theme_colors.get("highlight_match", Color(0.60, 0.70, 1.0))
				
				stylebox.bg_color = bg_color
				stylebox.border_color = Color(0.0, 0.0, 0.0)  # Black borders
				stylebox.draw_center = true
				
				# Re-apply border widths
				if row_idx % 3 == 0:
					stylebox.border_width_top = 4
				else:
					stylebox.border_width_top = 1
				
				if col_idx % 3 == 0:
					stylebox.border_width_left = 4
				else:
					stylebox.border_width_left = 1
				
				if (col_idx + 1) % 3 == 0 or col_idx == GRID_SIZE - 1:
					stylebox.border_width_right = 4
				else:
					stylebox.border_width_right = 1
				
				if (row_idx + 1) % 3 == 0 or row_idx == GRID_SIZE - 1:
					stylebox.border_width_bottom = 4
				else:
					stylebox.border_width_bottom = 1
				
				btn.add_theme_stylebox_override("normal", stylebox)
				btn.add_theme_stylebox_override("hover", stylebox)
				btn.add_theme_stylebox_override("pressed", stylebox)
	
	# Highlight selected cell with brightest blue (overrides all other highlights)
	if selected_cell != Vector2i(-1, -1):
		var btn = grid_buttons[selected_cell.x][selected_cell.y]
		var stylebox = StyleBoxFlat.new()
		stylebox.bg_color = theme_colors.get("selected", Color(0.7, 0.85, 1.0))
		stylebox.border_color = Color(0.0, 0.0, 0.0)
		stylebox.draw_center = true
		
		# Re-apply border widths for selected cell
		var row_idx = selected_cell.x
		var col_idx = selected_cell.y
		
		if row_idx % 3 == 0:
			stylebox.border_width_top = 4
		else:
			stylebox.border_width_top = 1
		
		if col_idx % 3 == 0:
			stylebox.border_width_left = 4
		else:
			stylebox.border_width_left = 1
		
		if (col_idx + 1) % 3 == 0 or col_idx == GRID_SIZE - 1:
			stylebox.border_width_right = 4
		else:
			stylebox.border_width_right = 1
		
		if (row_idx + 1) % 3 == 0 or row_idx == GRID_SIZE - 1:
			stylebox.border_width_bottom = 4
		else:
			stylebox.border_width_bottom = 1
		
		btn.add_theme_stylebox_override("normal", stylebox)
		btn.add_theme_stylebox_override("hover", stylebox)
		btn.add_theme_stylebox_override("pressed", stylebox)

func _on_number_selected(number: int):
	if selected_cell == Vector2i(-1, -1):
		return
	
	var row = selected_cell.x
	var col = selected_cell.y
	
	if game.is_cell_editable(row, col):
		game.set_cell(row, col, number)

func _on_erase_pressed():
	if selected_cell == Vector2i(-1, -1):
		return

	var row = selected_cell.x
	var col = selected_cell.y

	# Only erase if cell is editable and has incorrect value
	if game.is_cell_editable(row, col):
		var btn = grid_buttons[row][col]
		# Check if the cell has a value and it's incorrect (red text)
		if btn.text != "" and btn.get_theme_color("font_color") == Color(1.0, 0.0, 0.0):
			# Set the cell to 0 (which will trigger _on_cell_filled)
			game.set_cell(row, col, 0)

func reset_board() -> void:
	"""Reset all user entries and clear the saved game"""
	print("Resetting Sudoku board - clearing all user entries and save")

	# Clear all user-filled cells
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			if game.is_cell_editable(row, col) and game.get_cell_value(row, col) != 0:
				game.set_cell(row, col, 0)

	# Clear the saved game when board is reset
	PlayerData.clear_saved_game("Sudoku")

	# Deselect any selected cell
	selected_cell = Vector2i(-1, -1)
	_highlight_selected_cell()

func _update_erase_button_state():
	if not erase_button:
		return
	
	# Enable erase button only if selected cell has incorrect value
	if selected_cell == Vector2i(-1, -1):
		erase_button.disabled = true
		return
	
	var row = selected_cell.x
	var col = selected_cell.y
	
	# Check if cell is editable and has incorrect value (red text)
	if game.is_cell_editable(row, col):
		var btn = grid_buttons[row][col]
		# Enable if cell has text and it's red (incorrect)
		if btn.text != "" and btn.get_theme_color("font_color") == Color(1.0, 0.0, 0.0):
			erase_button.disabled = false
		else:
			erase_button.disabled = true
	else:
		erase_button.disabled = true

func _on_cell_filled(row: int, col: int, value: int, is_correct: bool):
	# Update button text
	var btn = grid_buttons[row][col]
	
	# If value is 0, clear the cell visually (erase action)
	if value == 0:
		btn.text = ""
		# No sound for erasing
	else:
		btn.text = str(value)
		
		# Set text color based on correctness and theme
		if is_correct:
			btn.add_theme_color_override("font_color", theme_colors.get("user_text", Color(0.0, 0.0, 0.0)))  # Use theme color for correct entries
			# Play place sound for correct entries
			if SoundManager:
				SoundManager.play_place()
		else:
			btn.add_theme_color_override("font_color", Color(1.0, 0.0, 0.0))  # Red for incorrect (always red)
			# Play incorrect sound for wrong entries
			if SoundManager:
				SoundManager.play_incorrect()
	
	# Update erase button state after filling a cell
	_update_erase_button_state()

	# Check for line, column, and section completions when correct entry is made
	if is_correct and value != 0:
		print("Checking for completions at (", row, ",", col, ")")
		_check_for_completions(row, col)
		# Check if all 9 instances of this number are now correctly placed
		_check_and_disable_number(value)

	# Keep gray background consistent with other cells
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(0.85, 0.85, 0.85)  # Gray background (same as all cells)
	
	# Preserve borders
	stylebox.border_color = Color(0.0, 0.0, 0.0)
	stylebox.draw_center = true
	
	# Re-apply border widths based on position
	if row % 3 == 0:
		stylebox.border_width_top = 4
	else:
		stylebox.border_width_top = 1
	
	if col % 3 == 0:
		stylebox.border_width_left = 4
	else:
		stylebox.border_width_left = 1
	
	if (col + 1) % 3 == 0 or col == GRID_SIZE - 1:
		stylebox.border_width_right = 4
	else:
		stylebox.border_width_right = 1
	
	if (row + 1) % 3 == 0 or row == GRID_SIZE - 1:
		stylebox.border_width_bottom = 4
	else:
		stylebox.border_width_bottom = 1
	
	btn.add_theme_stylebox_override("normal", stylebox)
	btn.add_theme_stylebox_override("hover", stylebox)
	btn.add_theme_stylebox_override("pressed", stylebox)

func update_theme() -> void:
	"""Update theme colors and refresh display"""
	_init_theme_colors()
	_update_all_cell_colors()  # Update text colors for all cells
	_highlight_selected_cell()

func _update_all_cell_colors() -> void:
	"""Update text colors for all existing cell buttons when theme changes"""
	for row_idx in range(grid_buttons.size()):
		for col_idx in range(grid_buttons[row_idx].size()):
			var btn = grid_buttons[row_idx][col_idx]
			if btn and game:
				# Update text color based on whether cell is editable
				if not game.is_cell_editable(row_idx, col_idx):
					# Pre-filled cells
					btn.add_theme_color_override("font_color", theme_colors.get("text", Color(1,1,1)))
				else:
					# User input cells
					btn.add_theme_color_override("font_color", theme_colors.get("user_text", Color(0.0, 0.0, 1.0)))

func _on_life_lost(remaining_lives: int):
	"""Update hearts display when a life is lost"""
	_update_hearts(remaining_lives)

func _update_hearts(lives_remaining: int):
	"""Update heart icons based on remaining lives"""
	print("Updating hearts - lives remaining: ", lives_remaining)
	for i in range(heart_icons.size()):
		var heart_icon = heart_icons[i]
		
		if i < lives_remaining:
			# Alive - red heart
			heart_icon.modulate = Color(1.0, 0.0, 0.0)  # Red
			print("Heart ", i + 1, " set to alive (red)")
		else:
			# Lost - gray heart
			heart_icon.modulate = Color(0.5, 0.5, 0.5)  # Gray
			print("Heart ", i + 1, " set to lost (gray)")

func _on_game_over():
	"""Handle game over - disable input and show overlay"""
	print("Sudoku game over - no lives remaining!")
	
	# Notify multiplayer if in multiplayer mode
	if MultiplayerGameManager and MultiplayerGameManager.is_multiplayer:
		print("Notifying multiplayer that player lost all lives")
		MultiplayerGameManager.forfeit_player()
	
	# Show game over overlay
	if game_over_overlay:
		game_over_overlay.visible = true
	
	# Disable all grid buttons
	for row in grid_buttons:
		for btn in row:
			if btn and not btn.disabled:
				btn.disabled = true

func _on_puzzle_completed():
	print("Sudoku puzzle completed!")
	
	# Show win overlay with Matrix shader effect
	if win_overlay:
		win_overlay.visible = true
	
	# Disable all grid buttons
	for row in grid_buttons:
		for btn in row:
			if btn and not btn.disabled:
				btn.disabled = true
	
	game_completed.emit()

func _check_for_completions(row: int, col: int) -> void:
	"""Check if the cell at (row, col) completes a line, column, or 3x3 section"""
	var completed_cells: Array[Vector2i] = []

	# Check row completion
	if _is_row_complete(row):
		print("Row ", row, " completed!")
		for c in range(GRID_SIZE):
			completed_cells.append(Vector2i(row, c))
		_animate_completion(completed_cells)
		return

	# Check column completion
	if _is_column_complete(col):
		print("Column ", col, " completed!")
		for r in range(GRID_SIZE):
			completed_cells.append(Vector2i(r, col))
		_animate_completion(completed_cells)
		return

	# Check 3x3 section completion
	var section_row = (row / 3) * 3
	var section_col = (col / 3) * 3
	if _is_section_complete(section_row, section_col):
		print("Section (", section_row, ",", section_col, ") completed!")
		for r in range(section_row, section_row + 3):
			for c in range(section_col, section_col + 3):
				completed_cells.append(Vector2i(r, c))
		_animate_completion(completed_cells)

func _is_row_complete(row: int) -> bool:
	"""Check if a row has all cells filled with correct values"""
	for col in range(GRID_SIZE):
		if game.get_cell_value(row, col) != game.get_solution_value(row, col):
			return false
	return true

func _is_column_complete(col: int) -> bool:
	"""Check if a column has all cells filled with correct values"""
	for row in range(GRID_SIZE):
		if game.get_cell_value(row, col) != game.get_solution_value(row, col):
			return false
	return true

func _is_section_complete(start_row: int, start_col: int) -> bool:
	"""Check if a 3x3 section has all cells filled with correct values"""
	for r in range(start_row, start_row + 3):
		for c in range(start_col, start_col + 3):
			if game.get_cell_value(r, c) != game.get_solution_value(r, c):
				return false
	return true

func _check_and_disable_number(value: int) -> void:
	"""Check if all 9 of a number are correctly placed and disable its button if so"""
	var count = 0
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			if game.get_cell_value(row, col) == value and game.get_solution_value(row, col) == value:
				count += 1
	if count == 9:
		var btn = _number_buttons.get(value)
		if btn and is_instance_valid(btn):
			btn.disabled = true
			print("Number ", value, " complete - button disabled")

func _reset_number_buttons() -> void:
	"""Re-enable all number selector buttons for a new game"""
	for btn in _number_buttons.values():
		if is_instance_valid(btn):
			btn.disabled = false

func _animate_completion(cells: Array[Vector2i]) -> void:
	"""Animate stars appearing and fading for completed cells"""
	print("Animating completion for ", cells.size(), " cells")
	# Play foundation sound for completion
	if SoundManager:
		SoundManager.play_foundation()

	# First, create all stars and store them with their tweens
	var stars_and_tweens: Array = []

	for cell_pos in cells:
		var row = cell_pos.x
		var col = cell_pos.y
		var btn = grid_buttons[row][col]
		if not btn:
			continue

		# Create star label
		var star = Label.new()
		star.text = "★"
		star.add_theme_font_size_override("font_size", int(cell_size * 0.8))
		star.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))  # Yellow/white color
		star.set_anchors_preset(Control.PRESET_CENTER)
		btn.add_child(star)
		print("Star created and added to button at (", row, ",", col, ")")

		# Create tween for star
		var tween = star.create_tween()
		tween.set_parallel(true)  # Run animations in parallel
		tween.tween_property(star, "position:y", -cell_size * 0.5, 0.3)  # Move up quickly
		tween.tween_property(star, "modulate:a", 0.0, 0.3)  # Fade out quickly

		stars_and_tweens.append({"star": star, "tween": tween})

	# Now wait for all tweens to finish and clean up
	for item in stars_and_tweens:
		await item.tween.finished
		item.star.queue_free()
