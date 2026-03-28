extends Node

class_name DeckGenerator

enum Difficulty { EASY, MEDIUM, HARD }

static func generate_deck(difficulty: Difficulty) -> Array[Dictionary]:
	var deck: Array[Dictionary] = []
	
	if difficulty == Difficulty.EASY or difficulty == Difficulty.MEDIUM:
		# 4 sets of 13 Spades
		for i in range(4):
			for rank in range(1, 14):
				deck.append({
					"suit": "Spades",
					"rank": rank,
					"name": "spades_%d_%d" % [rank, i],
					"front_image": _get_image_name("Spades", rank)
				})
	else:
		# Standard 4 suits
		var suits = ["Spades", "Hearts", "Diamonds", "Clubs"]
		for suit in suits:
			for rank in range(1, 14):
				deck.append({
					"suit": suit,
					"rank": rank,
					"name": "%s_%d" % [suit.to_lower(), rank],
					"front_image": _get_image_name(suit, rank)
				})
	
	deck.shuffle()
	return deck

static func _get_image_name(suit: String, rank: int) -> String:
	var rank_str = str(rank)
	if rank == 1: rank_str = "A"
	elif rank == 11: rank_str = "J"
	elif rank == 12: rank_str = "Q"
	elif rank == 13: rank_str = "K"
	
	return "card%s%s.png" % [suit, rank_str]
