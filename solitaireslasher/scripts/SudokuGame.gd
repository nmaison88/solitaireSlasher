extends Node
class_name SudokuGame

# Game Grid
var puzzle = [] # Holds the puzzle (with some cells empty)
var solution_grid = [] # Holds the complete solution
var player_grid = [] # Holds the player's current answers
var solution_count = 0 # Used for validating unique solutions

const GRID_SIZE = 9

# Difficulty settings
var difficulty: int = 3  # 1=Easy, 3=Medium, 5=Hard
var show_hints: bool = true

# Lives system
var lives: int = 3
var max_lives: int = 3

# Game time tracking
var _start_time: float = 0.0  # Time when game started (in seconds)

signal puzzle_completed
signal cell_filled(row: int, col: int, value: int, is_correct: bool)
signal life_lost(remaining_lives: int)
signal game_over

func _init():
	pass

func new_game(diff: int = 3, hints: bool = true, mirror_data: Dictionary = {}):
	"""Start a new Sudoku game with given difficulty"""
	difficulty = diff
	show_hints = hints
	lives = max_lives  # Reset lives to 3
	_start_time = Time.get_ticks_msec() / 1000.0  # Start timer
	_create_empty_grid()
	_fill_grid(solution_grid)

	# Check if mirror mode is enabled and we have mirror data
	if not mirror_data.is_empty():
		print("DEBUG: Sudoku new_game received mirror data with keys: ", mirror_data.keys())
		if mirror_data.has("puzzle"):
			# Load puzzle from mirror data
			puzzle = mirror_data["puzzle"].duplicate(true)
			print("Sudoku: Using mirror mode puzzle from host")
		else:
			print("DEBUG: Mirror data missing puzzle key, generating new puzzle")
			# Normal puzzle generation
			_create_puzzle(difficulty)
			print("Sudoku: Generated new puzzle (fallback)")
	else:
		# Normal puzzle generation
		_create_puzzle(difficulty)
		print("Sudoku: Generated new puzzle")

	_init_player_grid()
	print("Sudoku game created with difficulty: ", difficulty, " with ", lives, " lives")

func _init_player_grid():
	"""Initialize player grid with puzzle values"""
	player_grid = []
	for i in range(GRID_SIZE):
		var row = []
		for j in range(GRID_SIZE):
			row.append(puzzle[i][j])
		player_grid.append(row)

func set_cell(row: int, col: int, value: int) -> bool:
	"""Set a cell value and check if it's correct"""
	if puzzle[row][col] != 0:
		return false  # Can't change pre-filled cells

	if lives <= 0:
		return false  # Game over, no more moves allowed

	player_grid[row][col] = value

	# Special case: value=0 means erasing, don't check correctness or lose lives
	if value == 0:
		cell_filled.emit(row, col, value, true)  # Emit as "correct" to avoid red text
		return true

	var is_correct = (value == solution_grid[row][col])

	# Lose a life if incorrect
	if not is_correct:
		lives -= 1
		life_lost.emit(lives)
		print("Incorrect move! Lives remaining: ", lives)

		if lives <= 0:
			print("Game Over! No lives remaining")
			game_over.emit()
			return false

	cell_filled.emit(row, col, value, is_correct)

	# Check if puzzle is complete
	if _is_puzzle_complete():
		puzzle_completed.emit()

	return is_correct

func _is_puzzle_complete() -> bool:
	"""Check if all cells are filled correctly"""
	for i in range(GRID_SIZE):
		for j in range(GRID_SIZE):
			if player_grid[i][j] != solution_grid[i][j]:
				return false
	return true

func is_cell_editable(row: int, col: int) -> bool:
	"""Check if a cell can be edited (wasn't part of original puzzle)"""
	return puzzle[row][col] == 0

func get_cell_value(row: int, col: int) -> int:
	"""Get current value in a cell"""
	return player_grid[row][col]

func get_solution_value(row: int, col: int) -> int:
	"""Get the correct solution for a cell"""
	return solution_grid[row][col]

func get_game_time() -> float:
	"""Get elapsed time in seconds since game start"""
	if _start_time == 0.0:
		return 0.0
	return Time.get_ticks_msec() / 1000.0 - _start_time

# Generating Valid Sudoku grid
func _fill_grid(grid_obj):
	for i in range(GRID_SIZE):
		for j in range(GRID_SIZE):
			if grid_obj[i][j] == 0:
				var numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9]
				numbers.shuffle()
				for num in numbers:
					if is_valid(grid_obj, i, j, num):
						grid_obj[i][j] = num
						if _fill_grid(grid_obj):
							return true
						grid_obj[i][j] = 0
				return false
	return true

func _create_empty_grid():
	solution_grid = []
	for i in range(GRID_SIZE):
		var row = []
		for j in range(GRID_SIZE):
			row.append(0)
		solution_grid.append(row)

func is_valid(grd, row, col, num):
	return (
		num not in grd[row] and
		num not in get_column(grd, col) and
		num not in get_subgrid(grd, row, col)
	)

func get_column(grd, col):
	var col_list = []
	for i in range(GRID_SIZE):
		col_list.append(grd[i][col])
	return col_list

func get_subgrid(grd, row, col):
	var subgrid = []
	var start_row = (row / 3) * 3
	var start_col = (col / 3) * 3
	for r in range(start_row, start_row + 3):
		for c in range(start_col, start_col + 3):
			subgrid.append(grd[r][c])
	return subgrid

func _create_puzzle(diff):
	puzzle = solution_grid.duplicate(true)
	# Scale difficulty by removing more cards: Easy=71 shown, Medium=30 shown, Hard=26 shown
	var removals = 0
	match diff:
		1:  # Easy
			removals = 10  # 71 cells shown
		3:  # Medium
			removals = 51  # 30 cells shown
		5:  # Hard
			removals = 55  # 26 cells shown
		_:
			removals = 30  # Fallback
	while removals > 0:
		var row = randi_range(0, 8)
		var col = randi_range(0, 8)
		if puzzle[row][col] != 0:
			var temp = puzzle[row][col]
			puzzle[row][col] = 0
			if not has_unique_solution(puzzle):
				puzzle[row][col] = temp
			else:
				removals -= 1

func has_unique_solution(puzzle_grid):
	solution_count = 0
	try_to_solve_grid(puzzle_grid.duplicate(true))
	return solution_count == 1

func try_to_solve_grid(puzzle_grid):
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			if puzzle_grid[row][col] == 0:
				for num in range(1, 10):
					if is_valid(puzzle_grid, row, col, num):
						puzzle_grid[row][col] = num
						try_to_solve_grid(puzzle_grid)
						puzzle_grid[row][col] = 0
				return
	solution_count += 1
	if solution_count > 1:
		return

func get_mirror_data() -> Dictionary:
	"""Get puzzle data for mirror mode synchronization"""
	return {
		"puzzle": puzzle.duplicate(true),
		"solution": solution_grid.duplicate(true),
		"difficulty": difficulty
	}

func get_game_state() -> Dictionary:
	"""Get current game state for saving/multiplayer"""
	return {
		"puzzle": puzzle,
		"solution": solution_grid,
		"player_grid": player_grid,
		"difficulty": difficulty,
		"show_hints": show_hints,
		"lives": lives
	}

func load_game_state(state: Dictionary):
	"""Load game state from save/multiplayer"""
	puzzle = state.get("puzzle", [])
	solution_grid = state.get("solution", [])
	player_grid = state.get("player_grid", [])
	difficulty = state.get("difficulty", 3)
	show_hints = state.get("show_hints", true)
	lives = state.get("lives", max_lives)

func get_save_data() -> Dictionary:
	"""Serialize game state for saving (wrapper for consistency)"""
	return get_game_state()

func restore_from_save(save_data: Dictionary) -> void:
	"""Restore game state from saved data (wrapper for consistency)"""
	if not save_data.is_empty():
		load_game_state(save_data)
