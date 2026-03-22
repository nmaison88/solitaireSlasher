extends Node

# AudioStreamPlayer nodes for different sounds
var card_place_player: AudioStreamPlayer
var card_draw_player: AudioStreamPlayer
var win_player: AudioStreamPlayer
var retry_player: AudioStreamPlayer
var lose_player: AudioStreamPlayer

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

func _load_sound_files() -> void:
	# Try to load sound files from the sounds directory
	var sound_paths = {
		"card_place": ["res://sounds/card_place.wav", "res://sounds/card_place.ogg"],
		"card_draw": ["res://sounds/card_draw.wav", "res://sounds/card_draw.ogg"],
		"win": ["res://sounds/win.wav", "res://sounds/win.ogg"],
		"retry": ["res://sounds/retry.wav", "res://sounds/retry.ogg"],
		"lose": ["res://sounds/lose.wav", "res://sounds/lose.ogg"]
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
