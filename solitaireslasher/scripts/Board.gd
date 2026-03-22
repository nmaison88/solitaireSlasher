extends Control
class_name Board

const CARD_SIZE = Vector2(120, 180)  # Increased size for better readability
const PILE_GAP_X = 22.0
const TABLEAU_GAP_Y = 28.0
const WASTE_FAN_X = 35.0  # Increased to show card corners and suit/rank

signal stock_clicked

var game
var multiplayer_manager

var _stock_count_label: Label
var _dragged_card_view: CardView
var _dragged_cards: Array = []
var _drop_zones: Dictionary = {}

# Reference to our project's Card class to avoid conflicts with Card Framework
const SolitaireCard = preload("res://scripts/Card.gd")

# Helper function to get card texture path from reference project naming
func _get_card_texture_path(card: SolitaireCard) -> String:
	var suit_name = ""
	match card.suit:
		0: suit_name = "Clubs"
		1: suit_name = "Diamonds"
		2: suit_name = "Hearts"
		3: suit_name = "Spades"
	
	var rank_name = ""
	match card.rank:
		1: rank_name = "A"
		11: rank_name = "J"
		12: rank_name = "Q"
		13: rank_name = "K"
		_: rank_name = str(card.rank)
	
	return "res://card_assets/card%s%s.png" % [suit_name, rank_name]

func _ready() -> void:
	_stock_count_label = Label.new()
	_stock_count_label.text = ""
	add_child(_stock_count_label)

	resized.connect(render)

func set_game(value) -> void:
	game = value
	if game:
		game.card_moved.connect(_on_game_card_moved)
		game.game_completed.connect(_on_game_completed)
	render()

func set_multiplayer_manager(value) -> void:
	multiplayer_manager = value
	if multiplayer_manager:
		multiplayer_manager.race_started.connect(_on_race_started)
		multiplayer_manager.race_ended.connect(_on_race_ended)

func _on_race_started() -> void:
	render()

func _on_race_ended(_winner_id: int, winner_name: String, time: float) -> void:
	print("Race ended! Winner: ", winner_name, " Time: ", time)

func _on_game_card_moved(_from_pile: String, _to_pile: String, _card_count: int) -> void:
	if multiplayer_manager and multiplayer_manager.is_multiplayer:
		multiplayer_manager.send_local_progress()
	render()

func _on_game_completed() -> void:
	if multiplayer_manager and multiplayer_manager.is_multiplayer:
		var _completion_time = game.get_game_time()
		multiplayer_manager.send_local_progress()

func _on_stock_pressed() -> void:
	if game == null:
		return
	game.draw_from_stock_3()
	stock_clicked.emit()
	render()

func render() -> void:
	if game == null:
		return

	# Clear existing card views and drop zones
	for child in get_children():
		if child != _stock_count_label:
			if is_instance_valid(child):
				child.queue_free()

	# Clear drop zones dictionary
	_drop_zones.clear()

	var margin_x = 18.0
	var margin_right = 80.0  # Extra padding on the right side to accommodate waste card fanning
	var top_y = 16.0
	var bottom_margin = 18.0
	var available_w = maxf(0.0, size.x - margin_x - margin_right)
	var available_h = maxf(0.0, size.y - top_y - bottom_margin)

	var piles_row_y = top_y
	var tableau_y = piles_row_y + CARD_SIZE.y + 26.0
	var tableau_h = maxf(0.0, available_h - (CARD_SIZE.y + 26.0))

	var col_gap = PILE_GAP_X
	var total_tableau_w = (CARD_SIZE.x * 7.0) + (col_gap * 6.0)
	var left_x = margin_x + maxf(0.0, (available_w - total_tableau_w) * 0.5)

	# Foundations on the left (4 piles)
	var foundation_start_x = left_x
	# Waste and stock on the right - waste fans out, so needs extra space before stock
	# Waste needs space for 3 cards fanning (2 * WASTE_FAN_X = 70px extra)
	var waste_pos = Vector2(left_x + (CARD_SIZE.x + col_gap) * 4.5, piles_row_y)
	var stock_pos = Vector2(left_x + (CARD_SIZE.x + col_gap) * 6.0, piles_row_y)

	# Update stock count label position
	if is_instance_valid(_stock_count_label):
		_stock_count_label.position = stock_pos + Vector2(0, CARD_SIZE.y + 4.0)
		_stock_count_label.text = str(game.stock.size())

	# Draw foundation slots first (left side) - darker for visibility
	for i in range(4):
		_draw_foundation_slot(Vector2(foundation_start_x + i * (CARD_SIZE.x + col_gap), piles_row_y), i)
	# Draw waste and stock slots (right side)
	_draw_slot(waste_pos)
	_draw_slot(stock_pos)

	# Draw foundations (left side)
	for i in range(4):
		_draw_foundation(game.foundations[i], Vector2(foundation_start_x + i * (CARD_SIZE.x + col_gap), piles_row_y), i)
	# Draw waste and stock (right side) - waste first (left), then stock (right)
	_draw_waste(waste_pos)
	_draw_stock(stock_pos)

	for col in range(7):
		var x = left_x + col * (CARD_SIZE.x + col_gap)
		_draw_tableau_column(game.tableau[col], Vector2(x, tableau_y), tableau_h, col)

func _on_test_button_pressed():
	print("TEST BUTTON PRESSED! Mouse input works!")

func _draw_slot(pos: Vector2) -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.10)
	bg.position = pos
	bg.size = CARD_SIZE
	add_child(bg)

func _draw_foundation_slot(pos: Vector2, suit_index: int) -> void:
	# Use suite logo placeholder images from card-framework reference
	# suit_index: 0=Clubs, 1=Diamonds, 2=Hearts, 3=Spades
	var suit_names = ["club", "diamond", "heart", "spade"]
	var placeholder_path = "res://addons/card-framework/freecell/assets/images/spots/foundation_%s_spot.png" % suit_names[suit_index]
	
	# Create a TextureRect to display the placeholder image
	var placeholder = TextureRect.new()
	placeholder.position = pos
	placeholder.custom_minimum_size = CARD_SIZE
	placeholder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	placeholder.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	if ResourceLoader.exists(placeholder_path):
		placeholder.texture = load(placeholder_path)
	else:
		# Fallback to dark background if placeholder not found
		var bg = ColorRect.new()
		bg.color = Color(0.0, 0.0, 0.0, 0.25)
		bg.position = pos
		bg.size = CARD_SIZE
		add_child(bg)
		return
	
	add_child(placeholder)

func _draw_stock(pos: Vector2) -> void:
	# Always create a clickable area for the stock pile, even when empty
	if game.stock.is_empty():
		# Create a clickable empty slot that shows when stock needs recycling
		var empty_slot = Button.new()
		empty_slot.position = pos
		empty_slot.size = CARD_SIZE
		empty_slot.flat = true
		
		# Add a semi-transparent background to show it's clickable
		var bg = ColorRect.new()
		bg.color = Color(0.2, 0.2, 0.2, 0.3)
		bg.size = CARD_SIZE
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty_slot.add_child(bg)
		
		empty_slot.pressed.connect(_on_stock_pressed)
		add_child(empty_slot)
		return
	
	# Create a Card Framework card for stock
	var stock_card = preload("res://addons/card-framework/card.tscn").instantiate()
	stock_card.position = pos
	stock_card.card_size = CARD_SIZE
	stock_card.show_front = false
	stock_card.can_be_interacted_with = false  # Disable Card Framework's interaction system
	
	# Disable Card Framework's built-in mouse handling
	stock_card.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Set textures on the proper child nodes
	var back_texture = load("res://card_assets/cardBack_blue2.png")
	stock_card.get_node("BackFace/TextureRect").texture = back_texture
	stock_card.get_node("FrontFace/TextureRect").texture = back_texture
	
	# Add our own mouse input handling
	stock_card.gui_input.connect(_on_stock_gui_input)
	add_child(stock_card)

func _on_stock_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_stock_pressed()

func _draw_waste(pos: Vector2) -> void:
	if game.waste.is_empty():
		return
	var start = max(0, game.waste.size() - 3)
	var i = 0
	for idx in range(start, game.waste.size()):
		var c = game.waste[idx]
		
		# Create a Card Framework card for waste cards
		var waste_card = preload("res://addons/card-framework/card.tscn").instantiate()
		waste_card.position = pos + Vector2(WASTE_FAN_X * float(i), 0)
		waste_card.card_size = CARD_SIZE
		waste_card.show_front = c.face_up
		waste_card.can_be_interacted_with = false  # Disable Card Framework's interaction system
		
		# Disable Card Framework's built-in mouse handling
		waste_card.mouse_filter = Control.MOUSE_FILTER_PASS
		
		# Set textures on the proper child nodes
		var back_texture = load("res://card_assets/cardBack_blue2.png")
		waste_card.get_node("BackFace/TextureRect").texture = back_texture
		
		if c.face_up:
			# Show card face using reference project naming
			var front_texture = load(_get_card_texture_path(c))
			waste_card.get_node("FrontFace/TextureRect").texture = front_texture
		else:
			# Show card back
			waste_card.get_node("FrontFace/TextureRect").texture = back_texture
		
		# Only make the top card clickable
		if idx == game.waste.size() - 1:
			# Create a custom signal handler for this specific card
			var card_ref = c
			waste_card.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					_on_waste_card_pressed(card_ref)
			)
		
		add_child(waste_card)
		i += 1

func _on_waste_card_pressed(card: SolitaireCard):
	# Try to move to foundation first - use card's suit to determine correct foundation
	var correct_foundation = card.suit  # 0=Clubs, 1=Diamonds, 2=Hearts, 3=Spades
	if game.can_place_on_foundation(card, correct_foundation):
		if game.move_to_foundation("waste", -1, correct_foundation):
			render()
			return
	
	# If not moved to foundation, try to move to tableau
	for i in range(7):
		if game.move_waste_to_tableau(i):
			render()
			return

func _draw_foundation(pile: Array, pos: Vector2, foundation_index: int) -> void:
	if pile.is_empty():
		_create_drop_zone("foundation_" + str(foundation_index), pos)
		return
	var c = pile[pile.size() - 1]
	
	# Create a Card Framework card for foundation
	var foundation_card = preload("res://addons/card-framework/card.tscn").instantiate()
	foundation_card.position = pos
	foundation_card.card_size = CARD_SIZE
	foundation_card.show_front = true
	foundation_card.can_be_interacted_with = false  # Disable Card Framework's interaction system
	
	# Disable Card Framework's built-in mouse handling
	foundation_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Set face texture using reference project naming
	var front_texture = load(_get_card_texture_path(c))
	foundation_card.get_node("FrontFace/TextureRect").texture = front_texture
	foundation_card.get_node("BackFace/TextureRect").texture = load("res://card_assets/cardBack_blue2.png")
	
	add_child(foundation_card)

func _draw_tableau_column(pile: Array, origin: Vector2, max_h: float, column_index: int) -> void:
	_create_drop_zone("tableau_" + str(column_index), origin)

	var y = origin.y
	for i in range(pile.size()):
		if max_h > 0.0 and (y - origin.y) > max_h:
			break
		var c = pile[i]
		
		# Create a Card Framework card for tableau cards
		var tableau_card = preload("res://addons/card-framework/card.tscn").instantiate()
		tableau_card.position = Vector2(origin.x, y)
		tableau_card.card_size = CARD_SIZE
		tableau_card.show_front = c.face_up
		tableau_card.can_be_interacted_with = false  # Disable Card Framework's interaction system
		
		# Disable Card Framework's built-in mouse handling
		tableau_card.mouse_filter = Control.MOUSE_FILTER_PASS
		
		# Set textures on the proper child nodes
		var back_texture = load("res://card_assets/cardBack_blue2.png")
		tableau_card.get_node("BackFace/TextureRect").texture = back_texture
		
		if c.face_up:
			# Show card face using reference project naming
			var front_texture = load(_get_card_texture_path(c))
			tableau_card.get_node("FrontFace/TextureRect").texture = front_texture
		else:
			# Show card back
			tableau_card.get_node("FrontFace/TextureRect").texture = back_texture
		
		# Only face-up cards can be clicked
		if c.face_up:
			# Create a custom signal handler for this specific card
			var card_ref = c
			tableau_card.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					_on_test_card_pressed(card_ref)
			)
		
		add_child(tableau_card)
		
		if c.face_up:
			y += TABLEAU_GAP_Y
		else:
			y += 10.0

func _on_test_card_pressed(card: SolitaireCard):
	# Try to move to foundation first - use card's suit to determine correct foundation
	var correct_foundation = card.suit  # 0=Clubs, 1=Diamonds, 2=Hearts, 3=Spades
	if game.can_place_on_foundation(card, correct_foundation):
		# Find which pile this card is in
		for j in range(7):
			if not game.tableau[j].is_empty() and game.tableau[j][-1] == card:
				if game.move_to_foundation("tableau", j, correct_foundation):
					render()
					return
	
	# If not moved to foundation, try to move to another tableau pile
	# Find which tableau pile this card is in
	var from_pile_index = -1
	var card_index_in_pile = -1
	for j in range(7):
		for k in range(game.tableau[j].size()):
			if game.tableau[j][k] == card:
				from_pile_index = j
				card_index_in_pile = k
				break
		if from_pile_index != -1:
			break
	
	if from_pile_index != -1 and card_index_in_pile != -1:
		# Try to move this card and all cards above it to another tableau pile
		var card_count = game.tableau[from_pile_index].size() - card_index_in_pile
		for to_pile_index in range(7):
			if to_pile_index != from_pile_index:
				if game.move_tableau_to_tableau(from_pile_index, to_pile_index, card_count):
					render()
					return

func _create_drop_zone(zone_name: String, pos: Vector2) -> void:
	var drop_zone = ColorRect.new()
	drop_zone.color = Color(0.0, 1.0, 0.0, 0.1)
	drop_zone.position = pos
	drop_zone.size = CARD_SIZE
	drop_zone.mouse_filter = Control.MOUSE_FILTER_PASS
	drop_zone.name = zone_name
	_drop_zones[zone_name] = drop_zone
	add_child(drop_zone)

func _on_card_clicked(card_view: CardView) -> void:
	print("Card clicked event received!")
	if not card_view.card:
		print("No card found in card view")
		return
	
	# Try auto-move to foundation if it's a valid move
	var card = card_view.card
	print("Clicked card: ", card.short_name(), " Rank: ", card.rank, " Suit: ", card.suit)
	
	# Check if it can go to foundation
	for i in range(4):
		print("Checking foundation ", i, " - can place: ", game.can_place_on_foundation(card, i))
		if game.can_place_on_foundation(card, i):
			# Try from waste first
			if game.waste.has(card) and card == game.waste[-1]:
				print("Trying to move from waste to foundation ", i)
				if game.move_to_foundation("waste", -1, i):
					render()
					return
			
			# Then try from tableau
			for j in range(7):
				if not game.tableau[j].is_empty() and game.tableau[j][-1] == card:
					print("Trying to move from tableau ", j, " to foundation ", i)
					if game.move_to_foundation("tableau", j, i):
						render()
						return

func _on_card_drag_started(card_view: CardView) -> void:
	_dragged_card_view = card_view
	_dragged_cards.clear()
	
	var card = card_view.card
	if not card:
		return
	
	# Determine which cards are being dragged
	for i in range(7):
		var pile = game.tableau[i]
		var card_index = pile.find(card)
		if card_index != -1:
			# Drag all cards from this position to the end of the pile
			_dragged_cards = pile.slice(card_index)
			break
	
	# Check if it's a waste card
	if game.waste.has(card) and card == game.waste[-1]:
		_dragged_cards = [card]

func _on_card_drag_ended(card_view: CardView, target_position: Vector2) -> void:
	if _dragged_card_view != card_view or _dragged_cards.is_empty():
		return
	
	var drop_zone = _get_drop_zone_at_position(target_position)
	var moved = false
	
	if drop_zone:
		var zone_name = drop_zone.name
		if zone_name.begins_with("foundation_"):
			var foundation_index = zone_name.split("_")[1].to_int()
			if _dragged_cards.size() == 1:
				var card = _dragged_cards[0]
				if _try_move_to_foundation(card, foundation_index):
					moved = true
		elif zone_name.begins_with("tableau_"):
			var tableau_index = zone_name.split("_")[1].to_int()
			if _try_move_to_tableau(tableau_index):
				moved = true
	
	if not moved:
		card_view.reset_position()
	
	_dragged_card_view = null
	_dragged_cards.clear()
	render()

func _get_drop_zone_at_position(pos: Vector2) -> ColorRect:
	for zone in _drop_zones.values():
		var zone_rect = Rect2(zone.global_position, zone.size)
		if zone_rect.has_point(pos):
			return zone
	return null

func _try_move_to_foundation(card: Card, clicked_foundation_index: int) -> bool:
	# Automatically determine the correct foundation based on card's suit
	# Foundation indices: 0=Clubs, 1=Diamonds, 2=Hearts, 3=Spades
	var card_suit = -1
	var from_pile = ""
	var from_index = -1
	
	print("DEBUG: Trying to move card with rank ", card.rank, " to foundation")
	
	# Find the card in tableau and get its suit
	for i in range(7):
		if not game.tableau[i].is_empty():
			var top_card = game.tableau[i][-1]
			# Match by rank to find the right card (since Card Framework card != Game card)
			if top_card.rank == card.rank and top_card.face_up:
				card_suit = top_card.suit
				from_pile = "tableau"
				from_index = i
				print("DEBUG: Found card in tableau ", i, " with suit ", card_suit)
				break
	
	# If not found in tableau, check waste
	if card_suit == -1 and game.waste.size() > 0:
		var top_waste = game.waste[-1]
		if top_waste.rank == card.rank:
			card_suit = top_waste.suit
			from_pile = "waste"
			from_index = -1
			print("DEBUG: Found card in waste with suit ", card_suit)
	
	if card_suit == -1:
		print("DEBUG: Card suit not found!")
		return false
	
	# Use the card's suit to determine correct foundation (0=Clubs, 1=Diamonds, 2=Hearts, 3=Spades)
	var correct_foundation_index = card_suit
	
	print("DEBUG: Moving to foundation index ", correct_foundation_index, " (clicked ", clicked_foundation_index, ")")
	
	# Move to the correct foundation based on suit
	return game.move_to_foundation(from_pile, from_index, correct_foundation_index)

func _try_move_to_tableau(tableau_index: int) -> bool:
	if _dragged_cards.is_empty():
		return false
	
	var first_card = _dragged_cards[0]
	
	# Find which tableau pile the cards are coming from
	for i in range(7):
		if game.tableau[i].has(first_card):
			var card_index = game.tableau[i].find(first_card)
			var card_count = game.tableau[i].size() - card_index
			return game.move_tableau_to_tableau(i, tableau_index, card_count)
	
	# Check if it's a waste card
	if game.waste.has(first_card) and first_card == game.waste[-1]:
		return game.move_waste_to_tableau(tableau_index)
	
	return false
