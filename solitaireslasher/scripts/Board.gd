extends Control
class_name Board

const CARD_SIZE = Vector2(120, 160)  # Match actual card display size
const PILE_GAP_X = 24.0  # Preferred gap; _get_col_gap() reduces this on narrow screens
const TABLEAU_GAP_Y = 65.0  # Increased spacing to show suit and rank on stacked cards (was 45.0)
const WASTE_FAN_X = 35.0  # Increased to show card corners and suit/rank
const FACE_DOWN_GAP_Y = 30.0  # Spacing for face-down cards (was hardcoded 10.0)
const WASTE_SPREAD = 42.0  # Horizontal gap between fanned waste cards

signal stock_clicked
signal stock_count_changed(count: int)

@onready var _stock_count_label: Label = get_node_or_null("StockCountLabel")

var game: Game
var multiplayer_manager: MultiplayerGameManager
var animating_card_view: CardView
var _drop_zones: Dictionary = {}
var top_card_info: Dictionary = {}
var _dragged_card_view: CardView
var _dragged_cards: Array = []
var _dragged_card_views: Array[CardView] = []  # Track all CardViews being dragged
var _dragged_card_offsets: Dictionary = {}  # Store relative positions for stack dragging
var _last_render_frame: int = -1
var _stock_button: Button
var _animation_duration: float = 0.28
var _animating: bool = false
var _win_overlay: Control = null

const WIN_MESSAGES = [
	"YOU WIN!", "NICE JOB!", "MAN YOU'RE GOOD!",
	"GENIUS ALERT!", "ABSOLUTELY NAILED IT!",
	"FLAWLESS VICTORY!", "DEAL ME AGAIN!",
	"SOLITAIRE LEGEND!", "TOO EASY!", "CARD SHARK!",
	"YOUR CARDS ARE WILD!", "UNSTOPPABLE!"
]

func _get_col_gap() -> float:
	# Reduce gap from the preferred PILE_GAP_X so the 7-column layout + stock
	# always fits within the screen width (right edge = size.x - margin).
	var margin_x = 12.0
	var max_gap = (size.x - 2.0 * margin_x - 7.0 * CARD_SIZE.x) / 6.0
	return clampf(max_gap, 8.0, PILE_GAP_X)

func _get_left_x() -> float:
	var margin_x = 12.0
	var col_gap = _get_col_gap()
	var total_w = 7.0 * CARD_SIZE.x + 6.0 * col_gap
	var available_w = maxf(0.0, size.x - 2.0 * margin_x)
	return margin_x + maxf(0.0, (available_w - total_w) * 0.5)

func _waste_card_x(anchor_x: float, i: int, card_count: int) -> float:
	# Mirror the positioning logic in _draw_waste so all helpers agree
	var total_width = (card_count - 1) * WASTE_SPREAD
	var center_offset = total_width * 0.5
	var card_offset = (card_count - 1 - i) * WASTE_SPREAD - center_offset
	return anchor_x - card_offset

func _get_foundation_pos(foundation_index: int) -> Vector2:
	return Vector2(_get_left_x() + foundation_index * (CARD_SIZE.x + _get_col_gap()), 16.0)

func _get_tableau_card_pos(column: int, card_idx_in_pile: int) -> Vector2:
	var x = _get_left_x() + column * (CARD_SIZE.x + _get_col_gap())
	var y = 16.0 + CARD_SIZE.y + 44.0
	for i in range(card_idx_in_pile):
		if i < game.tableau[column].size() and game.tableau[column][i].face_up:
			y += TABLEAU_GAP_Y
		else:
			y += FACE_DOWN_GAP_Y
	return Vector2(x, y)

# Reference to our project's Card class to avoid conflicts with Card Framework
const SolitaireCard = preload("res://scripts/Card.gd")

# Helper function to get card texture path from reference project naming
func _get_card_texture_path(card: SolitaireCard) -> String:
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

	return "res://card_assets/Alternative-Face-Deck/card%s%s.png" % [suit_name, rank_name]

func _ready() -> void:
	_stock_count_label = Label.new()
	_stock_count_label.text = ""
	_stock_count_label.visible = false
	add_child(_stock_count_label)

	resized.connect(render)
	mouse_filter = Control.MOUSE_FILTER_PASS
	z_index = 1000

func _process(_delta: float) -> void:
	# Keep stack cards locked to the dragged card's position every frame — eliminates lag
	if _dragged_card_view == null or _dragged_card_views.is_empty():
		return
	for stack_card_view in _dragged_card_views:
		if stack_card_view == _dragged_card_view:
			continue
		if not is_instance_valid(stack_card_view):
			continue
		var offset = _dragged_card_offsets.get(stack_card_view, Vector2.ZERO)
		stack_card_view.global_position = _dragged_card_view.global_position + offset
	
	# Board is ready for game setup
	
	

# Remove Board GUI input to allow CardViews to receive mouse events
# func _gui_input(event: InputEvent) -> void:
# 	print("DEBUG: Board._gui_input called! Event: ", event)
# 	if event is InputEventMouseButton and event.pressed:
# 		print("DEBUG: Board received click at: ", event.position)

func set_game(value) -> void:
	game = value
	if game:
		game.card_moved.connect(_on_game_card_moved)
		game.game_completed.connect(_on_game_completed)
		_play_deal_animation()

func set_multiplayer_manager(value) -> void:
	multiplayer_manager = value
	if multiplayer_manager:
		# Check if signals are already connected before connecting
		if not multiplayer_manager.race_started.is_connected(_on_race_started):
			multiplayer_manager.race_started.connect(_on_race_started)
		if not multiplayer_manager.race_ended.is_connected(_on_race_ended):
			multiplayer_manager.race_ended.connect(_on_race_ended)

func _on_race_started() -> void:
	render()

func _on_race_ended(_winner_id: int, winner_name: String, time: float) -> void:
	print("Race ended! Winner: ", winner_name, " Time: ", time)

func _await_animation_completion() -> void:
	"""Wait for animation to complete before updating game state"""
	if multiplayer_manager and multiplayer_manager.is_multiplayer:
		multiplayer_manager.send_local_progress()
	# DISABLED delayed rendering to preserve Card Framework animation
	print("🚫 DELAYED RENDERING DISABLED - preserving Card Framework animation")

func _render_after_animation() -> void:
	"""Delay render until after card animation completes"""
	await get_tree().create_timer(_animation_duration).timeout
	render()

func _on_game_card_moved(_from_pile: String, _to_pile: String, _card_count: int) -> void:
	pass

func _on_game_completed() -> void:
	if multiplayer_manager and multiplayer_manager.is_multiplayer:
		var _completion_time = game.get_game_time()
		multiplayer_manager.send_local_progress()
	_show_win_screen()

func _show_win_screen() -> void:
	if is_instance_valid(_win_overlay):
		return

	var overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 10000
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_win_overlay = overlay
	add_child(overlay)

	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.05, 0.15, 0.88)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)

	var msg_label = Label.new()
	msg_label.text = WIN_MESSAGES[randi() % WIN_MESSAGES.size()]
	msg_label.add_theme_font_size_override("font_size", 52)
	msg_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	msg_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER)
	overlay.add_child(msg_label)

	var play_btn = Button.new()
	play_btn.text = "Play Again"
	play_btn.add_theme_font_size_override("font_size", 28)
	play_btn.custom_minimum_size = Vector2(240, 70)
	play_btn.pressed.connect(_restart_game)
	overlay.add_child(play_btn)

	# Position after one frame so size is valid
	await get_tree().process_frame
	msg_label.position = Vector2((size.x - msg_label.size.x) * 0.5, size.y * 0.35)
	msg_label.pivot_offset = msg_label.size * 0.5
	play_btn.position = Vector2((size.x - 240.0) * 0.5, size.y * 0.55)

	# Animate in
	overlay.modulate.a = 0.0
	var fade = create_tween()
	fade.tween_property(overlay, "modulate:a", 1.0, 0.4)

	msg_label.scale = Vector2(0.3, 0.3)
	var bounce = msg_label.create_tween()
	bounce.set_ease(Tween.EASE_OUT)
	bounce.set_trans(Tween.TRANS_BACK)
	bounce.tween_property(msg_label, "scale", Vector2(1.0, 1.0), 0.55)

func _restart_game() -> void:
	if is_instance_valid(_win_overlay):
		_win_overlay.queue_free()
		_win_overlay = null
	_animating = false
	game.new_game()
	_play_deal_animation()

func _get_stock_pos() -> Vector2:
	return Vector2(_get_left_x() + (CARD_SIZE.x + _get_col_gap()) * 6.0, 16.0)

func _play_deal_animation() -> void:
	_animating = true

	# Wait one frame so the Control has been laid out and size is valid
	await get_tree().process_frame

	# Collect the top (face-up) card of each tableau column
	var top_entries: Array = []
	if game and game.tableau and game.tableau.size() >= 7:
		for col in range(7):
			var pile = game.tableau[col]
			if pile and not pile.is_empty():
				var top_card = pile[-1]
				if top_card and top_card.face_up:
					top_entries.append({"col": col, "card": top_card, "idx": pile.size() - 1})
	else:
		print("Board._play_deal_animation: Tableau not ready, skipping deal animation")

	# Temporarily flip top cards face-down so the initial render shows all face-down
	for entry in top_entries:
		entry.card.face_up = false

	_last_render_frame = -1
	render()

	# Restore face-up state (ghosts will show the correct card face)
	for entry in top_entries:
		entry.card.face_up = true

	var fly_origin = _get_stock_pos()
	const STAGGER = 0.06
	const FLY_DUR = 0.32

	var ghosts: Array = []
	var last_tween: Tween = null

	for i in range(top_entries.size()):
		var entry = top_entries[i]
		var col: int = entry.col
		var card = entry.card
		var dest = _get_tableau_card_pos(col, entry.idx)

		var ghost: CardView = preload("res://scenes/CardView.tscn").instantiate()
		ghost.card = card
		ghost._refresh()
		ghost.position = fly_origin
		ghost.z_index = 2000 + i
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ghost)
		ghosts.append(ghost)

		var t = create_tween()
		t.set_ease(Tween.EASE_OUT)
		t.set_trans(Tween.TRANS_CUBIC)
		if i > 0:
			t.tween_interval(i * STAGGER)
		t.tween_property(ghost, "position", dest, FLY_DUR)
		last_tween = t

	if last_tween != null:
		await last_tween.finished

	for ghost in ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()

	_animating = false
	render()

func _on_stock_pressed() -> void:
	if _animating or game == null:
		return
	_animating = true

	var col_step = CARD_SIZE.x + _get_col_gap()
	var lx = _get_left_x()
	var waste_anchor = Vector2(lx + col_step * 4.5, 16.0)
	var stock_pos    = Vector2(lx + col_step * 6.0,  16.0)

	# --- Snapshot existing waste CardViews before any state change ---
	var old_waste: Array = game.waste.duplicate()  # shallow copy is fine (card refs)
	var old_vis_start = max(0, old_waste.size() - 3)
	var old_views: Dictionary = {}  # SolitaireCard -> CardView
	for child in get_children():
		if child is CardView and old_waste.has(child.card):
			old_views[child.card] = child

	# --- Execute game logic ---
	game.draw_from_stock_3()
	stock_clicked.emit()

	# --- Compute new layout ---
	var new_size      = game.waste.size()
	var new_vis_start = max(0, new_size - 3)
	var new_vis_count = new_size - new_vis_start
	var dur           = 0.38

	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	var tweener_count = 0

	# Animate each previously-visible waste card to its new position (or off-screen)
	for i in range(old_vis_start, old_waste.size()):
		var card = old_waste[i]
		if not old_views.has(card):
			continue
		var view: CardView = old_views[card]
		var new_idx = game.waste.find(card)
		if new_idx == -1 or new_idx < new_vis_start:
			tween.tween_property(view, "position:x", waste_anchor.x - 55.0, dur)
			tween.tween_property(view, "modulate:a", 0.0, dur)
			tweener_count += 1
		else:
			var vis_i = new_idx - new_vis_start
			tween.tween_property(view, "position:x",
				_waste_card_x(waste_anchor.x, vis_i, new_vis_count), dur)
			tweener_count += 1

	# Slide newly drawn card(s) in from the stock position
	var drawn_count = new_size - old_waste.size()
	for di in range(drawn_count):
		var wi = old_waste.size() + di
		if wi < new_vis_start:
			continue
		var card = game.waste[wi]
		var vis_i = wi - new_vis_start
		var ghost: CardView = preload("res://scenes/CardView.tscn").instantiate()
		ghost.card = card
		ghost._refresh()
		ghost.position = Vector2(stock_pos.x, waste_anchor.y)
		ghost.z_index  = 100 + di
		add_child(ghost)
		tween.tween_property(ghost, "position:x",
			_waste_card_x(waste_anchor.x, vis_i, new_vis_count), dur)
		tweener_count += 1

	if tweener_count > 0:
		await tween.finished
	else:
		tween.kill()
	_animating = false
	render()

func render() -> void:
	if game == null:
		print("ERROR: Board.render() called but game is null!")
		return
	
	var current_frame = Engine.get_frames_drawn()
	if current_frame == _last_render_frame:
		return  # Skip duplicate renders in same frame
	
	_last_render_frame = current_frame

	_stock_button = null  # Always recreate; don't preserve across renders

	# Clear all children except persistent nodes and in-flight undo ghost cards
	for child in get_children():
		if child == _stock_count_label or child == _win_overlay:
			continue
		if child.has_meta("_undo_ghost"):
			continue
		if is_instance_valid(child) and not child.is_queued_for_deletion():
			child.queue_free()

	# Clear drop zones dictionary
	_drop_zones.clear()

	var top_y = 16.0
	var bottom_margin = 18.0
	var available_h = maxf(0.0, size.y - top_y - bottom_margin)

	# Use helpers so render() and all animation helpers share identical positions
	var col_gap = _get_col_gap()
	var left_x = _get_left_x()

	var piles_row_y = top_y
	var tableau_y = piles_row_y + CARD_SIZE.y + 44.0
	var tableau_h = maxf(0.0, available_h - (CARD_SIZE.y + 26.0))

	# Foundations on the left (4 piles)
	var foundation_start_x = left_x
	# Waste and stock on the right - waste fans out, so needs extra space before stock
	# Waste needs space for 3 cards fanning (2 * WASTE_FAN_X = 70px extra)
	var waste_pos = Vector2(left_x + (CARD_SIZE.x + col_gap) * 4.5, piles_row_y)
	var stock_pos = Vector2(left_x + (CARD_SIZE.x + col_gap) * 6.0, piles_row_y)

	# Update stock count label position
	if is_instance_valid(_stock_count_label):
		_stock_count_label.position = stock_pos + Vector2(0, CARD_SIZE.y + 4.0)
		if game and game.stock:
			_stock_count_label.text = str(game.stock.size())

	# Draw foundation slots first (left side) - darker for visibility
	for i in range(4):
		var foundation_pos = Vector2(foundation_start_x + i * (CARD_SIZE.x + col_gap), piles_row_y)
		_draw_foundation_slot(foundation_pos, i)
	# Draw stock slot only (waste has no outline by design)
	_draw_slot(stock_pos)

	# Draw foundations (left side)
	if game and game.foundations and game.foundations.size() >= 4:
		for i in range(4):
			_draw_foundation(game.foundations[i], Vector2(foundation_start_x + i * (CARD_SIZE.x + col_gap), piles_row_y), i)
	else:
		print("Board.render: Foundations not ready, skipping foundation rendering")
	# Draw waste and stock (right side) - waste first (left), then stock (right)
	_draw_waste(waste_pos)
	_draw_stock(stock_pos)

	for col in range(7):
		var x = left_x + col * (CARD_SIZE.x + col_gap)
		if game and game.tableau and game.tableau.size() > col:
			_draw_tableau_column(game.tableau[col], Vector2(x, tableau_y), tableau_h, col)
		else:
			print("Board.render: Tableau column ", col, " not ready, skipping")

func _on_test_button_pressed():
	print("TEST BUTTON PRESSED! Mouse input works!")

func _draw_slot(pos: Vector2) -> void:
	# Use ColorRect instead of Panel — Panel has implicit theme margins that offset content
	var bg = ColorRect.new()
	bg.position = pos
	bg.size = CARD_SIZE
	bg.color = Color(0.0, 0.0, 0.0, 0.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Draw white border as four thin rects (top, bottom, left, right)
	var bw = 2.0
	for border_rect in [
		Rect2(pos, Vector2(CARD_SIZE.x, bw)),                         # top
		Rect2(pos + Vector2(0, CARD_SIZE.y - bw), Vector2(CARD_SIZE.x, bw)),  # bottom
		Rect2(pos, Vector2(bw, CARD_SIZE.y)),                          # left
		Rect2(pos + Vector2(CARD_SIZE.x - bw, 0), Vector2(bw, CARD_SIZE.y))   # right
	]:
		var line = ColorRect.new()
		line.position = border_rect.position
		line.size = border_rect.size
		line.color = Color(1.0, 1.0, 1.0, 0.6)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)

func _draw_foundation_slot(pos: Vector2, suit_index: int) -> void:
	# Rounded dark panel with semi-transparent black border
	var slot_panel = Panel.new()
	slot_panel.position = pos
	slot_panel.size = CARD_SIZE
	slot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.42)
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_width_top    = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.0, 0.0, 0.0, 0.6)
	style.corner_radius_top_left     = 10
	style.corner_radius_top_right    = 10
	style.corner_radius_bottom_left  = 10
	style.corner_radius_bottom_right = 10
	slot_panel.add_theme_stylebox_override("panel", style)
	add_child(slot_panel)

	# Suit icon: CenterContainer fills the panel and guarantees visual centering
	var icon_paths = [
		"res://card_assets/cloves_icon.png",
		"res://card_assets/diamonds_icon.png",
		"res://card_assets/hearts_icon.png",
		"res://card_assets/spades_icon.png",
	]
	var icon_path = icon_paths[suit_index]
	if ResourceLoader.exists(icon_path):
		var center = CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_panel.add_child(center)

		var icon = TextureRect.new()
		icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(54, 54)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Alpha-mask the PNG to a flat white — all suits render same tint
		var shader = Shader.new()
		shader.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tCOLOR = vec4(1.0, 1.0, 1.0, c.a * 0.38);\n}"
		var mat = ShaderMaterial.new()
		mat.shader = shader
		icon.material = mat
		center.add_child(icon)

func _draw_stock(pos: Vector2) -> void:
	if not game or not game.stock:
		print("Board.render: Stock not ready, skipping stock rendering")
		return
		
	if game.stock.is_empty():
		# Empty stock — circular redo button centred in the slot
		var recycle_btn = Button.new()
		var btn_size = 72.0
		recycle_btn.position = pos + (CARD_SIZE - Vector2(btn_size, btn_size)) * 0.5
		recycle_btn.size = Vector2(btn_size, btn_size)
		recycle_btn.pressed.connect(_on_stock_pressed)
		var circle = StyleBoxFlat.new()
		circle.bg_color = Color(0.0, 0.0, 0.0, 0.45)
		var r = btn_size / 2.0
		circle.corner_radius_top_left     = r
		circle.corner_radius_top_right    = r
		circle.corner_radius_bottom_left  = r
		circle.corner_radius_bottom_right = r
		recycle_btn.add_theme_stylebox_override("normal", circle)
		var circle_pressed = circle.duplicate()
		circle_pressed.bg_color = Color(0.0, 0.0, 0.0, 0.65)
		recycle_btn.add_theme_stylebox_override("pressed", circle_pressed)
		recycle_btn.add_theme_stylebox_override("hover",   circle)
		# Redo icon via FontAwesome
		var fa = FontAwesome.new()
		fa.icon_name = "rotate-right"
		fa.icon_type = "solid"
		fa.icon_size = 36
		fa.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fa.set_anchors_preset(Control.PRESET_FULL_RECT)
		recycle_btn.add_child(fa)
		add_child(recycle_btn)
		return

	# Stock has cards — use a CardView (same renderer as waste) so Y aligns perfectly
	var stock_card = SolitaireCard.new()
	stock_card.face_up = false  # Shows card back via CardView._refresh()
	stock_card.stock = true
	var stock_view = preload("res://scenes/CardView.tscn").instantiate()
	stock_view.card = stock_card
	stock_view._refresh()
	stock_view.position = pos
	stock_view.z_index = 10
	# Route touch/click to stock handler (card is face-down so CardView won't emit card_clicked)
	stock_view.gui_input.connect(func(event: InputEvent):
		if event is InputEventScreenTouch and event.pressed:
			_on_stock_pressed()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_on_stock_pressed()
			get_viewport().set_input_as_handled()
	)
	add_child(stock_view)

func on_card_pressed(card) -> void:
	"""Handle Card Framework's native card press callback"""
	print("DEBUG: Card Framework on_card_pressed called!")
	_on_stock_pressed()

func on_card_move_done(card) -> void:
	"""Handle Card Framework's animation completion callback"""
	print("DEBUG: Card Framework on_card_move_done called!")
	# Animation completed - no additional action needed

func _on_stock_pile_input(event: InputEvent) -> void:
	"""Handle input events on the stock pile using Card Framework system"""
	print("DEBUG: Stock pile input! Event: ", event)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("DEBUG: Stock pile clicked!")
		_on_stock_pressed()

func _draw_waste(pos: Vector2) -> void:
	if not game or not game.waste:
		print("Board.render: Waste not ready, skipping waste rendering")
		return
		
	if game.waste.is_empty():
		return
	
	# Show up to 3 most recent cards, newest on the right
	var start = max(0, game.waste.size() - 3)
	var card_count = game.waste.size() - start
	
	for i in range(card_count):
		var idx = start + i  # Index in waste array
		var c = game.waste[idx]
		
		# Create a CardView for waste cards
		var waste_card_view = preload("res://scenes/CardView.tscn").instantiate()
		
		# Center the 3-card group - calculate center offset
		var total_width = (card_count - 1) * WASTE_SPREAD
		var center_offset = total_width / 2

		var card_offset = (card_count - 1 - i) * WASTE_SPREAD - center_offset
		waste_card_view.position = pos + Vector2(-card_offset, 0)
		
		waste_card_view.card = c
		waste_card_view._refresh()  # Setup the visual
		
		# Make only the newest card (rightmost) clickable
		if idx == game.waste.size() - 1:
			waste_card_view.card_clicked.connect(_on_waste_card_clicked)
			waste_card_view.card_drag_started.connect(_on_card_drag_started)
			waste_card_view.card_drag_ended.connect(_on_card_drag_ended)
			waste_card_view.move_to_front()  # Newest card on top layer
		
		add_child(waste_card_view)

func _on_waste_card_clicked(card_view: CardView) -> void:
	"""Handle clicking on waste card using CardView system"""
	print("Waste card clicked via CardView!")
	_on_card_clicked(card_view)

func _on_foundation_card_clicked(card: SolitaireCard, foundation_index: int) -> void:
	"""Handle clicking on foundation card using CardView system"""
	print("Foundation card clicked via CardView!")
	# Try to move foundation card back to tableau
	for i in range(7):
		if game.move_foundation_to_tableau(foundation_index, i):
			print("Moved ", card.short_name(), " from foundation ", foundation_index, " to tableau ", i)
			# Animate the movement
			await get_tree().create_timer(_animation_duration).timeout
			render()
			return
	
	print("Cannot move ", card.short_name(), " from foundation to any tableau pile")

func _on_waste_card_pressed(card: SolitaireCard):
	# Try to move to foundation first - use card's suit to determine correct foundation
	var correct_foundation = card.suit  # 0=Clubs, 1=Diamonds, 2=Hearts, 3=Spades
	if game.can_place_on_foundation(card, correct_foundation):
		if game.move_to_foundation("waste", -1, correct_foundation):
			# Re-enable delayed rendering now that crash is fixed
			_render_after_animation()
			return
	
	# If not moved to foundation, try to move to tableau
	for i in range(7):
		if game.move_waste_to_tableau(i):
			# Re-enable delayed rendering now that crash is fixed
			_render_after_animation()
			return

func _draw_foundation(pile: Array, pos: Vector2, foundation_index: int) -> void:
	# Always create a drop zone so cards can be dragged onto any foundation state
	_create_drop_zone("foundation_" + str(foundation_index), pos)
	if pile.is_empty():
		return
	var c = pile[pile.size() - 1]
	
	# Create a CardView for foundation cards
	var foundation_card_view = preload("res://scenes/CardView.tscn").instantiate()
	foundation_card_view.position = pos  # Match tableau positioning exactly
	foundation_card_view.card = c
	foundation_card_view._refresh()  # Setup the visual
	
	# Connect CardView signals for foundation cards
	foundation_card_view.card_clicked.connect(func(card_view: CardView):
		_on_foundation_card_clicked(card_view.card, foundation_index)
	)
	foundation_card_view.card_drag_started.connect(_on_card_drag_started)
	foundation_card_view.card_drag_ended.connect(_on_card_drag_ended)
	
	add_child(foundation_card_view)

func _draw_tableau_column(pile: Array, origin: Vector2, max_h: float, column_index: int) -> void:
	_create_drop_zone("tableau_" + str(column_index), origin)

	var y = origin.y
	for i in range(pile.size()):
		if max_h > 0.0 and (y - origin.y) > max_h:
			break
		var c = pile[i]
		
		# Create a CardView for tableau cards
		var tableau_card_view = preload("res://scenes/CardView.tscn").instantiate()
		tableau_card_view.position = Vector2(origin.x, y)
		tableau_card_view.card = c
		tableau_card_view._refresh()  # Setup the visual
		
		# Only face-up cards can be clicked/dragged
		if c.face_up:
			tableau_card_view.card_clicked.connect(_on_card_clicked)
			tableau_card_view.card_drag_started.connect(_on_card_drag_started)
			tableau_card_view.card_drag_ended.connect(_on_card_drag_ended)
			tableau_card_view.move_to_front()  # Face-up cards on top
		
		add_child(tableau_card_view)
		
		if c.face_up:
			y += TABLEAU_GAP_Y
		else:
			y += FACE_DOWN_GAP_Y

func _on_test_card_pressed(card: SolitaireCard):
	# Try to move to foundation first - use card's suit to determine correct foundation
	var correct_foundation = card.suit  # 0=Clubs, 1=Diamonds, 2=Hearts, 3=Spades
	if game.can_place_on_foundation(card, correct_foundation):
		# Find which pile this card is in
		for j in range(7):
			if not game.tableau[j].is_empty() and game.tableau[j][-1] == card:
				if game.move_to_foundation("tableau", j, correct_foundation):
					# Re-enable delayed rendering now that crash is fixed
					_render_after_animation()
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
					# Re-enable delayed rendering now that crash is fixed
					_render_after_animation()
					return

func _on_foundation_card_pressed(card: SolitaireCard, foundation_index: int) -> void:
	"""Handle clicking on a foundation card - try to move it back to tableau"""
	print("Foundation card clicked: ", card.short_name(), " from foundation ", foundation_index)
	
	# Try to move the card to any valid tableau pile
	for tableau_index in range(7):
		if game.move_foundation_to_tableau(foundation_index, tableau_index):
			print("Moved ", card.short_name(), " from foundation ", foundation_index, " to tableau ", tableau_index)
			# Re-enable delayed rendering now that crash is fixed
			_render_after_animation()
			return
	
	print("Cannot move ", card.short_name(), " from foundation to any tableau pile")

func _create_drop_zone(zone_name: String, pos: Vector2) -> void:
	var drop_zone = ColorRect.new()
	drop_zone.color = Color(0.0, 1.0, 0.0, 0.0)  # Invisible hit target
	drop_zone.position = pos
	if zone_name.begins_with("tableau_"):
		drop_zone.size = Vector2(CARD_SIZE.x, 600)  # Full column height
	else:
		drop_zone.size = CARD_SIZE
	drop_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drop_zones[zone_name] = drop_zone
	add_child(drop_zone)

func _on_card_clicked(card_view: CardView) -> void:
	if _animating or not is_instance_valid(card_view) or not card_view.card:
		return
	_animating = true
	var card = card_view.card

	# Foundation move (correct suit first, then fallback)
	for foundation_index in range(4):
		if game.can_place_on_foundation(card, foundation_index):
			if game.waste.has(card) and card == game.waste[-1]:
				if game.move_to_foundation("waste", -1, foundation_index):
					await _animate_single_card(card_view, _get_foundation_pos(foundation_index))
					_animating = false
					render()
					return
			for j in range(7):
				if not game.tableau[j].is_empty() and game.tableau[j][-1] == card:
					# Capture face-down card below before state changes
					var below_flip: SolitaireCard = null
					if game.tableau[j].size() >= 2 and not game.tableau[j][-2].face_up:
						below_flip = game.tableau[j][-2]
					if game.move_to_foundation("tableau", j, foundation_index):
						await _animate_single_card(card_view, _get_foundation_pos(foundation_index))
						if below_flip != null:
							for child in get_children():
								if child is CardView and child.card == below_flip:
									await _animate_card_flip(child)
									break
						_animating = false
						render()
						return

	# Waste to tableau
	if game.waste.has(card) and card == game.waste[-1]:
		for j in range(7):
			if game.can_place_on_tableau(card, j):
				if game.move_waste_to_tableau(j):
					await _animate_single_card(card_view, _get_tableau_card_pos(j, game.tableau[j].size() - 1))
					_animating = false
					render()
					return

	# Tableau to tableau — move the entire visible stack together
	var source_column = -1
	var card_index = -1
	for j in range(7):
		for k in range(game.tableau[j].size()):
			if game.tableau[j][k] == card:
				source_column = j
				card_index = k
				break
		if source_column != -1:
			break

	if source_column != -1:
		var card_count = game.tableau[source_column].size() - card_index
		# Record the card just below the dragged stack (may flip after move)
		var card_to_flip: SolitaireCard = null
		if card_index > 0 and not game.tableau[source_column][card_index - 1].face_up:
			card_to_flip = game.tableau[source_column][card_index - 1]
		# Capture the CardViews for the whole stack NOW, before the move changes game state
		var stack_solitaire_cards = game.tableau[source_column].slice(card_index)
		var stack_views: Array = []
		for child in get_children():
			if child is CardView and child.card in stack_solitaire_cards:
				stack_views.append(child)

		for j in range(7):
			if j != source_column and game.can_place_on_tableau(card, j):
				if game.move_tableau_to_tableau(source_column, j, card_count):
					# Animate all stack cards to their new positions simultaneously
					var dest_start = game.tableau[j].size() - card_count
					# Raise z_index so animated cards render above destination column cards
					for sv in stack_views:
						if is_instance_valid(sv):
							sv.z_index = 500
					var tween = create_tween()
					tween.set_ease(Tween.EASE_OUT)
					tween.set_trans(Tween.TRANS_CUBIC)
					tween.set_parallel(true)
					for k in range(stack_views.size()):
						var sv = stack_views[k]
						if is_instance_valid(sv):
							tween.tween_property(sv, "position", _get_tableau_card_pos(j, dest_start + k), _animation_duration)
					await tween.finished
					# Flip the newly revealed card (if any) before re-rendering
					if card_to_flip != null:
						for child in get_children():
							if child is CardView and child.card == card_to_flip:
								await _animate_card_flip(child)
								break
					_animating = false
					render()
					return

	_animating = false

func animate_undo() -> void:
	"""Animate the last move in reverse, then restore state via game.undo()."""
	if _animating or game == null or not game.can_undo():
		return
	_animating = true
	var hint = game.last_move_hint
	if hint.is_empty():
		game.undo()
		_animating = false
		render()
		return
	match hint.get("type", ""):
		"to_foundation":
			await _anim_undo_to_foundation(hint)
		"tableau_to_tableau":
			await _anim_undo_tableau_to_tableau(hint)
		"waste_to_tableau":
			await _anim_undo_waste_to_tableau(hint)
		_:
			game.undo()
			render()
	_animating = false

func _anim_ghost(card: SolitaireCard, from_pos: Vector2, to_pos: Vector2) -> void:
	"""Slide a ghost card from from_pos to to_pos, surviving render() in-flight."""
	var ghost = preload("res://scenes/CardView.tscn").instantiate()
	ghost.card = card
	ghost._refresh()
	ghost.position = from_pos
	ghost.z_index = 1000
	ghost.set_meta("_undo_ghost", true)
	add_child(ghost)
	# Re-render the board immediately so restored state is visible underneath
	render()
	var tween = ghost.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(ghost, "position", to_pos, _animation_duration)
	await tween.finished
	if is_instance_valid(ghost):
		ghost.queue_free()

func _anim_undo_to_foundation(hint: Dictionary) -> void:
	var foundation_col = hint.get("foundation_col", 0)
	var from_pile      = hint.get("from_pile", "tableau")
	var from_col       = hint.get("from_col", -1)
	if game.foundations[foundation_col].is_empty():
		game.undo(); render(); return
	var card     = game.foundations[foundation_col][-1]
	var from_pos = _get_foundation_pos(foundation_col)
	game.undo()
	var to_pos: Vector2
	if from_pile == "tableau" and from_col >= 0:
		to_pos = _get_tableau_card_pos(from_col, game.tableau[from_col].size() - 1)
	else:
		var cs = CARD_SIZE.x + _get_col_gap()
		to_pos = Vector2(_get_left_x() + cs * 4.5, 16.0)
	await _anim_ghost(card, from_pos, to_pos)

func _anim_undo_tableau_to_tableau(hint: Dictionary) -> void:
	var from_col  = hint.get("from_col", -1)
	var to_col    = hint.get("to_col",   -1)
	var count     = hint.get("card_count", 1)
	if from_col == -1 or to_col == -1 or game.tableau[to_col].size() < count:
		game.undo(); render(); return
	# Capture current positions of the stack before undo
	var pile       = game.tableau[to_col]
	var start_idx  = pile.size() - count
	var cards      = pile.slice(start_idx)
	var cur_positions = []
	for k in range(count):
		cur_positions.append(_get_tableau_card_pos(to_col, start_idx + k))
	game.undo()
	var restored_start = game.tableau[from_col].size() - count
	var target_positions = []
	for k in range(count):
		target_positions.append(_get_tableau_card_pos(from_col, restored_start + k))
	# Spawn all ghosts, re-render beneath them, animate back
	var ghosts = []
	for k in range(count):
		var ghost = preload("res://scenes/CardView.tscn").instantiate()
		ghost.card = cards[k]
		ghost._refresh()
		ghost.position = cur_positions[k]
		ghost.z_index  = 500 + k
		ghost.set_meta("_undo_ghost", true)
		add_child(ghost)
		ghosts.append(ghost)
	render()
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	for k in range(ghosts.size()):
		tween.tween_property(ghosts[k], "position", target_positions[k], _animation_duration)
	await tween.finished
	for g in ghosts:
		if is_instance_valid(g): g.queue_free()

func _anim_undo_waste_to_tableau(hint: Dictionary) -> void:
	var to_col = hint.get("to_col", -1)
	if to_col == -1 or game.tableau[to_col].is_empty():
		game.undo(); render(); return
	var card     = game.tableau[to_col][-1]
	var from_pos = _get_tableau_card_pos(to_col, game.tableau[to_col].size() - 1)
	game.undo()
	var cs     = CARD_SIZE.x + _get_col_gap()
	var to_pos = Vector2(_get_left_x() + cs * 4.5, 16.0)
	await _anim_ghost(card, from_pos, to_pos)

func _animate_card_flip(card_view: CardView) -> void:
	"""Flip a card from face-down to face-up with a scale-X animation."""
	card_view.pivot_offset = card_view.size * 0.5
	var t1 = create_tween()
	t1.set_ease(Tween.EASE_IN)
	t1.set_trans(Tween.TRANS_QUAD)
	t1.tween_property(card_view, "scale:x", 0.0, 0.1)
	await t1.finished
	# card.face_up is already true (set by game logic); refresh shows face-up texture
	card_view._refresh()
	var t2 = create_tween()
	t2.set_ease(Tween.EASE_OUT)
	t2.set_trans(Tween.TRANS_QUAD)
	t2.tween_property(card_view, "scale:x", 1.0, 0.1)
	await t2.finished
	card_view.pivot_offset = Vector2.ZERO

func _animate_single_card(card_view: CardView, target_pos: Vector2) -> void:
	"""Slide a single card to target_pos. Caller is responsible for render() afterward."""
	var temp = preload("res://scenes/CardView.tscn").instantiate()
	temp.card = card_view.card
	temp._refresh()
	temp.position = card_view.position
	temp.z_index = 1000
	add_child(temp)
	card_view.visible = false

	var tween = temp.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(temp, "position", target_pos, _animation_duration)
	await tween.finished

	if is_instance_valid(temp) and not temp.is_queued_for_deletion():
		temp.queue_free()

func _on_card_drag_started(card_view: CardView) -> void:
	var card = card_view.card
	if not card:
		return
	
	# Check if this card can be dragged (must be face-up)
	for i in range(7):
		var pile = game.tableau[i]
		var card_index = pile.find(card)
		if card_index != -1:
			# Only allow dragging if this card is face-up
			if not card.face_up:
				print("Cannot drag card - face-down")
				return  # Cancel drag
			break
	
	# Check waste pile - only allow dragging the topmost (newest) card
	if game.waste.has(card) and card != game.waste[-1]:
		print("Cannot drag waste card - not topmost")
		return  # Cancel drag
	
	_dragged_card_view = card_view
	_dragged_cards.clear()
	
	# Determine which cards are being dragged and find their CardViews
	var dragged_card_views: Array[CardView] = []
	for i in range(7):
		var pile = game.tableau[i]
		var card_index = pile.find(card)
		if card_index != -1:
			# Drag all cards from this position to the end of the pile
			_dragged_cards = pile.slice(card_index)
			
			# Find the CardView nodes for all dragged cards
			for child in get_children():
				if child is CardView and child.card in _dragged_cards:
					dragged_card_views.append(child)
			break
	
	# Store the dragged CardViews. Use global-position offsets so _process can update them correctly.
	_dragged_card_views = dragged_card_views
	_dragged_card_offsets.clear()
	var base_global = card_view.global_position
	for stack_card in dragged_card_views:
		if stack_card != card_view:
			_dragged_card_offsets[stack_card] = stack_card.global_position - base_global

	# Raise entire dragged stack to front
	for stack_card_view in _dragged_card_views:
		stack_card_view.z_index = card_view.z_index_when_dragging
	card_view.z_index = card_view.z_index_when_dragging

	# Waste card drag is always single-card
	if game.waste.has(card) and card == game.waste[-1]:
		_dragged_cards = [card]

func _on_card_drag_moved(card_view: CardView, new_position: Vector2) -> void:
	"""Move all cards in the dragged stack together"""
	if _dragged_card_views.is_empty():
		return
	
	# Move all other cards in the stack using stored offsets
	for stack_card_view in _dragged_card_views:
		if stack_card_view == card_view:
			continue  # Skip the card being dragged (it moves itself)
		
		# Use stored relative offset to maintain stack formation
		var relative_offset = _dragged_card_offsets.get(stack_card_view, Vector2.ZERO)
		stack_card_view.position = new_position + relative_offset

func _on_card_drag_ended(card_view: CardView, target_position: Vector2) -> void:
	if _dragged_card_view != card_view or _dragged_cards.is_empty():
		return

	# Pre-capture the face-down card just below the dragged stack (to flip after a tableau move)
	var card_to_flip_drag: SolitaireCard = null
	if not _dragged_cards.is_empty():
		var first = _dragged_cards[0]
		for j in range(7):
			var idx = game.tableau[j].find(first)
			if idx != -1:
				if idx > 0 and not game.tableau[j][idx - 1].face_up:
					card_to_flip_drag = game.tableau[j][idx - 1]
				break

	var zone_name = _get_drop_zone_at_position(target_position)
	var moved = false

	if zone_name != "":
		if zone_name.begins_with("foundation_"):
			if _dragged_cards.size() == 1:
				if _try_move_to_foundation(_dragged_cards[0]):
					moved = true
		elif zone_name.begins_with("tableau_"):
			var tableau_index = zone_name.split("_")[1].to_int()
			if _try_move_to_tableau(tableau_index):
				moved = true
				# Flip the newly revealed card before re-rendering
				if card_to_flip_drag != null:
					for child in get_children():
						if child is CardView and child.card == card_to_flip_drag:
							await _animate_card_flip(child)
							break

	if not moved:
		# Animate all dragged cards back to their original positions simultaneously.
		# Build the full list, ensuring card_view is always included (waste cards have empty _dragged_card_views).
		var all_cards_to_snap: Array = _dragged_card_views.duplicate()
		if not all_cards_to_snap.has(card_view):
			all_cards_to_snap.append(card_view)
		var snap_tween = create_tween()
		snap_tween.set_ease(Tween.EASE_OUT)
		snap_tween.set_trans(Tween.TRANS_BACK)
		snap_tween.set_parallel(true)
		for stack_card in all_cards_to_snap:
			var target_pos: Vector2
			if stack_card == card_view:
				target_pos = card_view.original_position
			else:
				target_pos = card_view.original_position + _dragged_card_offsets.get(stack_card, Vector2.ZERO)
			snap_tween.tween_property(stack_card, "global_position", target_pos, 0.25)
		await snap_tween.finished

	# Cleanup BEFORE render to avoid accessing freed nodes

	if is_instance_valid(card_view):
		card_view.z_index = 0
	for stack_card_view in _dragged_card_views:
		if is_instance_valid(stack_card_view):
			stack_card_view.z_index = 0

	_dragged_card_view = null
	_dragged_cards.clear()
	_dragged_card_views.clear()
	_dragged_card_offsets.clear()
	render()

func _animate_card_to_zone(card_view: Control, drop_zone: ColorRect) -> void:
	"""Animate card smoothly to drop zone position using our working animation system"""
	print("🎯 _animate_card_to_zone called!")
	if card_view and drop_zone:
		var target_pos = drop_zone.global_position
		print("🎯 Animating card to: ", target_pos)
		
		# Add animation system if not already present
		_add_animation_to_card(card_view)
		
		# Use our proven animation system
		_animate_card_framework(card_view, target_pos, _animation_duration)
	else:
		print("🎯 ERROR: card_view or drop_zone is null!")

func _create_test_button() -> void:
	"""Create a test button to trigger dramatic animation"""
	var test_button = Button.new()
	test_button.text = "🎭 TEST ANIMATION"
	test_button.custom_minimum_size = Vector2(250, 60)
	test_button.position = Vector2(50, 50)
	test_button.z_index = 1000  # Put on top of everything
	test_button.mouse_filter = Control.MOUSE_FILTER_STOP  # Ensure it receives mouse events
	
	# Make it very visible
	test_button.add_theme_font_size_override("font_size", 18)
	test_button.add_theme_color_override("font_color", Color.WHITE)
	test_button.add_theme_color_override("font_hover_color", Color.YELLOW)
	
	# Style the button - very bright and visible
	var button_style = StyleBoxFlat.new()
	button_style.bg_color = Color.MAGENTA  # Very bright color
	button_style.corner_radius_top_left = 12
	button_style.corner_radius_top_right = 12
	button_style.corner_radius_bottom_left = 12
	button_style.corner_radius_bottom_right = 12
	button_style.border_width_left = 4
	button_style.border_width_right = 4
	button_style.border_width_top = 4
	button_style.border_width_bottom = 4
	button_style.border_color = Color.YELLOW
	button_style.shadow_color = Color.BLACK
	button_style.shadow_size = 5
	button_style.shadow_offset = Vector2(2, 2)
	test_button.add_theme_stylebox_override("normal", button_style)
	
	# Hover style - even brighter
	var hover_style = button_style.duplicate()
	hover_style.bg_color = Color.CYAN
	test_button.add_theme_stylebox_override("hover", hover_style)
	
	# Pressed style
	var pressed_style = button_style.duplicate()
	pressed_style.bg_color = Color.GREEN
	test_button.add_theme_stylebox_override("pressed", pressed_style)
	
	# Connect the button
	test_button.pressed.connect(test_dramatic_animation)
	
	add_child(test_button)
	
	print("🧪 Test button added at position: ", test_button.position)
	print("🧪 Test button size: ", test_button.custom_minimum_size)
	print("🧪 Test button z_index: ", test_button.z_index)

func _auto_test_animation() -> void:
	"""Automatically trigger animation test after 5 seconds"""
	await get_tree().create_timer(5.0).timeout
	print("🤖 Auto-test triggered! Testing dramatic animation...")
	test_dramatic_animation()

func test_dramatic_animation() -> void:
	"""Test function to trigger dramatic animation on first card found"""
	print("🧪 Testing dramatic animation!")
	
	# Debug: Show all children and their methods
	print("🧪 Board children count: ", get_child_count())
	var card_found = false
	for i in range(get_child_count()):
		var child = get_child(i)
		print("🧪 Child ", i, ": ", child.name, " (", child.get_class(), ")")
		
		# Check various possible card indicators
		var methods = child.get_method_list()
		var has_card_properties = false
		
		# Check for card-like properties
		for method in methods:
			if method.name.contains("card") or method.name.contains("Card"):
				has_card_properties = true
				break
		
		# Check for common card properties
		if child.has_method("set_card_size") or child.has_method("get_card") or has_card_properties:
			print("🧪   - Has card-related methods!")
			
			# This is our test card! Only test the first one we find
			if not card_found:
				card_found = true
				print("🧪 Found card for testing!")
				print("🧪 Current position: ", child.global_position)
				
				# Add animation system to this card
				_add_animation_to_card(child)
				
				# Animate to a dramatically different position
				var test_target = child.global_position + Vector2(200, 100)
				print("🧪 Will animate to: ", test_target)
				
				_animate_card_framework(child, test_target, _animation_duration)
				return
	
	if not card_found:
		print("🧪 No card-like objects found! Let's try animating any Control...")
		# As a fallback, try animating the first Control we find
		for child in get_children():
			if child is Control and child.name.begins_with("@Control@"):
				print("🧪 Using fallback Control for testing!")
				print("🧪 Current position: ", child.global_position)
				
				_add_animation_to_card(child)
				var test_target = child.global_position + Vector2(200, 100)
				print("🧪 Will animate to: ", test_target)
				
				_animate_card_framework(child, test_target, _animation_duration)
				return
	
	print("🧪 No cards found for testing!")

func _animate_stock_refresh_with_card(suit: int, rank: int) -> void:
	var anim_card = SolitaireCard.new()
	anim_card.suit = suit
	anim_card.rank = rank
	anim_card.face_up = true
	anim_card.stock = false

	var anim_view = preload("res://scenes/CardView.tscn").instantiate()
	anim_view.card = anim_card
	anim_view._refresh()
	anim_view.z_index = 500

	# Use calculated positions relative to Board (local coords)
	var col_step = CARD_SIZE.x + _get_col_gap()
	var lx = _get_left_x()
	var stock_pos = Vector2(lx + col_step * 6.0, 16.0)
	var waste_pos = Vector2(lx + col_step * 4.5, 16.0)

	anim_view.position = stock_pos
	add_child(anim_view)

	# Simple right-to-left slide, no arc
	var tween = anim_view.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(anim_view, "position", waste_pos, 0.2)
	await tween.finished

	if is_instance_valid(anim_view) and not anim_view.is_queued_for_deletion():
		anim_view.queue_free()

func _animate_stock_refresh() -> void:
	"""Fallback animation function"""
	print("🔄 Using fallback stock animation!")
	_animate_stock_refresh_with_card(0, 1)  # Default to Ace of Spades

func _create_animation_indicator() -> void:
	"""Create a simple animation indicator when no cards are found"""
	var indicator = ColorRect.new()
	indicator.color = Color.ORANGE
	indicator.size = Vector2(80, 80)
	indicator.position = Vector2(870, 16)
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(indicator)
	indicator.move_to_front()
	
	var tween = indicator.create_tween()
	tween.tween_property(indicator, "scale", Vector2(1.5, 1.5), 0.3)
	tween.tween_property(indicator, "scale", Vector2(1.0, 1.0), 0.3)
	tween.tween_callback(func(): indicator.queue_free())
	
	print("🔄 Created orange indicator animation")

func _animate_waste_card_movement(foundation_index: int) -> void:
	"""Animate waste card moving to foundation"""
	print("🃏 Animating waste card to foundation ", foundation_index)
	
	# Find waste cards (should be near the stock area)
	for child in get_children():
		if child.has_method("set_card_size") or child.has_method("get_card"):
			var child_pos = child.global_position
			# Waste cards are typically to the right of stock
			if child_pos.x > 700 and child_pos.x < 900:  # Rough waste area
				print("🃏 Found waste card at: ", child_pos)
				
				# Calculate foundation position
				var foundation_x = 18.0 + (foundation_index * 140.0)  # Approx foundation positions
				var foundation_y = 16.0
				var target_pos = Vector2(foundation_x, foundation_y)
				
				# Add animation and move
				_add_animation_to_card(child)
				_animate_card_framework(child, target_pos, _animation_duration)
				return

func _animate_waste_card_movement_to_tableau(tableau_index: int) -> void:
	"""Animate waste card moving to tableau"""
	print("🃏 Animating waste card to tableau ", tableau_index)
	
	# Find waste cards
	for child in get_children():
		if child.has_method("set_card_size") or child.has_method("get_card"):
			var child_pos = child.global_position
			# Waste cards are typically to the right of stock
			if child_pos.x > 700 and child_pos.x < 900:  # Rough waste area
				print("🃏 Found waste card at: ", child_pos)
				
				# Calculate tableau position
				var tableau_x = 18.0 + (tableau_index * 140.0)  # Approx tableau positions
				var tableau_y = 200.0 + (tableau_index * 20.0)  # Approx tableau Y
				var target_pos = Vector2(tableau_x, tableau_y)
				
				# Add animation and move
				_add_animation_to_card(child)
				_animate_card_framework(child, target_pos, _animation_duration)
				return

func _add_animation_to_card(card: Control) -> void:
	"""Add animation system to a Card Framework card"""
	if not card.has_meta("_tween"):
		card.set_meta("_tween", null)
		print("🧪 Added animation system to card!")

func _animate_card_framework(card: Control, target_pos: Vector2, duration: float) -> void:
	"""Animate a Card Framework card with dramatic effects"""
	print("🎭 animate_to_position called! Target: ", target_pos, " Duration: ", duration)
	
	# Cancel any existing tween
	var existing_tween = card.get_meta("_tween")
	if existing_tween:
		existing_tween.kill()
	
	# Store original values
	var original_scale = card.scale
	var original_rotation = card.rotation
	
	# Create new tween
	var tween = card.create_tween()
	card.set_meta("_tween", tween)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_ELASTIC)  # VERY bouncy!
	
	# DRAMATIC animation sequence
	# 1. Scale up and rotate dramatically
	tween.tween_property(card, "scale", original_scale * 1.5, 0.2)
	tween.tween_property(card, "rotation", deg_to_rad(360), 0.2)
	
	# 2. Move to target with elastic bounce
	tween.tween_property(card, "global_position", target_pos, 0.8)
	tween.parallel().tween_property(card, "scale", original_scale * 1.2, 0.4)
	tween.parallel().tween_property(card, "rotation", deg_to_rad(-180), 0.4)
	
	# 3. Settle back to normal
	tween.tween_property(card, "scale", original_scale, 0.2)
	tween.tween_property(card, "rotation", original_rotation, 0.2)
	
	print("🎭 DRAMATIC animation started - duration: ", duration)
	print("🎭 Card will scale to 1.5x, rotate 360°, then bounce to target!")

func _get_drop_zone_at_position(pos: Vector2) -> String:
	for zone_name in _drop_zones.keys():
		var zone = _drop_zones[zone_name]
		var zone_rect = Rect2(zone.global_position, zone.size)
		if zone_rect.has_point(pos):
			return zone_name
	return ""

func _try_move_to_foundation(card: SolitaireCard) -> bool:
	# Find the card by object identity (must be top of its pile for a foundation move)
	for i in range(7):
		if not game.tableau[i].is_empty() and game.tableau[i][-1] == card:
			return game.move_to_foundation("tableau", i, card.suit)

	if not game.waste.is_empty() and game.waste[-1] == card:
		return game.move_to_foundation("waste", -1, card.suit)

	return false

func _try_move_to_tableau(tableau_index: int) -> bool:
	if _dragged_cards.is_empty():
		print("🎯 No dragged cards")
		return false
	
	var first_card = _dragged_cards[0]
	print("🎯 First card: ", first_card.short_name())
	
	# Find which tableau pile the cards are coming from
	for i in range(7):
		if game.tableau[i].has(first_card):
			var card_index = game.tableau[i].find(first_card)
			var card_count = game.tableau[i].size() - card_index
			print("🎯 From tableau ", i, " to tableau ", tableau_index, " card count: ", card_count)
			var result = game.move_tableau_to_tableau(i, tableau_index, card_count)
			print("🎯 game.move_tableau_to_tableau result: ", result)
			return result
	
	# Check if it's a waste card
	if game.waste.has(first_card) and first_card == game.waste[-1]:
		print("🎯 Moving waste card to tableau ", tableau_index)
		var result = game.move_waste_to_tableau(tableau_index)
		print("🎯 game.move_waste_to_tableau result: ", result)
		return result
	
	print("🎯 Card not found in any tableau or waste")
	return false
