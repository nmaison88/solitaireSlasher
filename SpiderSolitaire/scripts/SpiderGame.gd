extends Node

class_name SpiderGame

@onready var card_manager: CardManager = $CardManager
@onready var tableau_container: HBoxContainer = $TableauContainer
@onready var stock_pile: Pile = $StockPile

@export var difficulty: DeckGenerator.Difficulty = DeckGenerator.Difficulty.EASY

var factory: SpiderCardFactory
var tableaus: Array[SpiderTableau] = []
var deck: Array[Dictionary] = []

func _ready() -> void:
	# Wait for CardManager to initialize factory
	await get_tree().process_frame
	factory = card_manager.card_factory as SpiderCardFactory
	_setup_game()

func _setup_game() -> void:
	# Generate deck
	deck = DeckGenerator.generate_deck(difficulty)
	
	# Reference tableaus
	tableaus.clear()
	for child in tableau_container.get_children():
		if child is SpiderTableau:
			tableaus.append(child)
	
	# Initial deal
	# Spider Solitaire (1 deck, 52 cards)
	# 10 columns
	# Let's do 4 cards in each of 10 columns = 40 cards.
	# Remaining 12 in stock.
	
	for i in range(40):
		var tableau = tableaus[i % tableaus.size()]
		var card_data = deck.pop_back()
		var card = factory.create_card_from_data(card_data, tableau)
		
		# In Spider, only the top card is face-up at start
		if i >= 40 - tableaus.size():
			card.show_front = true
		else:
			card.show_front = false
		
		tableau.update_card_ui()

	# Remaining cards to stock
	while not deck.is_empty():
		var card_data = deck.pop_back()
		var card = factory.create_card_from_data(card_data, stock_pile)
		card.show_front = false
	
	stock_pile.update_card_ui()
	
	# Connect stock pile click
	# Since Pile doesn't have a 'pressed' signal normally, we'll check its cards
	# or add a button/click area.
	# For now, let's assume we can click the StockPile control.
	stock_pile.gui_input.connect(_on_stock_pile_gui_input)

func _on_stock_pile_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		deal_from_stock()

func deal_from_stock():
	if stock_pile.get_card_count() == 0:
		return
		
	# Rules check: cannot deal if any column is empty
	for tableau in tableaus:
		if tableau.get_card_count() == 0:
			print("Cannot deal with empty columns!")
			return

	# Deal 1 card to each column
	var count = min(tableaus.size(), stock_pile.get_card_count())
	var cards_to_deal = stock_pile.get_top_cards(count)
	
	for i in range(count):
		var card = cards_to_deal[i]
		var tableau = tableaus[i]
		stock_pile.remove_card(card)
		tableau.add_card(card)
		card.show_front = true
		tableau.update_card_ui()
	
	stock_pile.update_card_ui()
