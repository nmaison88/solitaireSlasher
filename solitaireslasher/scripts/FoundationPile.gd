extends Pile
class_name FoundationPile

## Foundation pile for Solitaire - accepts cards in ascending order of same suit starting with Ace

func _card_can_be_added(cards: Array) -> bool:
	# Only accept single cards
	if cards.size() != 1:
		return false
	
	var card = cards[0] as Card
	if card == null:
		return false
	
	# Get card properties from metadata
	var card_suit = card.get_meta("suit", "")
	var card_rank = card.get_meta("rank", 0)
	
	# If foundation is empty, only accept Ace
	if _held_cards.is_empty():
		return card_rank == 1
	
	# Get top card of foundation
	var top_card = _held_cards[-1] as Card
	var top_suit = top_card.get_meta("suit", "")
	var top_rank = top_card.get_meta("rank", 0)
	
	# Must be same suit and next rank in sequence
	return card_suit == top_suit and card_rank == top_rank + 1
