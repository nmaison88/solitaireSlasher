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

const GRID_SIZE = 9
const CELL_SIZE = 80  # Sized for 1366px viewport
const NUMBER_BUTTON_SIZE = 80

signal game_completed

func _ready():
	print("=== SudokuBoard._ready() called ===")
	_create_ui()

func _create_ui():
	print("=== SudokuBoard._create_ui() called ===")
	# Hearts container (lives) - positioned above the Sudoku grid
	# Grid is at y=320, so hearts at y=220 with 100px height leaves padding
	hearts_container = HBoxContainer.new()
	hearts_container.position = Vector2(0, 220)  # Above grid at y=320
	hearts_container.custom_minimum_size = Vector2(0, 90)  # Height for hearts
	hearts_container.add_theme_constant_override("separation", 20)
	hearts_container.alignment = BoxContainer.ALIGNMENT_CENTER  # Center horizontally
	
	# Use anchors to center horizontally across screen width
	hearts_container.anchor_left = 0.0
	hearts_container.anchor_right = 1.0
	hearts_container.offset_left = 0
	hearts_container.offset_right = 0
	
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
	# Grid starts at y=320 (below hearts and top buttons)
	grid_container = GridContainer.new()
	grid_container.columns = GRID_SIZE
	grid_container.position = Vector2(144, 320)  # Centered horizontally, below hearts
	grid_container.add_theme_constant_override("h_separation", 2)
	grid_container.add_theme_constant_override("v_separation", 2)
	add_child(grid_container)
	
	# Erase button (above number selector)
	# Position at y=1140 (above number selector at y=1240)
	erase_button = Button.new()
	erase_button.custom_minimum_size = Vector2(100, 80)
	erase_button.position = Vector2(462, 1140)  # Centered: (1024 - 100) / 2 = 462
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
	
	# Number selector at bottom
	# Grid ends at: 320 + 736 = 1056
	# Undo button area: y=1050, height=180, ends at y=1230
	# Number selector: 9 buttons * 80px + 8 gaps * 8px = 720 + 64 = 784px width
	# Center: (1024 - 784) / 2 = 120px
	# Position at y=1240 (below undo button area)
	number_selector = GridContainer.new()
	number_selector.columns = 9
	number_selector.position = Vector2(120, 1240)  # Bottom of 1366px viewport
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
	border_overlay.position = Vector2(144, 320)  # Match grid_container position
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
	btn.add_theme_font_size_override("font_size", 48)  # Font size for 80px cells
	
	var value = game.get_cell_value(row, col)
	if value != 0:
		btn.text = str(value)
	
	# Create stylebox with proper borders for 3x3 subgrids
	var stylebox = StyleBoxFlat.new()
	
	# Set background color and text color based on whether it's editable
	if not game.is_cell_editable(row, col):
		# Pre-filled cells - can be selected but not edited
		stylebox.bg_color = Color(0.75, 0.80, 0.90)  # Light blue-gray
		btn.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0))  # Black text
		btn.pressed.connect(_on_cell_pressed.bind(Vector2i(row, col)))  # Allow selection
	else:
		# Editable cells - can be selected and edited
		stylebox.bg_color = Color(0.75, 0.80, 0.90)  # Light blue-gray
		btn.pressed.connect(_on_cell_pressed.bind(Vector2i(row, col)))
		btn.add_theme_color_override("font_color", Color(0.0, 0.0, 1.0))  # Blue text for user input
	
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
				var bg_color = Color(0.75, 0.80, 0.90)  # Default light blue-gray
				
				# Check if this cell should be highlighted
				if selected_cell != Vector2i(-1, -1):
					# Highlight row and column (brighter highlight)
					if row_idx == selected_cell.x or col_idx == selected_cell.y:
						bg_color = Color(0.85, 0.90, 1.0)  # Bright blue for row/column
					
					# Highlight matching numbers (even darker highlight) - overrides row/column
					if selected_value > 0 and btn.text == str(selected_value):
						bg_color = Color(0.60, 0.70, 1.0)  # Darker blue for matching numbers
				
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
		
		# Set text color based on correctness
		if is_correct:
			btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))  # White for correct
			# Play place sound for correct entries
			if SoundManager:
				SoundManager.play_place()
		else:
			btn.add_theme_color_override("font_color", Color(1.0, 0.0, 0.0))  # Red for incorrect
			# Play incorrect sound for wrong entries
			if SoundManager:
				SoundManager.play_incorrect()
	
	# Update erase button state after filling a cell
	_update_erase_button_state()
	
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
