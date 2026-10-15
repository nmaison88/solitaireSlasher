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
var border_overlay: Control  # Overlay for 3x3 subgrid borders
var erase_button: Button  # Erase button for incorrect values
var _number_buttons: Dictionary = {}  # number (1-9) -> Button reference
var _result_overlay: Control = null  # Win/lose result screen

# Theme colors
var theme_colors: Dictionary = {}

const GRID_SIZE = 9
const WastelandStyle = preload("res://scripts/WastelandStyle.gd")
const ERROR_TEXT := Color(1.0, 0.3, 0.25)  # Incorrect entries; also how erase-ability is detected
const HEART_ALIVE := Color(0.9, 0.18, 0.14)
const HEART_LOST := Color(0.35, 0.33, 0.3, 0.6)
var cell_size: float  # Dynamic cell size calculated based on screen
var number_button_size: float  # Dynamic button size
var spacing: int = 2  # Grid spacing

signal game_completed
signal play_again_requested
signal main_menu_requested

func _init_theme_colors() -> void:
	"""Initialize theme colors based on player settings"""
	var theme_mode = PlayerData.get_theme()
	
	if theme_mode == "light":
		theme_colors = {
			"cell": Color(0.75, 0.80, 0.90),  # Light blue-gray
			"text": Color(0.0, 0.0, 0.0),  # Black text
			"user_text": Color(0.05, 0.35, 0.05),  # Dark green for user input
			"highlight_row": Color(0.85, 0.90, 1.0),  # Bright blue
			"highlight_match": Color(0.60, 0.70, 1.0),  # Darker blue
			"selected": Color(0.7, 0.85, 1.0),  # Light blue highlight
			"grid_line": Color(0.0, 0.0, 0.0, 0.6),
			"border": Color(0.0, 0.0, 0.0)  # Black borders for 3x3 subgrids
		}
	else:  # dark mode: slate cells, bone givens, toxic-green entries
		var accent = WastelandStyle.accent_for("Sudoku")
		theme_colors = {
			"cell": Color(0.09, 0.09, 0.075, 0.92),
			"text": WastelandStyle.BONE,
			"user_text": accent,
			"highlight_row": Color(0.14, 0.17, 0.11, 0.95),
			"highlight_match": Color(0.2, 0.3, 0.14, 0.95),
			"selected": Color(0.28, 0.46, 0.17),
			"grid_line": Color(0.0, 0.0, 0.0, 0.7),
			"border": Color(WastelandStyle.BONE, 0.45)  # 3x3 subgrid lines
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
	var board_size = min(screen_width - 48.0, screen_height * 0.6)  # Margin leaves room for the glowing frame
	
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
		heart_icon.modulate = HEART_ALIVE
		heart_icon.custom_minimum_size = Vector2(80, 80)
		heart_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		hearts_container.add_child(heart_icon)
		heart_icons.append(heart_icon)
		
		print("Heart ", i + 1, " created as red FontAwesome icon (no background)")
	
	# Ensure hearts container is visible
	hearts_container.z_index = 10
	hearts_container.visible = true
	print("Hearts container created at position: ", hearts_container.position)
	
	
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

	# Glowing frame behind the grid
	var frame_style = StyleBoxFlat.new()
	frame_style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	frame_style.set_border_width_all(4)
	frame_style.border_color = WastelandStyle.accent_for("Sudoku")
	frame_style.set_corner_radius_all(10)
	frame_style.shadow_color = Color(WastelandStyle.accent_for("Sudoku"), 0.35)
	frame_style.shadow_size = 22
	var frame = Panel.new()
	frame.name = "GridFrame"
	frame.position = grid_container.position - Vector2(8, 8)
	frame.size = Vector2(grid_width, grid_width) + Vector2(16, 16)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", frame_style)
	add_child(frame)
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
	_style_metal_key(erase_button, 40)
	
	# Add FontAwesome eraser icon
	var erase_icon = FontAwesome.new()
	erase_icon.icon_name = "eraser"
	erase_icon.icon_type = "solid"
	erase_icon.icon_size = 44
	erase_icon.add_theme_color_override("font_color", WastelandStyle.BONE)
	erase_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
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
		_style_metal_key(btn, 14)
		btn.add_theme_font_size_override("font_size", int(number_button_size * 0.55))
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

	# Clear any result screen overlay
	_clear_result_overlay()

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
	btn.add_theme_font_override("font", WastelandStyle.font())
	btn.add_theme_font_size_override("font_size", int(cell_size * 0.62))
	
	var value = game.get_cell_value(row, col)
	if value != 0:
		btn.text = str(value)
	
	# Givens and user entries use different text colors; both can be selected
	var text_key = "user_text" if game.is_cell_editable(row, col) else "text"
	btn.add_theme_color_override("font_color", theme_colors.get(text_key, Color(1, 1, 1)))
	btn.add_theme_color_override("font_disabled_color", theme_colors.get(text_key, Color(1, 1, 1)))
	btn.pressed.connect(_on_cell_pressed.bind(Vector2i(row, col)))
	_apply_cell_style(btn, row, col, theme_colors.get("cell", Color(0.2, 0.2, 0.2)))
	return btn

func _apply_cell_style(btn: Button, row: int, col: int, bg_color: Color) -> void:
	"""Cell background with thin grid lines, thicker on 3x3 subgrid edges"""
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = bg_color
	stylebox.border_color = theme_colors.get("grid_line", Color(0, 0, 0))
	stylebox.border_width_top = 4 if row % 3 == 0 else 1
	stylebox.border_width_left = 4 if col % 3 == 0 else 1
	stylebox.border_width_right = 4 if (col + 1) % 3 == 0 else 1
	stylebox.border_width_bottom = 4 if (row + 1) % 3 == 0 else 1
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, stylebox)

func _style_metal_key(btn: Button, corner_radius: int) -> void:
	"""Dark metal key for the number pad and erase button"""
	var normal = StyleBoxFlat.new()
	normal.bg_color = WastelandStyle.METAL
	normal.set_border_width_all(2)
	normal.border_color = Color(WastelandStyle.BONE, 0.3)
	normal.set_corner_radius_all(corner_radius)
	var pressed = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = WastelandStyle.METAL_DARK
	pressed.border_color = WastelandStyle.accent_for("Sudoku")
	var disabled = normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(WastelandStyle.METAL, 0.35)
	disabled.border_color = Color(WastelandStyle.BONE, 0.1)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", normal)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("hover_pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_font_override("font", WastelandStyle.font())
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		btn.add_theme_color_override(state, WastelandStyle.BONE)
	btn.add_theme_color_override("font_pressed_color", WastelandStyle.accent_for("Sudoku"))
	btn.add_theme_color_override("font_hover_pressed_color", WastelandStyle.accent_for("Sudoku"))
	btn.add_theme_color_override("font_disabled_color", Color(WastelandStyle.BONE, 0.2))

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
	
	for row_idx in range(grid_buttons.size()):
		for col_idx in range(grid_buttons[row_idx].size()):
			var btn = grid_buttons[row_idx][col_idx]
			if not btn:
				continue
			var bg_color = theme_colors.get("cell", Color(0.2, 0.2, 0.2))
			if selected_cell != Vector2i(-1, -1):
				# Row and column of the selection
				if row_idx == selected_cell.x or col_idx == selected_cell.y:
					bg_color = theme_colors.get("highlight_row", bg_color)
				# Matching numbers override row/column
				if selected_value > 0 and btn.text == str(selected_value):
					bg_color = theme_colors.get("highlight_match", bg_color)
				# The selected cell itself overrides everything
				if Vector2i(row_idx, col_idx) == selected_cell:
					bg_color = theme_colors.get("selected", bg_color)
			_apply_cell_style(btn, row_idx, col_idx, bg_color)

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
		if btn.text != "" and btn.get_theme_color("font_color") == ERROR_TEXT:
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
		if btn.text != "" and btn.get_theme_color("font_color") == ERROR_TEXT:
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
			# Use theme color for correct entries
			btn.add_theme_color_override("font_color", theme_colors.get("user_text", Color(0.0, 0.0, 0.0)))
			btn.add_theme_color_override("font_disabled_color", theme_colors.get("user_text", Color(0.0, 0.0, 0.0)))
			# Play place sound for correct entries
			if SoundManager:
				SoundManager.play_place()
		else:
			# Incorrect entries are always red
			btn.add_theme_color_override("font_color", ERROR_TEXT)
			btn.add_theme_color_override("font_disabled_color", ERROR_TEXT)
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

	# Refresh highlights (the filled number may now match the selection)
	_highlight_selected_cell()

func update_theme() -> void:
	"""Update theme colors and refresh display"""
	_init_theme_colors()
	_update_all_cell_colors()  # Update text colors for all cells
	_highlight_selected_cell()
	if border_overlay:
		border_overlay.queue_redraw()

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
			heart_icon.modulate = HEART_ALIVE
			print("Heart ", i + 1, " set to alive (red)")
		else:
			# Lost - gray heart
			heart_icon.modulate = HEART_LOST
			print("Heart ", i + 1, " set to lost (gray)")

func _on_game_over():
	"""Handle game over - disable input and show result screen"""
	print("Sudoku game over - no lives remaining!")

	# Notify multiplayer if in multiplayer mode
	if MultiplayerGameManager and MultiplayerGameManager.is_multiplayer:
		print("Notifying multiplayer that player lost all lives")
		MultiplayerGameManager.forfeit_player()

	# Show result screen
	_show_result_screen(false)

	# Disable all grid buttons
	for row in grid_buttons:
		for btn in row:
			if btn and not btn.disabled:
				btn.disabled = true

func _on_puzzle_completed():
	print("Sudoku puzzle completed!")

	# Show result screen
	_show_result_screen(true)

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

func _format_time(seconds: float) -> String:
	"""Format elapsed time as MM:SS"""
	var m = int(seconds) / 60
	var s = int(seconds) % 60
	return "%d:%02d" % [m, s]

func _clear_result_overlay() -> void:
	"""Clean up result screen overlay"""
	if is_instance_valid(_result_overlay):
		_result_overlay.visible = false  # Hide immediately
		_result_overlay.queue_free()
	_result_overlay = null

func _show_result_screen(won: bool) -> void:
	"""Result screen: title, difficulty/time, remaining hearts, play again / main menu"""
	if is_instance_valid(_result_overlay):
		return  # Already showing

	var accent = WastelandStyle.accent_for("Sudoku") if won else HEART_ALIVE

	# Full-screen dimming overlay
	var overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 3000  # Stay under the 4096 z cap
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_overlay = overlay
	add_child(overlay)

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.04, 0.02, 0.88)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)

	var box = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 24)
	overlay.add_child(box)

	var title = WastelandStyle.title("PUZZLE COMPLETE" if won else "GAME OVER", 76)
	title.add_theme_color_override("font_color", accent.lightened(0.15))
	box.add_child(title)

	var difficulty_map = {1: "EASY", 3: "MEDIUM", 5: "HARD"}
	var stats = "%s  ·  %s" % [difficulty_map.get(game.difficulty, "?"), _format_time(game.get_game_time())]
	box.add_child(WastelandStyle.label(stats, 34, WastelandStyle.BONE_MUTED, 3))

	# Remaining lives
	var lives_row = HBoxContainer.new()
	lives_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lives_row.add_theme_constant_override("separation", 16)
	box.add_child(lives_row)
	for i in range(game.max_lives):
		var heart = FontAwesome.new()
		heart.icon_name = "heart"
		heart.icon_type = "solid"
		heart.icon_size = 48
		heart.modulate = HEART_ALIVE if i < game.lives else HEART_LOST
		heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lives_row.add_child(heart)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	box.add_child(spacer)

	var play_btn = WastelandStyle.make_button("PLAY AGAIN", accent, true, Vector2(440, 112), 44)
	play_btn.pressed.connect(_on_result_play_again)
	box.add_child(play_btn)

	var menu_btn = WastelandStyle.make_button("MAIN MENU", accent, false, Vector2(440, 104), 38)
	menu_btn.pressed.connect(_on_result_main_menu)
	box.add_child(menu_btn)

	# Animate: fade in + bounce title
	overlay.modulate.a = 0.0
	var fade = create_tween()
	fade.tween_property(overlay, "modulate:a", 1.0, 0.4)

	await get_tree().process_frame
	title.pivot_offset = title.size * 0.5
	title.scale = Vector2(0.3, 0.3)
	var bounce = title.create_tween()
	bounce.set_ease(Tween.EASE_OUT)
	bounce.set_trans(Tween.TRANS_BACK)
	bounce.tween_property(title, "scale", Vector2(1.0, 1.0), 0.55)

func _on_result_play_again() -> void:
	"""Handle 'Play Again' button press"""
	_clear_result_overlay()
	play_again_requested.emit()

func _on_result_main_menu() -> void:
	"""Handle 'Main Menu' button press"""
	_clear_result_overlay()
	visible = false  # Hide the entire board immediately
	main_menu_requested.emit()
