extends Pile
class_name TableauPile

## Tableau pile for Solitaire - accepts cards in descending order with alternating colors

func _card_can_be_added(cards: Array) -> bool:
	if cards.is_empty():
		return false
	
	var first_card = cards[0] as Card
	if first_card == null:
		return false
	
	# Get first card properties
	var card_suit = first_card.get_meta("suit", "")
	var card_rank = first_card.get_meta("rank", 0)
	var card_color = _get_card_color(card_suit)
	
	# If tableau is empty, only accept King
	if _held_cards.is_empty():
		return card_rank == 13
	
	# Get top card of tableau
	var top_card = _held_cards[-1] as Card
	var top_suit = top_card.get_meta("suit", "")
	var top_rank = top_card.get_meta("rank", 0)
	var top_color = _get_card_color(top_suit)
	
	# Must be alternating color and descending rank
	return card_color != top_color and card_rank == top_rank - 1

func _get_card_color(suit: String) -> String:
	if suit == "Hearts" or suit == "Diamonds":
		return "red"
	else:
		return "black"
