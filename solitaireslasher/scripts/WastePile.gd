extends Pile
class_name WastePile

## Waste pile for Solitaire - accepts cards from stock, only top card can be moved

func _ready():
	super._ready()
	# Configure waste pile settings
	card_face_up = true
	restrict_to_top_card = true
	allow_card_movement = true
	layout = PileDirection.RIGHT
	stack_display_gap = 18.0

func _card_can_be_added(cards: Array) -> bool:
	# Waste pile only accepts cards from stock pile (programmatically)
	# Players cannot drag cards to waste pile
	return false
