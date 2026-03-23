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
var border_overlay: Control  # Overlay for 3x3 subgrid borders

const GRID_SIZE = 9
const CELL_SIZE = 80  # Reduced from 100 to fit better
const NUMBER_BUTTON_SIZE = 80

signal game_completed

func _ready():
	_create_ui()

func _create_ui():
	# Hearts container (lives) at top
	# Board: 9 cells * 80px + 8 gaps * 2px = 736px width, starts at x=144
	# Center hearts over board: 144 + (736 / 2) - (hearts_width / 2)
	# 3 hearts * 80px + 2 gaps * 20px = 240 + 40 = 280px total width
	# Center: 144 + 368 - 140 = 372
	# Board starts at y=320, hearts at y=220 gives 100px padding
	hearts_container = HBoxContainer.new()
	hearts_container.position = Vector2(372, 220)  # Centered with board, with padding below
	hearts_container.add_theme_constant_override("separation", 20)  # Increased spacing
	add_child(hearts_container)
	
	# Create 3 heart icons (larger)
	for i in range(3):
		var heart_label = Label.new()
		heart_label.text = "❤"  # Heart emoji
		heart_label.add_theme_font_size_override("font_size", 80)  # Increased from 48 to 80
		heart_label.modulate = Color(1.0, 0.0, 0.0)  # Red color
		hearts_container.add_child(heart_label)
		heart_icons.append(heart_label)
	
	# Create game over overlay (hidden by default)
	game_over_overlay = Panel.new()
	game_over_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over_overlay.visible = false
	add_child(game_over_overlay)
	
	# Semi-transparent dark background
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(0.0, 0.0, 0.0, 0.7)  # Black with 70% opacity
	game_over_overlay.add_theme_stylebox_override("panel", stylebox)
	
	# "YOU LOST!" text in center
	var lost_label = Label.new()
	lost_label.text = "YOU LOST!"
	lost_label.add_theme_font_size_override("font_size", 96)
	lost_label.add_theme_color_override("font_color", Color(1.0, 0.0, 0.0))  # Red text
	lost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lost_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over_overlay.add_child(lost_label)
	
	# Main grid container for the 9x9 Sudoku grid
	# Board: 9 cells * 80px + 8 gaps * 2px = 720 + 16 = 736px width
	# Screen width: 1024px, center: (1024 - 736) / 2 = 144px
	# Board height: 9 cells * 80px + 8 gaps * 2px = 736px
	grid_container = GridContainer.new()
	grid_container.columns = GRID_SIZE
	grid_container.position = Vector2(144, 320)  # Centered horizontally, below top buttons
	grid_container.add_theme_constant_override("h_separation", 2)
	grid_container.add_theme_constant_override("v_separation", 2)
	add_child(grid_container)
	
	# Number selector at bottom (below undo button area)
	# Undo button is at y=1050, height=180, ends at y=1230
	# Number selector: 9 buttons * 80px + 8 gaps * 8px = 720 + 64 = 784px width
	number_selector = GridContainer.new()
	number_selector.columns = 9
	number_selector.position = Vector2(120, 1240)  # Below undo button, centered
	number_selector.add_theme_constant_override("h_separation", 8)
	add_child(number_selector)
	
	# Create number buttons 1-9
	for i in range(1, 10):
		var btn = Button.new()
		btn.text = str(i)
		btn.custom_minimum_size = Vector2(NUMBER_BUTTON_SIZE, NUMBER_BUTTON_SIZE)
		btn.add_theme_font_size_override("font_size", 48)
		btn.pressed.connect(_on_number_selected.bind(i))
		number_selector.add_child(btn)
	
	# Create border overlay for 3x3 subgrids (drawn on top of everything)
	border_overlay = Control.new()
	border_overlay.position = Vector2(152, 320)  # Same as grid_container
	border_overlay.size = Vector2(CELL_SIZE * 9 + 16, CELL_SIZE * 9 + 16)  # 9 cells + gaps
	border_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Pass through clicks
	border_overlay.z_index = 100  # Draw on top of everything
	border_overlay.draw.connect(_draw_border_overlay)
	add_child(border_overlay)

func _draw_border_overlay():
	"""Draw thick borders for 3x3 subgrids on top of everything"""
	if not border_overlay:
		return
	
	var border_color = Color(0.0, 0.0, 0.0)  # Black borders
	var thick_width = 4.0
	
	# Draw vertical lines (every 3 columns)
	for i in range(4):  # 0, 1, 2, 3 (4 vertical lines for 3 sections)
		var x = i * (CELL_SIZE * 3 + 6)  # 3 cells + 3 gaps of 2px
		border_overlay.draw_line(
			Vector2(x, 0),
			Vector2(x, CELL_SIZE * 9 + 16),
			border_color,
			thick_width
		)
	
	# Draw horizontal lines (every 3 rows)
	for i in range(4):  # 0, 1, 2, 3 (4 horizontal lines for 3 sections)
		var y = i * (CELL_SIZE * 3 + 6)  # 3 cells + 3 gaps of 2px
		border_overlay.draw_line(
			Vector2(0, y),
			Vector2(CELL_SIZE * 9 + 16, y),
			border_color,
			thick_width
		)

func set_game(sudoku_game: SudokuGame):
	game = sudoku_game
	if game:
		game.cell_filled.connect(_on_cell_filled)
		game.puzzle_completed.connect(_on_puzzle_completed)
		game.life_lost.connect(_on_life_lost)
		game.game_over.connect(_on_game_over)
		_update_hearts(game.lives)

func render():
	if not game:
		return
	
	# Hide game over overlay if visible
	if game_over_overlay:
		game_over_overlay.visible = false
	
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
	btn.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	btn.add_theme_font_size_override("font_size", 48)
	
	var value = game.get_cell_value(row, col)
	if value != 0:
		btn.text = str(value)
	
	# Create stylebox with proper borders for 3x3 subgrids
	var stylebox = StyleBoxFlat.new()
	
	# Set background color based on whether it's editable
	if not game.is_cell_editable(row, col):
		# Pre-filled cells - light gray background
		stylebox.bg_color = Color(0.85, 0.85, 0.85)
		btn.disabled = true
	else:
		# Editable cells - transparent background (blue shows through)
		stylebox.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		btn.pressed.connect(_on_cell_pressed.bind(Vector2i(row, col)))
	
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
	
	return btn

func _on_cell_pressed(pos: Vector2i):
	selected_cell = pos
	_highlight_selected_cell()

func _highlight_selected_cell():
	# Clear previous highlights - restore white background for editable cells
	for row_idx in range(grid_buttons.size()):
		for col_idx in range(grid_buttons[row_idx].size()):
			var btn = grid_buttons[row_idx][col_idx]
			if btn and not btn.disabled:
				var stylebox = StyleBoxFlat.new()
				stylebox.bg_color = Color(0.0, 0.0, 0.0, 0.0)  # Transparent background
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
	
	# Highlight selected cell with light blue
	if selected_cell != Vector2i(-1, -1):
		var btn = grid_buttons[selected_cell.x][selected_cell.y]
		var stylebox = StyleBoxFlat.new()
		stylebox.bg_color = Color(0.7, 0.85, 1.0)  # Light blue highlight
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

func _on_number_selected(number: int):
	if selected_cell == Vector2i(-1, -1):
		return
	
	var row = selected_cell.x
	var col = selected_cell.y
	
	if game.is_cell_editable(row, col):
		game.set_cell(row, col, number)

func _on_cell_filled(row: int, col: int, value: int, is_correct: bool):
	# Update button text
	var btn = grid_buttons[row][col]
	btn.text = str(value)
	
	# Set text color based on correctness
	if is_correct:
		btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))  # White for correct
	else:
		btn.add_theme_color_override("font_color", Color(1.0, 0.0, 0.0))  # Red for incorrect
	
	# Keep transparent background, no hint backgrounds needed
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(0.0, 0.0, 0.0, 0.0)  # Transparent background
	
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

func _on_life_lost(remaining_lives: int):
	"""Update hearts display when a life is lost"""
	_update_hearts(remaining_lives)

func _update_hearts(lives_remaining: int):
	"""Update heart icons based on remaining lives"""
	for i in range(heart_icons.size()):
		if i < lives_remaining:
			heart_icons[i].modulate = Color(1.0, 0.0, 0.0)  # Red (alive)
		else:
			heart_icons[i].modulate = Color(0.5, 0.5, 0.5)  # Gray (lost)

func _on_game_over():
	"""Handle game over - disable input and show overlay"""
	print("Sudoku game over - no lives remaining!")
	
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
	game_completed.emit()
