extends Pile
class_name SpiderTableau

signal sequence_completed(suit: String)

## Set to true after initial deal so on_card_move_done flips cards normally
var _setup_done: bool = false

func _ready() -> void:
	super._ready()
	layout = PileDirection.DOWN
	restrict_to_top_card = false
	allow_card_movement = true
	stack_display_gap = 28
	max_stack_display = 20

# ── Drop rule ─────────────────────────────────────────────────────────────────

func _card_can_be_added(cards: Array) -> bool:
	if cards.is_empty():
		return true

	# Find the top-of-sequence card (highest rank = pressed/top card of dragged stack)
	var top_card = cards[0]
	for c in cards:
		if c.card_info["rank"] > top_card.card_info["rank"]:
			top_card = c

	if _held_cards.is_empty():
		return true

	var bottom_rank = _held_cards[-1].card_info["rank"]
	return bottom_rank == top_card.card_info["rank"] + 1

# ── Layout ────────────────────────────────────────────────────────────────────

func _update_target_positions() -> void:
	# Replicates Pile logic but deliberately does NOT touch card.show_front
	# so manual face-up/face-down state is preserved.
	var last_index = _held_cards.size() - 1
	if last_index < 0:
		last_index = 0
	var last_offset = _calculate_offset(last_index)

	if enable_drop_zone and align_drop_zone_with_top_card and drop_zone != null:
		drop_zone.change_sensor_position_with_offset(last_offset)

	for i in range(_held_cards.size()):
		var card = _held_cards[i]
		var target_pos = position + _calculate_offset(i)
		card.move(target_pos, 0)
		card.can_be_interacted_with = true  # will be refined below

	update_card_interaction_states()

func update_card_interaction_states() -> void:
	if _held_cards.is_empty():
		return

	for card in _held_cards:
		card.can_be_interacted_with = false

	# Walk from bottom upward finding the longest same-suit descending run
	var i = _held_cards.size() - 1
	var last_card = _held_cards[i]

	if not last_card.show_front:
		return

	last_card.can_be_interacted_with = true

	while i > 0:
		var current = _held_cards[i]
		var above   = _held_cards[i - 1]

		if not above.show_front:
			break

		if above.card_info["suit"] == current.card_info["suit"] and \
		   above.card_info["rank"] == current.card_info["rank"] + 1:
			above.can_be_interacted_with = true
			i -= 1
		else:
			break

# ── Drag handling ─────────────────────────────────────────────────────────────

func on_card_pressed(card: Card) -> void:
	var index = _held_cards.find(card)
	if index == -1 or not card.can_be_interacted_with:
		return

	_holding_cards.clear()

	# Add cards from the bottom of the column up to (but NOT including) the
	# pressed card, in reverse order.  The pressed card itself will be appended
	# last when it enters the HOLDING state → _holding_cards ends up as
	# [bottom, ..., above_pressed, pressed].  _move_cards iterates in reverse
	# so cards land on the target in correct top→bottom order.
	for i in range(_held_cards.size() - 1, index, -1):
		_held_cards[i].set_holding()

# ── Card move callbacks ───────────────────────────────────────────────────────

func remove_card(card: Card) -> bool:
	var result = super.remove_card(card)
	# When a card is taken from this pile during play, flip the new bottom card face-up.
	# (Remaining cards don't re-animate, so on_card_move_done won't fire for the source.)
	if result and _setup_done and not _held_cards.is_empty():
		var new_bottom = _held_cards[-1]
		if not new_bottom.show_front:
			new_bottom.show_front = true
			update_card_ui()
	return result

func on_card_move_done(_card: Card) -> void:
	if not _setup_done:
		return  # Ignore animation callbacks during the initial deal

	# Flip the new bottom card face-up when the previous bottom was moved away
	if not _held_cards.is_empty():
		var top = _held_cards[-1]
		if not top.show_front:
			top.show_front = true

	_check_for_completed_sequence()

func _check_for_completed_sequence() -> void:
	if _held_cards.size() < 13:
		return

	# Bottom 13 cards must form K→A of the same suit
	var suit = _held_cards[-1].card_info["suit"]
	var sequence: Array[Card] = []

	for i in range(1, 14):
		var card = _held_cards[-i]
		if not card.show_front \
		   or card.card_info["suit"] != suit \
		   or card.card_info["rank"] != i:
			return
		sequence.append(card)

	# Complete sequence found — remove cards and notify the game
	for card in sequence:
		remove_card(card)
		card.queue_free()

	update_card_ui()

	if not _held_cards.is_empty():
		_held_cards[-1].show_front = true

	sequence_completed.emit(suit)
