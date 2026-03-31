extends Node
class_name SpiderGame

signal game_won
signal sequence_completed(col: int, suit: int)  # Emitted when a sequence (K-A) is completed
signal game_completed
signal card_moved

const TABLEAU_COUNT = 7
const SEQUENCES_TO_WIN = 4

var tableaus: Array = []       # Array[Array[SolitaireCard]], index 0=bottom, -1=top
var stock: Array = []          # Array[SolitaireCard]
var sequences_completed: int = 0
var _difficulty: String = "Easy"
var _start_time: float = 0.0  # Time when game started (in seconds)
var _seed: int = -1  # Seed used for RNG (for mirror mode)

var _history: Array = []    # stack of state snapshots for undo
var _redo_stack: Array = [] # stack of state snapshots for redo

# ── Undo / Redo ───────────────────────────────────────────────────────────────

func _save_state() -> Dictionary:
	# Snapshot array structure (card objects stay the same; we capture their face_up)
	var state: Dictionary = {
		"tableaus": [],
		"stock": stock.duplicate(),
		"seq": sequences_completed,
		"face_ups": {}
	}
	for col in tableaus:
		state.tableaus.append(col.duplicate())
	for col in tableaus:
		for card in col:
			state.face_ups[card] = card.face_up
	for card in stock:
		state.face_ups[card] = card.face_up
	return state

func _restore_state(state: Dictionary) -> void:
	tableaus.clear()
	for col_snap in state.tableaus:
		tableaus.append(col_snap.duplicate())
	stock = state.stock.duplicate()
	sequences_completed = state.seq
	for card in state.face_ups.keys():
		if is_instance_valid(card):
			card.face_up = state.face_ups[card]

func can_undo() -> bool:
	return not _history.is_empty()

func can_redo() -> bool:
	return not _redo_stack.is_empty()

func undo() -> void:
	if _history.is_empty():
		return
	_redo_stack.append(_save_state())
	_restore_state(_history.pop_back())

func redo() -> void:
	if _redo_stack.is_empty():
		return
	_history.append(_save_state())
	_restore_state(_redo_stack.pop_back())

# ── Game logic ────────────────────────────────────────────────────────────────

func new_game(difficulty_string: String = "Easy", seed: int = -1) -> void:
	_difficulty = difficulty_string
	_seed = seed
	sequences_completed = 0
	_history.clear()
	_redo_stack.clear()
	_start_time = Time.get_ticks_msec() / 1000.0  # Start timer

	# Reset tableaus and stock
	tableaus.clear()
	for _i in range(TABLEAU_COUNT):
		tableaus.append([])
	stock.clear()

	# Build deck
	var deck: Array = []
	if _difficulty == "Easy" or _difficulty == "Medium":
		# 4 copies of 13 Spades cards (suit=3, rank 1–13) = 52 total
		for _copy in range(4):
			for r in range(1, 14):
				var c = SolitaireCard.new()
				c.suit = SolitaireCard.Suit.SPADES
				c.rank = r
				c.face_up = false
				c.stock = false
				deck.append(c)
	else:
		# Hard: 1 copy each of all 4 suits = 52 total
		for s in range(4):
			for r in range(1, 14):
				var c = SolitaireCard.new()
				c.suit = s
				c.rank = r
				c.face_up = false
				c.stock = false
				deck.append(c)

	# Shuffle with seed support
	if seed != -1:
		var rng = RandomNumberGenerator.new()
		rng.seed = seed
		_seed = seed
		# Manual Fisher-Yates shuffle with seeded RNG
		for i in range(deck.size() - 1, 0, -1):
			var j = rng.randi_range(0, i)
			var temp = deck[i]
			deck[i] = deck[j]
			deck[j] = temp
	else:
		deck.shuffle()
		_seed = -1

	# Use common deal logic
	_deal_from_deck(deck)


func _deal_from_deck(deck: Array) -> void:
	"""Common deal logic for new_game() and new_game_mirror()"""
	# Deal Klondike-style:
	# col 0 gets 1 card, col 1 gets 2, ..., col 6 gets 7 (28 total)
	var deal_index = 0
	for col in range(TABLEAU_COUNT):
		var card_count = col + 1
		for card_i in range(card_count):
			var card = deck[deal_index]
			deal_index += 1
			# Only last card in each column is face-up
			card.face_up = (card_i == card_count - 1)
			tableaus[col].append(card)

	# Remaining 24 cards go to stock, all face-down
	for i in range(deal_index, deck.size()):
		var c = deck[i]
		c.face_up = false
		stock.append(c)


func can_place_on(card: SolitaireCard, to_col: int) -> bool:
	if to_col < 0 or to_col >= TABLEAU_COUNT:
		return false
	var col_arr: Array = tableaus[to_col]
	if col_arr.is_empty():
		return true  # Any card can go on an empty column
	var dest_top: SolitaireCard = col_arr[col_arr.size() - 1]
	if not dest_top.face_up:
		return false
	# Spider rule: any suit is allowed; just rank must be one lower
	return dest_top.rank == card.rank + 1


func get_moveable_sequence_size(col: int, card_idx: int) -> int:
	var col_arr: Array = tableaus[col]
	if card_idx < 0 or card_idx >= col_arr.size():
		return 0
	if not (col_arr[card_idx] as SolitaireCard).face_up:
		return 0

	# Count how many cards from card_idx downward form a same-suit, descending run
	var count = 1
	for i in range(card_idx + 1, col_arr.size()):
		var prev: SolitaireCard = col_arr[i - 1]
		var curr: SolitaireCard = col_arr[i]
		if not curr.face_up:
			break
		if curr.rank != prev.rank - 1:
			break
		if curr.suit != prev.suit:
			break
		count += 1
	return count


func can_move_from(col: int, card_idx: int) -> bool:
	var col_arr: Array = tableaus[col]
	if card_idx < 0 or card_idx >= col_arr.size():
		return false
	var card: SolitaireCard = col_arr[card_idx]
	if not card.face_up:
		return false
	# The entire tail from card_idx must form a valid same-suit sequence
	var seq_size = get_moveable_sequence_size(col, card_idx)
	return seq_size == (col_arr.size() - card_idx)


func move_cards(from_col: int, card_idx: int, to_col: int) -> bool:
	if from_col < 0 or from_col >= TABLEAU_COUNT:
		return false
	if to_col < 0 or to_col >= TABLEAU_COUNT:
		return false
	var from_arr: Array = tableaus[from_col]
	if card_idx < 0 or card_idx >= from_arr.size():
		return false

	var moving_card: SolitaireCard = from_arr[card_idx]
	if not can_place_on(moving_card, to_col):
		return false
	if not can_move_from(from_col, card_idx):
		return false

	_history.append(_save_state())
	_redo_stack.clear()

	# Slice the cards to move
	var cards_to_move: Array = from_arr.slice(card_idx)

	# Remove from source column
	tableaus[from_col] = from_arr.slice(0, card_idx)

	# Add to destination column
	for c in cards_to_move:
		tableaus[to_col].append(c)

	# Flip new top of from_col if it's face-down and column is not empty
	var from_col_arr: Array = tableaus[from_col]
	if not from_col_arr.is_empty():
		var new_top: SolitaireCard = from_col_arr[from_col_arr.size() - 1]
		if not new_top.face_up:
			new_top.face_up = true

	# Check for completed sequences
	_check_sequences()
	card_moved.emit()
	return true


func deal_from_stock() -> bool:
	if stock.is_empty():
		return false

	_history.append(_save_state())
	_redo_stack.clear()

	# Deal one card to each column that has cards, filling empty columns left-to-right
	var dealt = false

	# First pass: deal to non-empty columns (left to right)
	for col in range(TABLEAU_COUNT):
		if stock.is_empty():
			break
		if not tableaus[col].is_empty():
			var card: SolitaireCard = stock.pop_back()
			card.face_up = true
			tableaus[col].append(card)
			dealt = true

	# Second pass: if stock still has cards and there are empty columns, fill them left-to-right
	for col in range(TABLEAU_COUNT):
		if stock.is_empty():
			break
		if tableaus[col].is_empty():
			var card: SolitaireCard = stock.pop_back()
			card.face_up = true
			tableaus[col].append(card)
			dealt = true

	# Check for completed sequences after dealing
	_check_sequences()
	if dealt:
		card_moved.emit()
	return dealt


func _check_sequences() -> void:
	for col in range(TABLEAU_COUNT):
		var col_arr: Array = tableaus[col]
		if col_arr.size() < 13:
			continue

		# Check if the last 13 cards form K→A (rank 13 down to 1), all same suit
		var start_idx = col_arr.size() - 13
		var base_card: SolitaireCard = col_arr[start_idx]
		var base_suit = base_card.suit
		var is_complete = true

		# First card must be rank 13 (King)
		if base_card.rank != 13:
			is_complete = false

		if is_complete:
			for i in range(1, 13):
				var c: SolitaireCard = col_arr[start_idx + i]
				if not c.face_up:
					is_complete = false
					break
				if c.suit != base_suit:
					is_complete = false
					break
				if c.rank != 13 - i:
					is_complete = false
					break

		if is_complete:
			# Emit signal before removing cards (so board can animate them)
			sequence_completed.emit(col, base_suit)

			# Remove those 13 cards
			tableaus[col] = col_arr.slice(0, col_arr.size() - 13)
			sequences_completed += 1

			# Flip the new top card if it's face-down
			var new_col: Array = tableaus[col]
			if not new_col.is_empty():
				var new_top: SolitaireCard = new_col[new_col.size() - 1]
				if not new_top.face_up:
					new_top.face_up = true

			if sequences_completed >= SEQUENCES_TO_WIN:
				game_completed.emit()
				game_won.emit()
				return

func is_completed() -> bool:
	"""Check if the game is completed (all sequences found)"""
	return sequences_completed >= SEQUENCES_TO_WIN


func has_valid_moves() -> bool:
	"""Check if there are any valid moves available"""
	if not stock.is_empty():
		return true
	for from_col in range(TABLEAU_COUNT):
		var col = tableaus[from_col]
		if col.is_empty():
			continue
		var card_idx = col.size() - 1
		# Find the first face-up card to try moving
		while card_idx >= 0:
			var card = col[card_idx]
			if not card.face_up:
				break
			for to_col in range(TABLEAU_COUNT):
				if from_col == to_col:
					continue
				if can_place_on(card, to_col):
					return true
			card_idx -= 1
	return false


func get_mirror_data() -> Dictionary:
	"""Get game state as mirror data for synchronization"""
	var deck_data = []
	# Tableau cards first (col 0, col 1, ..., col 6)
	for col in tableaus:
		for card in col:
			deck_data.append({
				"suit": card.suit,
				"rank": card.rank,
				"face_up": card.face_up,
				"stock": false
			})
	# Stock cards
	for card in stock:
		deck_data.append({
			"suit": card.suit,
			"rank": card.rank,
			"face_up": card.face_up,
			"stock": true
		})
	return {
		"deck": deck_data,
		"seed": _seed,
		"difficulty": _difficulty
	}


func new_game_mirror(mirror_data: Dictionary) -> void:
	"""Reconstruct game from mirror data"""
	var difficulty = mirror_data.get("difficulty", "Easy")
	_difficulty = difficulty
	sequences_completed = 0
	_history.clear()
	_redo_stack.clear()
	_start_time = Time.get_ticks_msec() / 1000.0

	# Reset tableaus and stock
	tableaus.clear()
	for _i in range(TABLEAU_COUNT):
		tableaus.append([])
	stock.clear()

	# Rebuild deck from mirror data
	var deck: Array = []
	for entry in mirror_data.get("deck", []):
		var c = SolitaireCard.new()
		c.suit = entry.get("suit", 0)
		c.rank = entry.get("rank", 0)
		c.face_up = entry.get("face_up", false)
		c.stock = entry.get("stock", false)
		deck.append(c)

	# Use common deal logic
	_deal_from_deck(deck)


func get_game_time() -> float:
	"""Get elapsed time in seconds since game start"""
	if _start_time == 0.0:
		return 0.0
	return Time.get_ticks_msec() / 1000.0 - _start_time

func get_save_data() -> Dictionary:
	"""Serialize game state for saving"""
	var tableaus_data: Array = []
	for col in tableaus:
		var col_data: Array = []
		for card in col:
			col_data.append({
				"suit": card.suit,
				"rank": card.rank,
				"face_up": card.face_up
			})
		tableaus_data.append(col_data)

	var stock_data: Array = []
	for card in stock:
		stock_data.append({
			"suit": card.suit,
			"rank": card.rank,
			"face_up": card.face_up
		})

	return {
		"tableaus": tableaus_data,
		"stock": stock_data,
		"sequences_completed": sequences_completed,
		"difficulty": _difficulty
	}

func restore_from_save(save_data: Dictionary) -> void:
	"""Restore game state from saved data"""
	if save_data.is_empty():
		return

	# Reconstruct tableaus
	tableaus.clear()
	for col_data in save_data.get("tableaus", []):
		var col: Array = []
		for card_data in col_data:
			var card = SolitaireCard.new()
			card.suit = card_data.get("suit", 0)
			card.rank = card_data.get("rank", 0)
			card.face_up = card_data.get("face_up", false)
			col.append(card)
		tableaus.append(col)

	# Reconstruct stock
	stock.clear()
	for card_data in save_data.get("stock", []):
		var card = SolitaireCard.new()
		card.suit = card_data.get("suit", 0)
		card.rank = card_data.get("rank", 0)
		card.face_up = card_data.get("face_up", false)
		stock.append(card)

	sequences_completed = save_data.get("sequences_completed", 0)
	_difficulty = save_data.get("difficulty", "Easy")
	_history.clear()
	_redo_stack.clear()
