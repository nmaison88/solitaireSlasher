extends Node

# AudioStreamPlayer nodes for different sounds
var card_place_player: AudioStreamPlayer
var card_draw_player: AudioStreamPlayer
var win_player: AudioStreamPlayer
var retry_player: AudioStreamPlayer
var lose_player: AudioStreamPlayer
var incorrect_player: AudioStreamPlayer
var place_player: AudioStreamPlayer
var foundation_player: AudioStreamPlayer
var restart_deck_player: AudioStreamPlayer
var music_player: AudioStreamPlayer

func _ready() -> void:
	_setup_audio_players()
	_load_sound_files()

func _setup_audio_players() -> void:
	# Card place sound
	card_place_player = AudioStreamPlayer.new()
	card_place_player.name = "CardPlacePlayer"
	add_child(card_place_player)
	
	# Card draw sound
	card_draw_player = AudioStreamPlayer.new()
	card_draw_player.name = "CardDrawPlayer"
	add_child(card_draw_player)
	
	# Win sound
	win_player = AudioStreamPlayer.new()
	win_player.name = "WinPlayer"
	add_child(win_player)
	
	# Retry sound
	retry_player = AudioStreamPlayer.new()
	retry_player.name = "RetryPlayer"
	add_child(retry_player)
	
	# Lose sound
	lose_player = AudioStreamPlayer.new()
	lose_player.name = "LosePlayer"
	add_child(lose_player)
	
	# Incorrect sound
	incorrect_player = AudioStreamPlayer.new()
	incorrect_player.name = "IncorrectPlayer"
	add_child(incorrect_player)
	
	# Place sound (for Sudoku correct entries)
	place_player = AudioStreamPlayer.new()
	place_player.name = "PlacePlayer"
	add_child(place_player)
	
	# Foundation sound
	foundation_player = AudioStreamPlayer.new()
	foundation_player.name = "FoundationPlayer"
	add_child(foundation_player)
	
	# Restart deck sound
	restart_deck_player = AudioStreamPlayer.new()
	restart_deck_player.name = "RestartDeckPlayer"
	add_child(restart_deck_player)

	# Background music player
	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.volume_db = -6.0
	add_child(music_player)
	music_player.finished.connect(_on_music_finished)

func _load_sound_files() -> void:
	# Try to load sound files from the sounds directory
	var sound_paths = {
		"card_place": ["res://sounds/card_place.wav", "res://sounds/card_place.ogg"],
		"card_draw": ["res://sounds/card_draw.wav", "res://sounds/card_draw.ogg"],
		"win": ["res://sounds/win.wav", "res://sounds/win.ogg"],
		"retry": ["res://sounds/retry.wav", "res://sounds/retry.ogg"],
		"lose": ["res://sounds/lose.wav", "res://sounds/lose.ogg"],
		"incorrect": ["res://sounds/incorrect.wav", "res://sounds/incorrect.ogg"],
		"place": ["res://sounds/place.wav", "res://sounds/place.ogg"],
		"foundation": ["res://sounds/foundation.wav", "res://sounds/foundation.ogg"],
		"restart_deck": ["res://sounds/restart_deck.wav", "res://sounds/restart_deck.ogg"]
	}
	
	# Load card place sound
	for path in sound_paths["card_place"]:
		if ResourceLoader.exists(path):
			card_place_player.stream = load(path)
			print("Loaded card place sound: ", path)
			break
	
	# Load card draw sound
	for path in sound_paths["card_draw"]:
		if ResourceLoader.exists(path):
			card_draw_player.stream = load(path)
			print("Loaded card draw sound: ", path)
			break
	
	# Load win sound
	for path in sound_paths["win"]:
		if ResourceLoader.exists(path):
			win_player.stream = load(path)
			print("Loaded win sound: ", path)
			break
	
	# Load retry sound
	for path in sound_paths["retry"]:
		if ResourceLoader.exists(path):
			retry_player.stream = load(path)
			print("Loaded retry sound: ", path)
			break
	
	# Load lose sound
	for path in sound_paths["lose"]:
		if ResourceLoader.exists(path):
			lose_player.stream = load(path)
			print("Loaded lose sound: ", path)
			break
	
	# Load incorrect sound
	for path in sound_paths["incorrect"]:
		if ResourceLoader.exists(path):
			incorrect_player.stream = load(path)
			print("Loaded incorrect sound: ", path)
			break
	
	# Load place sound
	for path in sound_paths["place"]:
		if ResourceLoader.exists(path):
			place_player.stream = load(path)
			print("Loaded place sound: ", path)
			break
	
	# Load foundation sound
	for path in sound_paths["foundation"]:
		if ResourceLoader.exists(path):
			foundation_player.stream = load(path)
			print("Loaded foundation sound: ", path)
			break
	
	# Load restart deck sound
	for path in sound_paths["restart_deck"]:
		if ResourceLoader.exists(path):
			restart_deck_player.stream = load(path)
			print("Loaded restart deck sound: ", path)
			break

	# Load background music
	var music_path = "res://sounds/App_Background_music.wav"
	if ResourceLoader.exists(music_path):
		music_player.stream = load(music_path)
		print("Loaded background music: ", music_path)

func play_card_place() -> void:
	if card_place_player and card_place_player.stream:
		card_place_player.play()

func play_card_draw() -> void:
	if card_draw_player and card_draw_player.stream:
		card_draw_player.play()

func play_win() -> void:
	if win_player and win_player.stream:
		win_player.play()

func play_retry() -> void:
	if retry_player and retry_player.stream:
		retry_player.play()

func play_lose() -> void:
	if lose_player and lose_player.stream:
		lose_player.play()

func play_incorrect() -> void:
	if incorrect_player and incorrect_player.stream:
		incorrect_player.play()

func play_place() -> void:
	if place_player and place_player.stream:
		place_player.play()

func play_foundation() -> void:
	if foundation_player and foundation_player.stream:
		foundation_player.play()

func play_restart_deck() -> void:
	if restart_deck_player and restart_deck_player.stream:
		restart_deck_player.play()

func play_background_music() -> void:
	if music_player and music_player.stream and not music_player.playing:
		music_player.play()

func stop_background_music() -> void:
	if music_player and music_player.playing:
		music_player.stop()

func play_game_start() -> void:
	stop_background_music()
	play_restart_deck()

func _on_music_finished() -> void:
	# Loop the music when it finishes
	if music_player and music_player.stream:
		music_player.play()

# Helper function to load sounds from files
func load_sounds(card_place_path: String, card_draw_path: String, win_path: String) -> void:
	if ResourceLoader.exists(card_place_path):
		card_place_player.stream = load(card_place_path)
	
	if ResourceLoader.exists(card_draw_path):
		card_draw_player.stream = load(card_draw_path)
	
	if ResourceLoader.exists(win_path):
		win_player.stream = load(win_path)

# Generate simple procedural sounds if no files are available
func generate_simple_sounds() -> void:
	# For now, we'll create placeholder AudioStreamGenerators
	# In a real implementation, you'd use actual sound files
	pass
