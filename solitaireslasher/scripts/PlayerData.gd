extends Node

const SAVE_FILE_PATH = "user://player_data.json"

var player_name: String = "Player"
var theme: String = "dark"
var stats: Dictionary = {
	"games_played": 0,
	"games_won": 0,
	"total_time": 0.0,
	"best_time": 0.0,
	"multiplayer_wins": 0,
	"multiplayer_losses": 0
}

func _ready() -> void:
	load_data()

func save_data() -> void:
	"""Save player data to JSON file"""
	var data = {
		"player_name": player_name,
		"theme": theme,
		"stats": stats
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
				
			if data.has("stats"):
				stats = data.stats
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

