extends Pile

class_name SpiderTableau

func _ready() -> void:
	super._ready()
	# Spider Solitaire tableau stacks downwards
	layout = PileDirection.DOWN
	# We want to allow movement of stacks, not just top card
	restrict_to_top_card = false
	allow_card_movement = true

func _card_can_be_added(cards: Array) -> bool:
	if cards.is_empty():
		return true # Can always add to empty column
		
	var top_dropped_card = cards[0]
	var top_dropped_rank = top_dropped_card.card_info["rank"]
	
	if _held_cards.is_empty():
		return true
		
	var bottom_card = _held_cards[-1]
	var bottom_rank = bottom_card.card_info["rank"]
	
	# In Spider Solitaire, any card can be placed on a card with rank + 1
	return bottom_rank == top_dropped_rank + 1

# Override to check if the card(s) being dragged can actually be moved
# In the framework, Card handles its own interaction, but we can influence it.
func update_card_interaction_states():
	if _held_cards.is_empty():
		return
		
	# All cards are non-interactable by default
	for card in _held_cards:
		card.can_be_interacted_with = false
		
	# Work backwards from the bottom to find the valid movable sequence
	var i = _held_cards.size() - 1
	var last_card = _held_cards[i]
	
	if not last_card.show_front:
		return # Cannot move face-down cards
		
	last_card.can_be_interacted_with = true
	
	while i > 0:
		var current = _held_cards[i]
		var above = _held_cards[i-1]
		
		if not above.show_front:
			break
			
		# Must be same suit and rank + 1
		if above.card_info["suit"] == current.card_info["suit"] and \
		   above.card_info["rank"] == current.card_info["rank"] + 1:
			above.can_be_interacted_with = true
			i -= 1
		else:
			break

func on_card_pressed(card: Card):
	# When a card is pressed, if it's part of a movable sequence,
	# we should also hold all cards below it in the stack.
	var index = _held_cards.find(card)
	if index == -1 or not card.can_be_interacted_with:
		return
		
	# Clear previous holding (should be empty but just in case)
	_holding_cards.clear()
	
	# Add the pressed card and all cards below it to holding
	for i in range(index, _held_cards.size()):
		_held_cards[i].set_holding()

func _update_target_positions() -> void:
	super._update_target_positions()
	update_card_interaction_states()

func on_card_move_done(_card: Card):
	# Check if we need to flip the new top card
	if not _held_cards.is_empty():
		var top_card = _held_cards[-1]
		if not top_card.show_front:
			top_card.show_front = true
	
	# Check for completed sequence (K to A of same suit)
	_check_for_completed_sequence()

func _check_for_completed_sequence():
	if _held_cards.size() < 13:
		return
		
	# Find if the bottom 13 cards form a complete sequence
	var sequence = []
	var suit = _held_cards[-1].card_info["suit"]
	
	for i in range(1, 14):
		var card = _held_cards[-i]
		if not card.show_front or card.card_info["suit"] != suit or card.card_info["rank"] != i:
			return
		sequence.append(card)
	
	# If we reach here, we have a complete sequence!
	# Remove it from the tableau
	print("Completed sequence of ", suit)
	for card in sequence:
		remove_card(card)
		card.queue_free() # Or move to a "completed" pile
	
	# Update UI and flip new top card
	update_card_ui()
	if not _held_cards.is_empty():
		_held_cards[-1].show_front = true
