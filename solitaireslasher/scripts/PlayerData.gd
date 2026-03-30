extends Node

const SAVE_FILE_PATH = "user://player_data.json"

var player_name: String = "Player"
var theme: String = "dark"
var background_music_enabled: bool = true
var stats: Dictionary = {
	"games_played": 0,
	"games_won": 0,
	"total_time": 0.0,
	"best_time": 0.0,
	"multiplayer_wins": 0,
	"multiplayer_losses": 0
}

# Saved game states (one per game type)
var solitaire_save: Dictionary = {}
var spider_save: Dictionary = {}
var sudoku_save: Dictionary = {}

func _ready() -> void:
	load_data()

func save_data() -> void:
	"""Save player data to JSON file"""
	var data = {
		"player_name": player_name,
		"theme": theme,
		"background_music_enabled": background_music_enabled,
		"stats": stats,
		"solitaire_save": solitaire_save,
		"spider_save": spider_save,
		"sudoku_save": sudoku_save
	}

	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(data, "\t")
		file.store_string(json_string)
		file.close()
		print("Player data saved: ", player_name)
	else:
		print("Failed to save player data")

func load_data() -> void:
	"""Load player data from JSON file"""
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		print("No save file found, using defaults")
		return

	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()

		var json = JSON.new()
		var parse_result = json.parse(json_string)

		if parse_result == OK:
			var data = json.data
			if data.has("player_name"):
				player_name = data.player_name

			if data.has("theme"):
				theme = data.theme

			if data.has("background_music_enabled"):
				background_music_enabled = data.background_music_enabled

			if data.has("stats"):
				stats = data.stats

			if data.has("solitaire_save"):
				solitaire_save = data.solitaire_save

			if data.has("spider_save"):
				spider_save = data.spider_save

			if data.has("sudoku_save"):
				sudoku_save = data.sudoku_save

			print("Player data loaded: ", player_name)
		else:
			print("Failed to parse player data JSON")
	else:
		print("Failed to open player data file")

func set_player_name(new_name: String) -> void:
	"""Set player name and save"""
	player_name = new_name
	save_data()

func get_player_name() -> String:
	"""Get current player name"""
	return player_name

func update_stats(stat_name: String, value) -> void:
	"""Update a specific stat and save"""
	if stats.has(stat_name):
		stats[stat_name] = value
		save_data()

func increment_stat(stat_name: String, amount = 1) -> void:
	"""Increment a stat by amount and save"""
	if stats.has(stat_name):
		stats[stat_name] += amount
		save_data()

func get_stat(stat_name: String):
	"""Get a specific stat value"""
	return stats.get(stat_name, 0)

func get_theme() -> String:
	"""Get current theme"""
	return theme

func set_theme(new_theme: String) -> void:
	"""Set theme and save"""
	theme = new_theme
	save_data()

func is_background_music_enabled() -> bool:
	"""Get background music setting"""
	return background_music_enabled

func set_background_music_enabled(enabled: bool) -> void:
	"""Set background music and save"""
	background_music_enabled = enabled
	save_data()

func save_game(game_type: String, state_data: Dictionary) -> void:
	"""Save a game state for the specified game type"""
	match game_type:
		"Solitaire":
			solitaire_save = state_data
		"Spider":
			spider_save = state_data
		"Sudoku":
			sudoku_save = state_data
	save_data()
	print("Game saved: ", game_type)

func load_game(game_type: String) -> Dictionary:
	"""Load a saved game state for the specified game type"""
	match game_type:
		"Solitaire":
			return solitaire_save.duplicate(true)
		"Spider":
			return spider_save.duplicate(true)
		"Sudoku":
			return sudoku_save.duplicate(true)
	return {}

func has_saved_game(game_type: String) -> bool:
	"""Check if there's a saved game for the specified game type"""
	match game_type:
		"Solitaire":
			return not solitaire_save.is_empty()
		"Spider":
			return not spider_save.is_empty()
		"Sudoku":
			return not sudoku_save.is_empty()
	return false

func clear_saved_game(game_type: String) -> void:
	"""Clear saved game for the specified game type"""
	match game_type:
		"Solitaire":
			solitaire_save.clear()
		"Spider":
			spider_save.clear()
		"Sudoku":
			sudoku_save.clear()
	save_data()
	print("Game save cleared: ", game_type)
