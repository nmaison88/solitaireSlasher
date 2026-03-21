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

# Undo state tracking
var _last_move_state: Dictionary = {}
var _can_undo: bool = false

func new_game(seed: int = -1) -> void:
	_rng.randomize()
	if seed != -1:
		_rng.seed = seed

	var deck = Deck.new_standard_deck()
	Deck.shuffle(deck, _rng)

	foundations = [[], [], [], []]
	tableau = [[], [], [], [], [], [], []]
	stock = []
	waste = []
	_moves_count = 0
	_start_time = Time.get_ticks_msec() / 1000.0
	_is_completed = false
	_can_undo = false
	_last_move_state = {}

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

func draw_from_stock_3() -> void:
	# Save state before drawing
	_save_state()
	
	# If stock is empty, recycle waste pile back to stock
	if stock.is_empty():
		_recycle_waste_to_stock()
		# If still empty after recycling, nothing to draw
		if stock.is_empty():
			return

	# Draw up to 3 cards from stock to waste
	var draw_count: int = min(3, stock.size())
	for _i in range(draw_count):
		var c = stock.pop_back()
		c.face_up = true
		waste.append(c)

func _recycle_waste_to_stock() -> void:
	if waste.is_empty():
		return
	for i in range(waste.size() - 1, -1, -1):
		var c = waste[i]
		c.face_up = false
		stock.append(c)
	waste.clear()

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
	# Save state before move
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
	return true

func move_tableau_to_tableau(from_index: int, to_index: int, card_count: int) -> bool:
	# Save state before move
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
	
	for i in range(card_count):
		to_pile.append(from_pile.pop_back())
	
	if not from_pile.is_empty():
		from_pile[-1].face_up = true
	
	_moves_count += 1
	card_moved.emit("tableau", "tableau", card_count)
	return true

func move_waste_to_tableau(tableau_index: int) -> bool:
	# Save state before move
	_save_state()
	
	if waste.is_empty() or tableau_index >= tableau.size():
		return false
	
	var card = waste[-1]
	if not can_place_on_tableau(card, tableau_index):
		return false
	
	tableau[tableau_index].append(waste.pop_back())
	_moves_count += 1
	card_moved.emit("waste", "tableau", 1)
	return true

func _check_completion() -> void:
	if _is_completed:
		return
	
	for foundation in foundations:
		if foundation.size() != 13:
			return
	
	_is_completed = true
	game_completed.emit()

func get_game_time() -> float:
	if _start_time == 0.0:
		return 0.0
	return Time.get_time_dict_from_system().hour * 3600 + Time.get_time_dict_from_system().minute * 60 + Time.get_time_dict_from_system().second - _start_time

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
	_last_move_state = {
		"tableau": [],
		"foundations": [],
		"stock": stock.duplicate(),
		"waste": waste.duplicate()
	}
	
	# Deep copy tableau
	for pile in tableau:
		_last_move_state["tableau"].append(pile.duplicate())
	
	# Deep copy foundations
	for pile in foundations:
		_last_move_state["foundations"].append(pile.duplicate())
	
	_can_undo = true

func undo() -> bool:
	"""Undo the last move. Returns true if undo was successful."""
	if not _can_undo or _last_move_state.is_empty():
		return false
	
	# Restore state
	tableau = []
	for pile in _last_move_state["tableau"]:
		tableau.append(pile.duplicate())
	
	foundations = []
	for pile in _last_move_state["foundations"]:
		foundations.append(pile.duplicate())
	
	stock = _last_move_state["stock"].duplicate()
	waste = _last_move_state["waste"].duplicate()
	
	# Clear undo state - only one undo allowed
	_can_undo = false
	_last_move_state = {}
	
	return true

func can_undo() -> bool:
	"""Check if undo is available"""
	return _can_undo
