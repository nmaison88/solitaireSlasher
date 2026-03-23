extends Control
class_name CardView

signal card_clicked(card_view: CardView)
signal card_drag_started(card_view: CardView)
signal card_drag_ended(card_view: CardView, target_position: Vector2)

@onready var _texture_rect: TextureRect = $TextureRect
@onready var _card_back: TextureRect = $CardBack

var card: SolitaireCard
var is_dragging: bool = false
var drag_offset: Vector2
var original_position: Vector2
var z_index_when_dragging: int = 100
var _tween: Tween  # For smooth animations

func set_card(value: SolitaireCard) -> void:
	card = value
	_refresh()

func _ready() -> void:
	_refresh()
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _refresh() -> void:
	if not is_node_ready() or not card:
		return
	
	if card.face_up:
		# Show card face using reference project's mapping
		var texture_path = ""
		if card.stock:
			texture_path = "res://card_assets/Back1.png"
		else:
			# Reference project uses: {value}.{suit}.png where value is 1-13 and suit is 1-4
			var value = card.rank  # 1-13
			var suit = 0
			match card.suit:
				0: suit = 1  # CLUBS
				1: suit = 2  # DIAMONDS
				2: suit = 3  # HEARTS
				3: suit = 4  # SPADES
			
			texture_path = "res://card_assets/%d.%d.png" % [value, suit]
		
		var texture = load(texture_path)
		if texture:
			_texture_rect.texture = texture
			_texture_rect.show()
			_card_back.hide()
	else:
		# Show card back
		_texture_rect.hide()
		_card_back.texture = load("res://card_assets/Back1.png")
		_card_back.show()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_card_pressed()
			else:
				_on_card_released()
	elif event is InputEventMouseMotion and is_dragging:
		_on_card_dragged(event)

func _on_card_pressed() -> void:
	if card and card.face_up and not card.stock:
		original_position = global_position
		drag_offset = global_position - get_global_mouse_position()
		is_dragging = true
		z_index = z_index_when_dragging
		card_drag_started.emit(self)

func _card_clicked() -> void:
	card_clicked.emit(self)

func _on_card_released() -> void:
	if is_dragging:
		is_dragging = false
		z_index = 0
		card_drag_ended.emit(self, get_global_mouse_position())
	else:
		_card_clicked()

func _on_card_dragged(_event: InputEventMouseMotion) -> void:
	global_position = get_global_mouse_position() + drag_offset

func _on_mouse_entered() -> void:
	if card:
		card.is_mouse_entered = true

func _on_mouse_exited() -> void:
	if card:
		card.is_mouse_entered = false

func reset_position() -> void:
	animate_to_position(original_position)
	z_index = 0

func animate_to_position(target_pos: Vector2, duration: float = 0.2) -> void:
	"""Smoothly animate card to target position"""
	# Cancel any existing tween
	if _tween:
		_tween.kill()
	
	# Create new tween
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	
	# Animate position
	_tween.tween_property(self, "global_position", target_pos, duration)

func move_to_position_instant(target_pos: Vector2) -> void:
	"""Move card instantly without animation (for initial setup)"""
	global_position = target_pos

func get_drag_data() -> SolitaireCard:
	return card if is_dragging else null
