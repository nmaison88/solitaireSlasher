extends Node
class_name SpiderGame

signal game_won

const TABLEAU_COUNT = 7
const SEQUENCES_TO_WIN = 4

var tableaus: Array = []       # Array[Array[SolitaireCard]], index 0=bottom, -1=top
var stock: Array = []          # Array[SolitaireCard]
var sequences_completed: int = 0
var _difficulty: String = "Easy"

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

func new_game(difficulty_string: String = "Easy") -> void:
	_difficulty = difficulty_string
	sequences_completed = 0
	_history.clear()
	_redo_stack.clear()

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

	# Shuffle
	deck.shuffle()

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
				game_won.emit()
				return
