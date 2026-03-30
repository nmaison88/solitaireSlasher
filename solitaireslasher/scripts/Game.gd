extends Node
class_name Game

signal game_completed
signal card_moved(from_pile: String, to_pile: String, card_count: int)

var tableau: Array = []
var foundations: Array = []
var stock: Array[SolitaireCard] = []
var waste: Array[SolitaireCard] = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _moves_count: int = 0
var _start_time: float = 0.0
var _is_completed: bool = false

# Difficulty settings
var difficulty: String = "Medium"  # Easy, Medium, Hard
var draw_count: int = 3  # Cards to draw from stock
var max_stock_passes: int = -1  # -1 = unlimited, else limited passes

# Undo state tracking
var _last_move_state: Dictionary = {}
var _can_undo: bool = false
var _auto_winning: bool = false  # Guard against recursive auto-win calls
# Hint used by Board to play a reverse animation when undo is triggered
var last_move_hint: Dictionary = {}

var stock_index: int = 0  # Track stock position for save/load

func set_difficulty(diff: String) -> void:
	"""Set game difficulty"""
	difficulty = diff
	match diff:
		"Easy":
			draw_count = 1
			max_stock_passes = -1  # Unlimited
		"Medium":
			draw_count = 2
			max_stock_passes = -1  # Unlimited
		"Hard":
			draw_count = 3
			max_stock_passes = -1  # Unlimited
	print("Difficulty set to: ", difficulty, " (Draw: ", draw_count, ", Passes: ", max_stock_passes, ")")

func new_game(seed: int = -1) -> void:
	_rng.randomize()
	if seed != -1:
		_rng.seed = seed

	var deck = Deck.new_standard_deck()
	Deck.shuffle(deck, _rng)

	_setup_game_from_deck(deck)

func new_game_mirror(mirror_data: Dictionary) -> void:
	"""Create a game with predefined shuffled deck for mirror mode"""
	print("Game: Creating mirror mode game from original deck")

	# Use seed from mirror data
	_rng.randomize()
	if mirror_data.has("seed"):
		_rng.seed = mirror_data["seed"]

	# Recreate the original shuffled deck from mirror data
	var deck = []
	if mirror_data.has("deck"):
		# Recreate cards in the exact order they were shuffled
		for card_data in mirror_data["deck"]:
			var card = SolitaireCard.new()
			card.suit = card_data.suit
			card.rank = card_data.rank
			card.face_up = false  # All cards start face down
			card.pile_id = -1  # Will be assigned during dealing
			card.stock = false  # Will be assigned during dealing
			deck.append(card)
		print("Recreated deck with ", deck.size(), " cards for mirror mode")
	else:
		# Fallback: create and shuffle standard deck
		deck = Deck.new_standard_deck()
		Deck.shuffle(deck, _rng)
		print("Fallback: Created standard shuffled deck")

	# Use the same dealing logic as normal new_game
	_setup_game_from_deck(deck)

func _setup_game_from_deck(deck: Array) -> void:
	"""Setup game state from a deck of cards"""
	foundations = [[], [], [], []]
	tableau = [[], [], [], [], [], [], []]
	stock = []
	waste = []
	_moves_count = 0
	_start_time = Time.get_ticks_msec() / 1000.0
	_is_completed = false
	_can_undo = false
	_last_move_state = {}
	last_move_hint = {}

	var idx: int = 0
	for pile_i in range(7):
		for j in range(pile_i + 1):
			if idx < deck.size():
				var c = deck[idx]
				idx += 1
				c.face_up = (j == pile_i)  # Only top card face-up
				c.pile_id = pile_i
				tableau[pile_i].append(c)

	while idx < deck.size():
		if idx < deck.size():
			var c = deck[idx]
			c.stock = true
			stock.append(c)
			idx += 1

func get_mirror_data() -> Dictionary:
	"""Get complete game state for mirror mode synchronization"""
	var deck_data = []

	# Collect all cards from tableau
	for pile_i in range(tableau.size()):
		for card in tableau[pile_i]:
			deck_data.append({
				"suit": card.suit,
				"rank": card.rank,
				"face_up": card.face_up,
				"pile_id": card.pile_id,
				"stock": false
			})

	# Collect stock cards
	for card in stock:
		deck_data.append({
			"suit": card.suit,
			"rank": card.rank,
			"face_up": false,  # Stock cards are always face down
			"pile_id": -1,  # Stock pile
			"stock": true
		})

	# Collect waste cards
	for card in waste:
		deck_data.append({
			"suit": card.suit,
			"rank": card.rank,
			"face_up": card.face_up,
			"pile_id": -2,  # Waste pile
			"stock": false
		})

	return {
		"deck": deck_data,
		"seed": _rng.seed,
		"difficulty": difficulty
	}

func draw_from_stock_3() -> void:
	# Save state before drawing
	_save_state()

	# If stock is empty, recycle waste pile back to stock
	if stock.is_empty():
		var waste_size = waste.size() if waste else -1
		print("DEBUG: Game.draw_from_stock_3 - stock is empty, attempting to recycle waste (waste: ", ("null" if not waste else "array"), ", size: ", waste_size, ")")
		_recycle_waste_to_stock()
		# If still empty after recycling, nothing to draw
		if stock.is_empty():
			print("DEBUG: Game.draw_from_stock_3 - stock still empty after recycle, nothing to draw")
			return

	# Draw cards from stock to waste (respects difficulty setting)
	var cards_to_draw: int = min(draw_count, stock.size())
	print("DEBUG: Game.draw_from_stock_3 - drawing ", cards_to_draw, " cards (draw_count: ", draw_count, ", stock size: ", stock.size(), ")")
	for _i in range(cards_to_draw):
		var c = stock.pop_back()
		c.face_up = true
		c.stock = false  # Important: card is no longer in stock pile
		waste.append(c)

	print("DEBUG: Game.draw_from_stock_3 - after draw: stock size: ", stock.size(), ", waste size: ", waste.size())

	# Check for auto-win after drawing from stock
	_check_auto_win()

	# Play card draw sound
	if SoundManager:
		SoundManager.play_card_draw()

func _recycle_waste_to_stock() -> void:
	if waste.is_empty():
		return
	for i in range(waste.size() - 1, -1, -1):
		var c = waste[i]
		c.face_up = false
		c.stock = true  # Important: card is back in stock pile
		stock.append(c)
	waste.clear()

	# Play restart deck sound after recycling
	if SoundManager:
		SoundManager.play_restart_deck()

func get_debug_summary() -> Dictionary:
	var face_up_counts: Array = []
	var tableau_sizes: Array = []
	for p in tableau:
		var n: int = 0
		for c in p:
			if c.face_up:
				n += 1
		face_up_counts.append(n)
		tableau_sizes.append(p.size())

	var foundation_sizes: Array = []
	for f in foundations:
		foundation_sizes.append(f.size())

	return {
		"tableau_sizes": tableau_sizes,
		"tableau_face_up": face_up_counts,
		"stock": stock.size(),
		"waste": waste.size(),
		"foundations": foundation_sizes,
	}

func card_texture_path(card: SolitaireCard) -> String:
	if not card.face_up:
		# Use card back for face-down cards
		return "res://card_assets/Back1.png"

	# Reference project uses: {value}.{suit}.png where value is 1-13 and suit is 1-4
	var value = card.rank  # 1-13
	var suit = 0
	match card.suit:
		0: suit = 1  # CLUBS
		1: suit = 2  # DIAMONDS
		2: suit = 3  # HEARTS
		3: suit = 4  # SPADES

	return "res://card_assets/%d.%d.png" % [value, suit]

func has_card_texture(card: SolitaireCard) -> bool:
	return ResourceLoader.exists(card_texture_path(card))

func can_place_on_foundation(card: SolitaireCard, foundation_index: int) -> bool:
	var foundation = foundations[foundation_index]
	if foundation.is_empty():
		return card.rank == 1  # Only Ace on empty foundation

	var top_card = foundation[-1]
	return card.suit == top_card.suit and card.rank == top_card.rank + 1

func can_place_on_tableau(card: SolitaireCard, tableau_index: int) -> bool:
	var pile = tableau[tableau_index]
	if pile.is_empty():
		return card.rank == 13  # Only King on empty tableau

	var top_card = pile[-1]
	if not top_card.face_up:
		return false

	return card.is_red() != top_card.is_red() and card.rank == top_card.rank - 1

func move_to_foundation(from_pile: String, from_index: int, foundation_index: int) -> bool:
	last_move_hint = {"type": "to_foundation", "from_pile": from_pile,
		"from_col": from_index, "foundation_col": foundation_index}
	_save_state()

	var card: SolitaireCard

	match from_pile:
		"tableau":
			if from_index >= tableau.size() or tableau[from_index].is_empty():
				return false
			card = tableau[from_index][-1]
		"waste":
			if waste.is_empty():
				return false
			card = waste[-1]
		_:
			return false

	if not can_place_on_foundation(card, foundation_index):
		return false

	match from_pile:
		"tableau":
			tableau[from_index].pop_back()
			if not tableau[from_index].is_empty():
				tableau[from_index][-1].face_up = true
		"waste":
			waste.pop_back()

	foundations[foundation_index].append(card)
	_moves_count += 1
	card_moved.emit(from_pile, "foundation", 1)
	_check_completion()
	_check_auto_win()  # Check for auto-win after foundation move

	# Play card place sound
	if SoundManager:
		SoundManager.play_card_place()
		# Play foundation sound after card_place sound
		SoundManager.play_foundation()

	return true

func move_tableau_to_tableau(from_index: int, to_index: int, card_count: int) -> bool:
	last_move_hint = {"type": "tableau_to_tableau",
		"from_col": from_index, "to_col": to_index, "card_count": card_count}
	_save_state()

	if from_index >= tableau.size() or to_index >= tableau.size():
		return false

	var from_pile = tableau[from_index]
	var to_pile = tableau[to_index]

	if card_count > from_pile.size() or card_count < 1:
		return false

	var moving_cards = from_pile.slice(from_pile.size() - card_count)
	var first_moving_card = moving_cards[0]

	if not first_moving_card.face_up:
		return false

	if not can_place_on_tableau(first_moving_card, to_index):
		return false

	# Move cards in correct order (not reversed)
	for card in moving_cards:
		to_pile.append(card)

	# Remove the moved cards from source pile
	for i in range(card_count):
		from_pile.pop_back()

	if not from_pile.is_empty():
		from_pile[-1].face_up = true

	_moves_count += 1
	card_moved.emit("tableau", "tableau", card_count)

	# Check for auto-win after cards are flipped
	_check_auto_win()

	# Play card place sound
	if SoundManager:
		SoundManager.play_card_place()

	return true

func move_foundation_to_tableau(foundation_index: int, tableau_index: int) -> bool:
	# Save state before move
	_save_state()

	if foundation_index >= foundations.size() or tableau_index >= tableau.size():
		return false

	if foundations[foundation_index].is_empty():
		return false

	var card = foundations[foundation_index][-1]

	if not can_place_on_tableau(card, tableau_index):
		return false

	# Remove card from foundation
	foundations[foundation_index].pop_back()

	# Add card to tableau
	tableau[tableau_index].append(card)

	_moves_count += 1
	card_moved.emit("foundation", "tableau", 1)

	# Check for auto-win after foundation move
	_check_auto_win()

	# Play card place sound
	if SoundManager:
		SoundManager.play_card_place()

	return true

func move_waste_to_tableau(tableau_index: int) -> bool:
	last_move_hint = {"type": "waste_to_tableau", "to_col": tableau_index}
	_save_state()

	if waste.is_empty() or tableau_index >= tableau.size():
		return false

	var card = waste[-1]
	if not can_place_on_tableau(card, tableau_index):
		return false

	tableau[tableau_index].append(waste.pop_back())
	_moves_count += 1
	card_moved.emit("waste", "tableau", 1)

	# Check for auto-win after waste move
	_check_auto_win()

	# Play card place sound
	if SoundManager:
		SoundManager.play_card_place()

	return true

func _check_completion() -> void:
	if _is_completed:
		return

	for foundation in foundations:
		if foundation.size() != 13:
			return

	_is_completed = true
	game_completed.emit()

	# Play win sound
	if SoundManager:
		SoundManager.play_win()

	print("Game completed! Moves: ", _moves_count, " Time: ", Time.get_ticks_msec() / 1000.0 - _start_time)

func _check_auto_win() -> void:
	"""Auto-win when stock is empty and every tableau card is face-up.
	At that point the player can always complete the game, so we do it for them."""
	print("DEBUG: _check_auto_win called - _is_completed: ", _is_completed, ", _auto_winning: ", _auto_winning)

	if _is_completed or _auto_winning:
		print("DEBUG: Early return - already completed or auto-winning")
		return

	# Condition 1: stock must be empty
	print("DEBUG: Stock size: ", stock.size())
	if not stock.is_empty():
		print("DEBUG: Stock not empty, returning")
		return

	# Condition 2: all tableau cards must be face-up (no hidden cards remain)
	var face_down_count = 0
	for pile_idx in range(tableau.size()):
		for card_idx in range(tableau[pile_idx].size()):
			var card = tableau[pile_idx][card_idx]
			if not card.face_up:
				print("DEBUG: Found face-down card at tableau[", pile_idx, "][", card_idx, "]")
				face_down_count += 1

	print("DEBUG: Face-down cards in tableau: ", face_down_count)
	if face_down_count > 0:
		print("DEBUG: Face-down cards exist, returning")
		return

	# All cards are visible — auto-complete to foundation
	var total_cards = 0
	var tableau_cards = 0
	var waste_cards = waste.size() if waste else 0

	for pile in tableau:
		tableau_cards += pile.size()
		total_cards += pile.size()
	total_cards += waste_cards

	print("DEBUG: Auto-win conditions met! Tableau cards: ", tableau_cards, ", Waste cards: ", waste_cards, ", Total: ", total_cards)

	if total_cards > 0:
		print("Auto-win detected! Moving all ", total_cards, " cards to foundation")
		_auto_winning = true
		_auto_move_all_to_foundation()
		_auto_winning = false
	else:
		print("DEBUG: No cards to move, already complete?")

func _auto_move_all_to_foundation() -> void:
	"""Automatically move all remaining cards to foundation with quick animation"""
	var moved = true
	var moves_made = 0

	# Keep moving until no more moves possible
	while moved:
		moved = false

		# Try moving waste cards to foundation
		if not waste.is_empty():
			var card = waste[-1]
			if can_place_on_foundation(card, card.suit):
				move_to_foundation("waste", -1, card.suit)
				moved = true
				moves_made += 1
				# Small delay for quick animation effect (much faster than normal)
				await get_tree().create_timer(0.05).timeout

		# Try moving tableau cards to foundation
		for i in range(tableau.size()):
			if not tableau[i].is_empty():
				var card = tableau[i][-1]
				if can_place_on_foundation(card, card.suit):
					move_to_foundation("tableau", i, card.suit)
					moved = true
					moves_made += 1
					# Small delay for quick animation effect (much faster than normal)
					await get_tree().create_timer(0.05).timeout

	print("Auto-win completed! Moved ", moves_made, " cards automatically")
	# Trigger win after all cards are moved
	_check_completion()

func get_game_time() -> float:
	if _start_time == 0.0:
		return 0.0
	return Time.get_ticks_msec() / 1000.0 - _start_time

func get_moves_count() -> int:
	return _moves_count

func is_completed() -> bool:
	return _is_completed

func get_game_state() -> Dictionary:
	var foundation_sizes = []
	for f in foundations:
		foundation_sizes.append(f.size())

	var tableau_sizes = []
	for pile in tableau:
		tableau_sizes.append(pile.size())

	return {
		"tableau_sizes": tableau_sizes,
		"foundation_sizes": foundation_sizes,
		"stock_size": stock.size(),
		"waste_size": waste.size(),
		"moves": _moves_count,
		"time": get_game_time(),
		"completed": _is_completed
	}

func auto_complete() -> bool:
	if not _can_auto_complete():
		return false

	while true:
		var moved = false

		for i in range(tableau.size()):
			if not tableau[i].is_empty() and tableau[i][-1].face_up:
				var card = tableau[i][-1]
				for j in range(4):
					if can_place_on_foundation(card, j):
						move_to_foundation("tableau", i, j)
						moved = true
						break

		if not waste.is_empty():
			var card = waste[-1]
			for j in range(4):
				if can_place_on_foundation(card, j):
					move_to_foundation("waste", -1, j)
					moved = true
					break

		if not moved:
			break

	return _is_completed

func _can_auto_complete() -> bool:
	for pile in tableau:
		for card in pile:
			if not card.face_up:
				return false
	return true

func get_hint() -> Dictionary:
	for i in range(tableau.size()):
		if not tableau[i].is_empty():
			var card = tableau[i][-1]
			if card.face_up:
				for j in range(4):
					if can_place_on_foundation(card, j):
						return {"type": "tableau_to_foundation", "from": i, "to": j}

	for i in range(tableau.size()):
		for j in range(tableau.size()):
			if i != j and not tableau[i].is_empty():
				for card_count in range(1, tableau[i].size() + 1):
					var card_index = tableau[i].size() - card_count
					if tableau[i][card_index].face_up:
						if can_place_on_tableau(tableau[i][card_index], j):
							return {"type": "tableau_to_tableau", "from": i, "to": j, "count": card_count}

	if not waste.is_empty():
		var card = waste[-1]
		for i in range(tableau.size()):
			if can_place_on_tableau(card, i):
				return {"type": "waste_to_tableau", "to": i}

		for i in range(4):
			if can_place_on_foundation(card, i):
				return {"type": "waste_to_foundation", "to": i}

	return {"type": "none"}

func _save_state() -> void:
	"""Save current game state before making a move"""
	# Must deep-copy each SolitaireCard — pile.duplicate() only copies the array,
	# leaving the card objects as shared references. Mutating face_up etc. would
	# otherwise corrupt the saved snapshot.
	_last_move_state = {
		"tableau": [],
		"foundations": [],
		"stock": [],
		"waste": []
	}

	for card in stock:
		_last_move_state["stock"].append(card.duplicate())
	for card in waste:
		_last_move_state["waste"].append(card.duplicate())
	for pile in tableau:
		var pile_copy = []
		for card in pile:
			pile_copy.append(card.duplicate())
		_last_move_state["tableau"].append(pile_copy)
	for pile in foundations:
		var pile_copy = []
		for card in pile:
			pile_copy.append(card.duplicate())
		_last_move_state["foundations"].append(pile_copy)

	_can_undo = true

func undo() -> bool:
	"""Undo the last move. Returns true if undo was successful."""
	if not _can_undo or _last_move_state.is_empty():
		return false

	# Restore tableau (untyped array — fine)
	tableau = []
	for pile in _last_move_state["tableau"]:
		var pile_copy = []
		for card in pile:
			pile_copy.append(card)
		tableau.append(pile_copy)

	# Restore foundations (untyped array — fine)
	foundations = []
	for pile in _last_move_state["foundations"]:
		var pile_copy = []
		for card in pile:
			pile_copy.append(card)
		foundations.append(pile_copy)

	# stock/waste are typed Array[SolitaireCard] — must fill element-by-element,
	# not assign from an untyped Array (causes crash in Godot 4).
	stock.clear()
	for card in _last_move_state["stock"]:
		stock.append(card as SolitaireCard)
	waste.clear()
	for card in _last_move_state["waste"]:
		waste.append(card as SolitaireCard)

	# Clear undo state - only one undo allowed
	_can_undo = false
	_last_move_state = {}
	last_move_hint = {}

	return true

func can_undo() -> bool:
	"""Check if undo is available"""
	return _can_undo

func has_valid_moves() -> bool:
	"""Check if the player has any valid moves available (not jammed)"""
	# Check if we can draw from stock
	if not stock.is_empty():
		return true

	# Check if waste can move to foundation
	if not waste.is_empty():
		var waste_card = waste[-1]
		for i in range(4):
			if can_place_on_foundation(waste_card, i):
				return true
		# Check if waste can move to tableau
		for i in range(7):
			if can_place_on_tableau(waste_card, i):
				return true

	# Check if any tableau card can move to foundation
	for pile_idx in range(7):
		if not tableau[pile_idx].is_empty():
			var top_card = tableau[pile_idx][-1]
			if top_card.face_up:
				for f_idx in range(4):
					if can_place_on_foundation(top_card, f_idx):
						return true

	# Check if any tableau cards can move to another tableau
	for from_idx in range(7):
		if tableau[from_idx].is_empty():
			continue
		for card_idx in range(tableau[from_idx].size()):
			var card = tableau[from_idx][card_idx]
			if not card.face_up:
				continue
			# Try moving this card (and cards below it) to other tableau piles
			for to_idx in range(7):
				if from_idx == to_idx:
					continue
				if can_place_on_tableau(card, to_idx):
					return true

	# No valid moves found - player is jammed
	return false

func get_save_data() -> Dictionary:
	"""Serialize game state for saving"""
	var tableau_data: Array = []
	for col in tableau:
		var col_data: Array = []
		for card in col:
			col_data.append({
				"suit": card.suit,
				"rank": card.rank,
				"face_up": card.face_up
			})
		tableau_data.append(col_data)

	var stock_data: Array = []
	for card in stock:
		stock_data.append({
			"suit": card.suit,
			"rank": card.rank,
			"face_up": card.face_up
		})

	var waste_data: Array = []
	for card in waste:
		waste_data.append({
			"suit": card.suit,
			"rank": card.rank,
			"face_up": card.face_up
		})

	var foundation_data: Array = []
	for col in foundations:
		var col_data: Array = []
		for card in col:
			col_data.append({
				"suit": card.suit,
				"rank": card.rank,
				"face_up": card.face_up
			})
		foundation_data.append(col_data)

	return {
		"tableau": tableau_data,
		"stock": stock_data,
		"waste": waste_data,
		"foundations": foundation_data,
		"stock_index": stock_index,
		"difficulty": difficulty
	}

func restore_from_save(save_data: Dictionary) -> void:
	"""Restore game state from saved data"""
	if save_data.is_empty():
		return

	# Reconstruct tableau
	tableau.clear()
	for col_data in save_data.get("tableau", []):
		var col: Array = []
		for card_data in col_data:
			var card = SolitaireCard.new()
			card.suit = card_data.get("suit", 0)
			card.rank = card_data.get("rank", 0)
			card.face_up = card_data.get("face_up", false)
			col.append(card)
		tableau.append(col)

	# Reconstruct stock
	stock.clear()
	for card_data in save_data.get("stock", []):
		var card = SolitaireCard.new()
		card.suit = card_data.get("suit", 0)
		card.rank = card_data.get("rank", 0)
		card.face_up = card_data.get("face_up", false)
		stock.append(card)

	# Reconstruct waste
	waste.clear()
	for card_data in save_data.get("waste", []):
		var card = SolitaireCard.new()
		card.suit = card_data.get("suit", 0)
		card.rank = card_data.get("rank", 0)
		card.face_up = card_data.get("face_up", false)
		waste.append(card)

	# Reconstruct foundations
	foundations.clear()
	for col_data in save_data.get("foundations", []):
		var col: Array = []
		for card_data in col_data:
			var card = SolitaireCard.new()
			card.suit = card_data.get("suit", 0)
			card.rank = card_data.get("rank", 0)
			card.face_up = card_data.get("face_up", false)
			col.append(card)
		foundations.append(col)

	stock_index = save_data.get("stock_index", 0)
	difficulty = save_data.get("difficulty", "Medium")
	_can_undo = false
	_last_move_state = {}
