extends RefCounted
class_name Deck

static func new_standard_deck() -> Array[SolitaireCard]:
	var cards: Array[SolitaireCard] = []
	for suit in [0, 1, 2, 3]:  # CLUBS, DIAMONDS, HEARTS, SPADES
		for rank in range(1, 14):
			var c := SolitaireCard.new()
			c.suit = suit
			c.rank = rank
			c.face_up = false
			cards.append(c)
	return cards

static func shuffle(cards: Array[SolitaireCard], rng: RandomNumberGenerator) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cards[i]
		cards[i] = cards[j]
		cards[j] = tmp
