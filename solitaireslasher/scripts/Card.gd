extends Resource
class_name SolitaireCard

enum Suit { CLUBS, DIAMONDS, HEARTS, SPADES }

@export var suit: Suit
@export var rank: int
@export var face_up: bool = false
@export var pile_id: int = -1
@export var stock: bool = false

var is_dragging: bool = false
var is_mouse_entered: bool = false
var previous_position: Vector2

func is_red() -> bool:
	return suit == Suit.DIAMONDS or suit == Suit.HEARTS

func short_name() -> String:
	var r := ""
	match rank:
		1:
			r = "A"
		11:
			r = "J"
		12:
			r = "Q"
		13:
			r = "K"
		_:
			r = str(rank)
	var s := ""
	match suit:
		Suit.CLUBS:
			s = "C"
		Suit.DIAMONDS:
			s = "D"
		Suit.HEARTS:
			s = "H"
		Suit.SPADES:
			s = "S"
	return r + s

func get_color() -> Color:
	if is_red():
		return Color.RED
	else:
		return Color.BLACK

func can_stack_on(other: SolitaireCard) -> bool:
	if other == null:
		return rank == 13  # King on empty pile
	return is_red() != other.is_red() and rank == other.rank - 1

func can_foundation_on(other: SolitaireCard) -> bool:
	if other == null:
		return rank == 1  # Ace on empty foundation
	return suit == other.suit and rank == other.rank + 1
