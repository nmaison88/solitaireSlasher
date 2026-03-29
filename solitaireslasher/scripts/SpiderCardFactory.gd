extends CardFactory
class_name SpiderCardFactory

@export var default_card_scene: PackedScene
@export var card_asset_dir: String = "res://card_assets/Alternative-Face-Deck"
@export var back_image: Texture2D

func create_card_from_data(card_data: Dictionary, target: CardContainer) -> Card:
	var card = default_card_scene.instantiate() as Card

	card.card_info = card_data
	card.card_name = card_data["name"]
	card.card_size = card_size
	card.size = card_size  # Give the Control node a hit area; card.tscn defaults to (0,0)

	var front_texture = load(card_asset_dir + "/" + card_data["front_image"]) as Texture2D

	# Card must be in scene tree before set_faces() is called
	var cards_node = target.get_node_or_null("Cards")
	if cards_node:
		cards_node.add_child(card)
	else:
		target.add_child(card)

	target.add_card(card)
	card.set_faces(front_texture, back_image)

	return card
