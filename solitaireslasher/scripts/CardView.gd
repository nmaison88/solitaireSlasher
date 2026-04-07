extends Control
class_name CardView

signal card_clicked(card_view: CardView)
signal card_drag_started(card_view: CardView)
signal card_drag_ended(card_view: CardView, target_position: Vector2)
signal card_drag_moved(card_view: CardView, new_position: Vector2)

@onready var _texture_rect: TextureRect = $TextureRect
@onready var _card_back: TextureRect = $CardBack

static var _corner_shader: Shader = null

var card: SolitaireCard
var is_dragging: bool = false
var original_position: Vector2
var drag_offset: Vector2
var z_index_when_dragging: int = 100
var mouse_press_position: Vector2
var drag_threshold: float = 5.0  # Minimum movement to consider as drag
var _tween: Tween  # For smooth animations
var _current_touch_index: int = -1  # Track active touch finger for iPhone

func set_card(value: SolitaireCard) -> void:
	card = value
	_refresh()

func _ready() -> void:
	_apply_rounded_corners()
	_refresh()
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _apply_rounded_corners() -> void:
	if _corner_shader == null:
		_corner_shader = Shader.new()
		_corner_shader.code = """
shader_type canvas_item;
uniform vec2 card_size = vec2(120.0, 160.0);
uniform float radius = 10.0;
uniform float border_width = 3.5;
void fragment() {
	vec2 px = UV * card_size;
	vec2 half = card_size * 0.5;
	vec2 d = abs(px - half) - (half - vec2(radius));
	float dist = length(max(d, vec2(0.0))) - radius;
	float a = 1.0 - smoothstep(-1.0, 1.0, dist);
	COLOR = texture(TEXTURE, UV);
	// Dark border: ramps from 0 deep inside to 1 at the edge
	float border = smoothstep(-(border_width + 1.5), 0.0, dist) * a;
	COLOR.rgb = mix(COLOR.rgb, vec3(0.0), border * 0.75);
	COLOR.a *= a;
}
"""
	var mat = ShaderMaterial.new()
	mat.shader = _corner_shader
	_texture_rect.material = mat
	var mat2 = ShaderMaterial.new()
	mat2.shader = _corner_shader
	_card_back.material = mat2

func _refresh() -> void:
	if not is_node_ready() or not card:
		return
	
		
	if card.face_up:
		# Show card face using new card asset format (same as Board.gd)
		var texture_path = ""
		# Note: card.stock is only for cards still in stock pile, not for drawn cards
		if card.stock:
			texture_path = "res://card_assets/cardBack_blue2.png"
		else:
			var rank_name = ""
			match card.rank:
				1:  rank_name = "A"
				11: rank_name = "J"
				12: rank_name = "Q"
				13: rank_name = "K"
				_:  rank_name = str(card.rank)

			# Spades files have inconsistent casing: face cards use "Spades",
			# Ace and number cards use "spades" (lowercase)
			var suit_name = ""
			match card.suit:
				0: suit_name = "Clubs"
				1: suit_name = "Diamonds"
				2: suit_name = "Hearts"
				3: suit_name = "Spades" if card.rank >= 11 else "spades"

			texture_path = "res://card_assets/Alternative-Face-Deck/card%s%s.png" % [suit_name, rank_name]
		
		var texture = load(texture_path)
		if texture:
			_texture_rect.texture = texture
			_texture_rect.show()
			_card_back.hide()
		else:
			_texture_rect.hide()
			_card_back.texture = load("res://card_assets/cardBack_blue2.png")
			_card_back.show()
	else:
		# Show card back using new format
		_texture_rect.hide()
		_card_back.texture = load("res://card_assets/cardBack_blue2.png")
		_card_back.show()

func _on_gui_input(event: InputEvent) -> void:
	# Touch events — primary for iPhone. Handle first to block emulated mouse events.
	if event is InputEventScreenTouch:
		if event.pressed and _current_touch_index == -1:
			_current_touch_index = event.index
			_on_press_started(event.position)
		elif not event.pressed and event.index == _current_touch_index:
			_current_touch_index = -1
			_on_press_ended(event.position)
		get_viewport().set_input_as_handled()
		return
	elif event is InputEventScreenDrag:
		if event.index == _current_touch_index:
			_on_motion(event.position)
		get_viewport().set_input_as_handled()
		return

	# Mouse events — only process when no active touch (avoids double-processing emulation)
	if _current_touch_index != -1:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press_started(event.global_position)
		else:
			_on_press_ended(event.global_position)
	elif event is InputEventMouseMotion:
		_on_motion(event.global_position)

func _on_press_started(global_pos: Vector2) -> void:
	if card and card.face_up and not card.stock:
		original_position = global_position
		# Store offset as center of card relative to finger
		drag_offset = global_position - global_pos
		mouse_press_position = global_pos

func _on_press_ended(global_pos: Vector2) -> void:
	if mouse_press_position == Vector2.ZERO:
		return
	if is_dragging:
		is_dragging = false
		z_index = 0
		card_drag_ended.emit(self, global_pos)
	else:
		var dist = mouse_press_position.distance_to(global_pos)
		if dist > drag_threshold:
			card_drag_ended.emit(self, global_pos)
		else:
			card_clicked.emit(self)
	mouse_press_position = Vector2.ZERO

func _on_motion(global_pos: Vector2) -> void:
	if mouse_press_position == Vector2.ZERO:
		return
	if not is_dragging:
		if mouse_press_position.distance_to(global_pos) > drag_threshold:
			is_dragging = true
			card_drag_started.emit(self)
			# Recalculate drag_offset at start of drag for accurate tracking
			drag_offset = original_position - mouse_press_position
			print("DEBUG: CardView drag_started at ", global_pos, " original_position: ", original_position)
	if is_dragging:
		# Track movement relative to press position, not absolute global position
		# This ensures 1-to-1 finger tracking without drift
		var delta = global_pos - mouse_press_position
		global_position = original_position + delta
		card_drag_moved.emit(self, global_position)  # Emit global_position not local position

func _card_clicked() -> void:
	card_clicked.emit(self)

func _on_mouse_entered() -> void:
	if card:
		card.is_mouse_entered = true

func _on_mouse_exited() -> void:
	if card:
		card.is_mouse_entered = false

func reset_position() -> void:
	animate_to_position(original_position)
	z_index = 0

func animate_to_position(target_pos: Vector2, duration: float = 0.28) -> void:
	"""Clean card animation using reparent solution for Container interference"""
	if _tween and _tween.is_valid():
		_tween.kill()

	var original_parent := get_parent()
	var scene_root := get_tree().root.get_child(0)

	# Escape the Container layout
	if original_parent is Container:
		var saved := global_position
		original_parent.remove_child(self)
		scene_root.add_child(self)
		global_position = saved

	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "global_position", target_pos, duration)

	await _tween.finished

	# Return home
	if get_parent() == scene_root:
		scene_root.remove_child(self)
		original_parent.add_child(self)

func snap_back_to(target_pos: Vector2) -> void:
	"""For rejected drops — slight overshoot back to origin"""
	if _tween and _tween.is_valid():
		_tween.kill()

	var original_parent := get_parent()
	var scene_root := get_tree().root.get_child(0)
	if original_parent is Container:
		var saved := global_position
		original_parent.remove_child(self)
		scene_root.add_child(self)
		global_position = saved

	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_BACK)  # The overshoot easing
	_tween.tween_property(self, "global_position", target_pos, 0.3)

	await _tween.finished
	if get_parent() == scene_root:
		scene_root.remove_child(self)
		original_parent.add_child(self)

func flip_to_face_up() -> void:
	"""Scale-X midpoint swap flip — matches real card turn-over feel"""
	if _tween and _tween.is_valid():
		_tween.kill()

	# Squish
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "scale:x", 0.0, 0.11)
	await _tween.finished

	# Swap textures while invisible
	card.face_up = true
	_refresh()

	# Expand
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "scale:x", 1.0, 0.11)
	await _tween.finished

func move_to_position_instant(target_pos: Vector2) -> void:
	"""Move card instantly without animation (for initial setup)"""
	global_position = target_pos

func get_drag_data() -> SolitaireCard:
	return card if is_dragging else null
