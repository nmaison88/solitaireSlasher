extends Node

## Script to generate JSON card definitions for all playing cards

func _ready():
	generate_all_card_json()
	print("Card JSON files generated successfully!")
	get_tree().quit()

func generate_all_card_json():
	var suits = ["Clubs", "Diamonds", "Hearts", "Spades"]
	var ranks = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
	var rank_values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
	
	for suit in suits:
		for i in range(ranks.size()):
			var rank = ranks[i]
			var rank_value = rank_values[i]
			var card_name = "%s_%s" % [suit.to_lower(), rank.to_lower()]
			var image_name = "card%s%s.png" % [suit, rank]
			
			var card_data = {
				"name": card_name,
				"front_image": image_name,
				"back_image": "cardBack_blue2.png",
				"suit": suit,
				"rank": rank_value
			}
			
			var json_string = JSON.stringify(card_data, "\t")
			var file_path = "res://card_info/%s.json" % card_name
			
			var file = FileAccess.open(file_path, FileAccess.WRITE)
			if file:
				file.store_string(json_string)
				file.close()
			else:
				print("Error creating file: ", file_path)
