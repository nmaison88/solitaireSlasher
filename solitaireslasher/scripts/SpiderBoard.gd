extends Control
class_name SpiderBoard

signal game_won

const CARD_SIZE       = Vector2(120, 160)
const PILE_GAP_X      = 20.0
const FACE_DOWN_GAP_Y = 22.0
const FACE_UP_GAP_Y   = 55.0
const TABLEAU_TOP_Y   = 250.0   # Header gap: increased to give more space between stock and tableau

const WIN_MESSAGES = [
	"YOU WIN!", "NICE JOB!", "MAN YOU'RE GOOD!",
	"GENIUS ALERT!", "ABSOLUTELY NAILED IT!",
	"FLAWLESS VICTORY!", "DEAL ME AGAIN!",
	"SOLITAIRE LEGEND!", "CARD SHARK!",
]

var _game: SpiderGame = null
var _animating: bool = false
var _animation_duration: float = 0.28
var _drop_zones: Dictionary = {}       # col_index(int) -> ColorRect
var _dragged_card_view: CardView = null
var _dragged_cards: Array = []         # Array[SolitaireCard]
var _dragged_card_views: Array = []    # Array[CardView]
var _dragged_card_offsets: Dictionary = {}
var _win_overlay: Control = null
var _last_render_frame: int = -1
var _undo_btn: Button = null
var _redo_btn: Button = null
var _foundation_stacks: Array = []     # Array[Array[SolitaireCard]] - tracks completed sequences (max 4)

# ── Layout helpers ─────────────────────────────────────────────────────────────

func _get_col_gap() -> float:
	var margin_x = 12.0
	var max_gap = (size.x - 2.0 * margin_x - 7.0 * CARD_SIZE.x) / 6.0
	return clampf(max_gap, 6.0, PILE_GAP_X)

func _get_left_x() -> float:
	var margin_x = 12.0
	var col_gap = _get_col_gap()
	var total_w = 7.0 * CARD_SIZE.x + 6.0 * col_gap
	var available_w = maxf(0.0, size.x - 2.0 * margin_x)
	return margin_x + maxf(0.0, (available_w - total_w) * 0.5)

func _get_col_x(col: int) -> float:
	return _get_left_x() + col * (CARD_SIZE.x + _get_col_gap())

func _get_card_y(col: int, card_idx: int) -> float:
	var y = TABLEAU_TOP_Y
	if _game == null:
		return y
	var pile: Array = _game.tableaus[col]
	for i in range(card_idx):
		if i < pile.size():
			y += FACE_DOWN_GAP_Y if not (pile[i] as SolitaireCard).face_up else FACE_UP_GAP_Y
	return y

func _get_card_pos(col: int, card_idx: int) -> Vector2:
	return Vector2(_get_col_x(col), _get_card_y(col, card_idx))

func _stock_pos() -> Vector2:
	return Vector2(_get_col_x(6), 16.0)

# ── Lifecycle ──────────────────────────────────────────────────────────────────

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(render)

func _process(_delta: float) -> void:
	if _dragged_card_view == null or _dragged_card_views.is_empty():
		return
	for cv in _dragged_card_views:
		if cv == _dragged_card_view:
			continue
		if not is_instance_valid(cv):
			continue
		var offset: Vector2 = _dragged_card_offsets.get(cv, Vector2.ZERO)
		cv.global_position = _dragged_card_view.global_position + offset

# ── Public API ─────────────────────────────────────────────────────────────────

func new_game(difficulty_string: String = "Easy") -> void:
	if is_instance_valid(_win_overlay):
		_win_overlay.queue_free()
		_win_overlay = null
	_animating = false
	_undo_btn = null
	_redo_btn = null
	_foundation_stacks.clear()

	if _game == null:
		_game = SpiderGame.new()
		add_child(_game)
		_game.game_won.connect(_on_game_won)
		_game.sequence_completed.connect(_on_sequence_completed)

	_game.new_game(difficulty_string)
	_play_deal_animation()

func _on_game_won() -> void:
	game_won.emit()
	_show_win_screen()

func _on_sequence_completed(col: int, suit: int) -> void:
	"""Handle completed sequence - animate to foundation"""
	if _foundation_stacks.size() >= 4:
		return  # Already have 4 foundations

	# Get the 13 cards that were just removed (they're still in view)
	var cards_to_animate: Array = []
	for child in get_children():
		if child is CardView and child.card and child.card.suit == suit and child.card.face_up:
			cards_to_animate.append(child)

	if cards_to_animate.is_empty():
		return

	# Sort by position (bottom to top)
	cards_to_animate.sort_custom(func(a, b): return a.global_position.y > b.global_position.y)

	# Keep only the top 13 cards from this column
	if cards_to_animate.size() > 13:
		cards_to_animate = cards_to_animate.slice(0, 13)

	# Calculate foundation position (above left 4 columns, stacked)
	var col_gap = _get_col_gap()
	var left_x = _get_left_x()
	var foundation_col = _foundation_stacks.size()
	var foundation_x = left_x + foundation_col * (CARD_SIZE.x + col_gap)
	var foundation_y = TABLEAU_TOP_Y - CARD_SIZE.y - 20.0  # Above tableau with gap

	# Animate each card to foundation position with stagger
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_parallel(true)

	for i in range(cards_to_animate.size()):
		var cv = cards_to_animate[i]
		var stagger_delay = i * 0.03
		tween.tween_callback(func(): pass).set_delay(stagger_delay)
		tween.tween_property(cv, "global_position", Vector2(foundation_x, foundation_y), 0.5)

	await tween.finished

	# Play foundation sound
	if SoundManager:
		SoundManager.play_foundation()

	# Hide the animated cards and track the foundation
	for cv in cards_to_animate:
		cv.visible = false
	_foundation_stacks.append(cards_to_animate.map(func(cv): return cv.card))

	# Re-render to show new foundation position
	render()

func _animate_foundation_removal(foundation_index: int) -> void:
	"""Animate removed foundation back to tableau during undo"""
	if foundation_index < 0 or foundation_index >= _foundation_stacks.size():
		return

	var removed_foundation = _foundation_stacks[foundation_index]
	if removed_foundation.is_empty():
		return

	# Calculate foundation position
	var col_gap = _get_col_gap()
	var left_x = _get_left_x()
	var foundation_y = TABLEAU_TOP_Y - CARD_SIZE.y - 20.0
	var foundation_x = left_x + foundation_index * (CARD_SIZE.x + col_gap)
	var foundation_pos = Vector2(foundation_x, foundation_y)

	# Create temporary CardViews for animation
	var ghost_views: Array = []
	for card in removed_foundation:
		var cv: CardView = preload("res://scenes/CardView.tscn").instantiate()
		cv.card = card
		cv._refresh()
		cv.position = foundation_pos
		cv.z_index = 100
		add_child(cv)
		ghost_views.append(cv)

	# Find which tableau column these cards belong to (they should be on top of a column now)
	# The sequence was removed from a specific column, so they go back to that column
	var target_col = -1
	var target_y = TABLEAU_TOP_Y
	for col in range(SpiderGame.TABLEAU_COUNT):
		# Find which column has the King (bottom card of the sequence)
		if not _game.tableaus[col].is_empty():
			var col_size = _game.tableaus[col].size()
			# The King should be the last card we added back
			if col_size >= 13:
				# Check if the top 13 cards match our removed sequence
				var found = true
				for i in range(13):
					if _game.tableaus[col][col_size - 13 + i] != removed_foundation[i]:
						found = false
						break
				if found:
					target_col = col
					target_y = _get_card_y(col, col_size - 13)
					break

	if target_col == -1:
		# Fallback: just animate down
		target_col = 0
		target_y = TABLEAU_TOP_Y + 200.0

	# Animate ghosts back to tableau
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_parallel(true)

	for i in range(ghost_views.size()):
		var cv = ghost_views[i]
		var target_pos = Vector2(_get_col_x(target_col), target_y + i * FACE_UP_GAP_Y)
		tween.tween_property(cv, "global_position", target_pos, 0.5)

	await tween.finished

	# Remove ghost views
	for cv in ghost_views:
		cv.queue_free()

	# Play undo-like sound (reverse of foundation sound)
	if SoundManager:
		SoundManager.play_card_draw()  # Use card draw as undo indicator

	# Remove from foundation stacks
	_foundation_stacks.remove_at(foundation_index)

func _animate_foundation_addition(foundation_index: int) -> void:
	"""Animate restored foundation from tableau back to foundation during redo"""
	if foundation_index >= _foundation_stacks.size():
		return

	var restored_foundation = _foundation_stacks[foundation_index]
	if restored_foundation.is_empty():
		return

	# Create temporary CardViews starting from tableau position
	var ghost_views: Array = []
	var start_col = -1

	# Find where these cards are in the tableau (should be stacked together)
	for col in range(SpiderGame.TABLEAU_COUNT):
		if not _game.tableaus[col].is_empty():
			var col_arr = _game.tableaus[col]
			var col_size = col_arr.size()
			# Check if the last 13 cards match our restored sequence
			if col_size >= 13:
				var found = true
				for i in range(13):
					if col_arr[col_size - 13 + i] != restored_foundation[i]:
						found = false
						break
				if found:
					start_col = col
					break

	if start_col == -1:
		return  # Couldn't find the cards

	# Create ghost views for animation
	var col_size = _game.tableaus[start_col].size()
	var start_y = _get_card_y(start_col, col_size - 13)

	for i in range(restored_foundation.size()):
		var card = restored_foundation[i]
		var cv: CardView = preload("res://scenes/CardView.tscn").instantiate()
		cv.card = card
		cv._refresh()
		cv.position = Vector2(_get_col_x(start_col), start_y + i * FACE_UP_GAP_Y)
		cv.z_index = 100
		add_child(cv)
		ghost_views.append(cv)

	# Calculate foundation position
	var col_gap = _get_col_gap()
	var left_x = _get_left_x()
	var foundation_y = TABLEAU_TOP_Y - CARD_SIZE.y - 20.0
	var foundation_x = left_x + foundation_index * (CARD_SIZE.x + col_gap)
	var foundation_pos = Vector2(foundation_x, foundation_y)

	# Animate ghosts up to foundation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_parallel(true)

	for cv in ghost_views:
		tween.tween_property(cv, "global_position", foundation_pos, 0.5)

	await tween.finished

	# Remove ghost views
	for cv in ghost_views:
		cv.queue_free()

	# Play foundation sound
	if SoundManager:
		SoundManager.play_foundation()

# ── Render ─────────────────────────────────────────────────────────────────────

func render() -> void:
	if _game == null:
		return
	var frame = Engine.get_frames_drawn()
	if frame == _last_render_frame:
		return
	_last_render_frame = frame

	# Clear children (keep win overlay, game node, undo/redo buttons)
	for child in get_children():
		if child == _win_overlay or child == _game:
			continue
		if child == _undo_btn or child == _redo_btn:
			continue
		if child.has_meta("_undo_ghost"):
			continue
		if is_instance_valid(child) and not child.is_queued_for_deletion():
			child.queue_free()

	_drop_zones.clear()

	# Column slots and cards
	for col in range(SpiderGame.TABLEAU_COUNT):
		_draw_column_slot(Vector2(_get_col_x(col), TABLEAU_TOP_Y))
		_draw_column(col)

	# Foundation stacks (completed sequences - top left area)
	_draw_foundations()

	# Stock deck (top-right)
	_draw_stock_deck()

	# Undo / Redo buttons (created once, kept across renders)
	if _undo_btn == null:
		_create_undo_redo_buttons()

	_update_undo_redo_state()

func _draw_column_slot(pos: Vector2) -> void:
	var panel = Panel.new()
	panel.position = pos
	panel.size = CARD_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_width_top    = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 1.0, 1.0, 0.22)
	style.corner_radius_top_left     = 10
	style.corner_radius_top_right    = 10
	style.corner_radius_bottom_left  = 10
	style.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

func _draw_column(col: int) -> void:
	# Drop zone covers the entire column height
	var dz = ColorRect.new()
	dz.color = Color(0.0, 1.0, 0.0, 0.0)
	dz.position = Vector2(_get_col_x(col), TABLEAU_TOP_Y)
	dz.size = Vector2(CARD_SIZE.x, 900.0)
	dz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drop_zones[col] = dz
	add_child(dz)

	var pile: Array = _game.tableaus[col]
	for i in range(pile.size()):
		var card = pile[i] as SolitaireCard
		var cv: CardView = preload("res://scenes/CardView.tscn").instantiate()
		cv.card = card
		cv._refresh()
		cv.position = _get_card_pos(col, i)
		if card.face_up:
			cv.card_clicked.connect(_on_card_clicked)
			cv.card_drag_started.connect(_on_card_drag_started)
			cv.card_drag_ended.connect(_on_card_drag_ended)
			cv.card_drag_moved.connect(_on_card_drag_moved)
			cv.move_to_front()
		add_child(cv)

func _draw_foundations() -> void:
	"""Draw foundation slots for completed sequences (top left area)"""
	if _foundation_stacks.is_empty():
		return

	var col_gap = _get_col_gap()
	var left_x = _get_left_x()
	var foundation_y = TABLEAU_TOP_Y - CARD_SIZE.y - 20.0

	for i in range(_foundation_stacks.size()):
		var foundation_x = left_x + i * (CARD_SIZE.x + col_gap)
		var pos = Vector2(foundation_x, foundation_y)

		# Draw slot background
		_draw_column_slot(pos)

		# Draw the completed sequence (show top card - Ace face up)
		if not _foundation_stacks[i].is_empty():
			var top_card = _foundation_stacks[i][-1]  # Ace (last card in sequence)
			var cv: CardView = preload("res://scenes/CardView.tscn").instantiate()
			cv.card = top_card
			cv._refresh()
			cv.position = pos
			cv.z_index = 100
			add_child(cv)

func _draw_stock_deck() -> void:
	var stock_count = _game.stock.size()
	if stock_count == 0:
		return

	# Number of deals remaining (ceil, since a partial stock still = 1 deal)
	var deals_remaining = int(ceil(stock_count / float(SpiderGame.TABLEAU_COUNT)))
	var visible_cards = clampi(deals_remaining, 0, 5)  # Cap visual stack at 5

	var base_pos = _stock_pos()
	const STACK_OFFSET_Y = 5.0
	const STACK_OFFSET_X = 18.0  # Spread out 3 visible stock cards horizontally

	for i in range(visible_cards):
		var offset = Vector2(i * STACK_OFFSET_X, i * STACK_OFFSET_Y)
		var is_top = (i == visible_cards - 1)

		var cv: CardView = preload("res://scenes/CardView.tscn").instantiate()
		var dummy = SolitaireCard.new()
		dummy.face_up = false
		dummy.stock = true
		cv.card = dummy
		cv._refresh()
		cv.position = base_pos + offset
		cv.z_index = i + 1

		if is_top:
			cv.mouse_filter = Control.MOUSE_FILTER_STOP
			cv.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					_on_stock_pressed()
					get_viewport().set_input_as_handled()
				elif event is InputEventScreenTouch and event.pressed:
					_on_stock_pressed()
					get_viewport().set_input_as_handled()
			)
		else:
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE

		add_child(cv)

# ── Undo / Redo buttons ────────────────────────────────────────────────────────

func _circle_style(color: Color, radius: float) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	var r = radius / 2.0
	s.corner_radius_top_left     = r
	s.corner_radius_top_right    = r
	s.corner_radius_bottom_left  = r
	s.corner_radius_bottom_right = r
	return s

func _create_undo_redo_buttons() -> void:
	var btn_size = 100.0
	var bottom_offset = -160.0  # px up from bottom of SpiderBoard

	# ── Undo ──
	var undo_btn = Button.new()
	undo_btn.name = "spider_undo"
	undo_btn.anchor_left   = 0.0
	undo_btn.anchor_right  = 0.0
	undo_btn.anchor_top    = 1.0
	undo_btn.anchor_bottom = 1.0
	undo_btn.offset_left   = 12.0
	undo_btn.offset_right  = 12.0 + btn_size
	undo_btn.offset_top    = bottom_offset
	undo_btn.offset_bottom = bottom_offset + btn_size
	undo_btn.pivot_offset  = Vector2(btn_size * 0.5, btn_size * 0.5)
	undo_btn.tooltip_text  = "Undo"
	undo_btn.add_theme_stylebox_override("normal",   _circle_style(Color(0, 0, 0, 0.45), btn_size))
	undo_btn.add_theme_stylebox_override("hover",    _circle_style(Color(0, 0, 0, 0.55), btn_size))
	undo_btn.add_theme_stylebox_override("pressed",  _circle_style(Color(0, 0, 0, 0.65), btn_size))
	undo_btn.add_theme_stylebox_override("disabled", _circle_style(Color(0, 0, 0, 0.25), btn_size))

	var undo_vbox = VBoxContainer.new()
	undo_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	undo_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	undo_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	undo_btn.add_child(undo_vbox)

	var undo_icon = FontAwesome.new()
	undo_icon.icon_name = "rotate-left"
	undo_icon.icon_type = "solid"
	undo_icon.icon_size = 52
	undo_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	undo_vbox.add_child(undo_icon)

	var undo_lbl = Label.new()
	undo_lbl.text = "Undo"
	undo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	undo_lbl.add_theme_font_size_override("font_size", 17)
	undo_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	undo_vbox.add_child(undo_lbl)

	var _undo_tween: Tween = null
	undo_btn.button_down.connect(func() -> void:
		if undo_btn.disabled: return
		if _undo_tween and _undo_tween.is_valid(): _undo_tween.kill()
		_undo_tween = undo_btn.create_tween()
		_undo_tween.set_ease(Tween.EASE_OUT)
		_undo_tween.set_trans(Tween.TRANS_CUBIC)
		_undo_tween.tween_property(undo_btn, "scale", Vector2(0.88, 0.88), 0.08)
	)
	undo_btn.button_up.connect(func() -> void:
		if _undo_tween and _undo_tween.is_valid(): _undo_tween.kill()
		_undo_tween = undo_btn.create_tween()
		_undo_tween.set_ease(Tween.EASE_OUT)
		_undo_tween.set_trans(Tween.TRANS_BACK)
		_undo_tween.tween_property(undo_btn, "scale", Vector2(1.0, 1.0), 0.22)
	)
	undo_btn.pressed.connect(_on_undo_pressed)
	add_child(undo_btn)
	_undo_btn = undo_btn

	# ── Redo ──
	var redo_btn = Button.new()
	redo_btn.name = "spider_redo"
	redo_btn.anchor_left   = 0.0
	redo_btn.anchor_right  = 0.0
	redo_btn.anchor_top    = 1.0
	redo_btn.anchor_bottom = 1.0
	redo_btn.offset_left   = 12.0 + btn_size + 16.0
	redo_btn.offset_right  = 12.0 + btn_size + 16.0 + btn_size
	redo_btn.offset_top    = bottom_offset
	redo_btn.offset_bottom = bottom_offset + btn_size
	redo_btn.pivot_offset  = Vector2(btn_size * 0.5, btn_size * 0.5)
	redo_btn.tooltip_text  = "Redo"
	redo_btn.add_theme_stylebox_override("normal",   _circle_style(Color(0, 0, 0, 0.45), btn_size))
	redo_btn.add_theme_stylebox_override("hover",    _circle_style(Color(0, 0, 0, 0.55), btn_size))
	redo_btn.add_theme_stylebox_override("pressed",  _circle_style(Color(0, 0, 0, 0.65), btn_size))
	redo_btn.add_theme_stylebox_override("disabled", _circle_style(Color(0, 0, 0, 0.25), btn_size))

	var redo_vbox = VBoxContainer.new()
	redo_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	redo_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	redo_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	redo_btn.add_child(redo_vbox)

	var redo_icon = FontAwesome.new()
	redo_icon.icon_name = "rotate-right"
	redo_icon.icon_type = "solid"
	redo_icon.icon_size = 52
	redo_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	redo_vbox.add_child(redo_icon)

	var redo_lbl = Label.new()
	redo_lbl.text = "Redo"
	redo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	redo_lbl.add_theme_font_size_override("font_size", 17)
	redo_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	redo_vbox.add_child(redo_lbl)

	var _redo_tween: Tween = null
	redo_btn.button_down.connect(func() -> void:
		if redo_btn.disabled: return
		if _redo_tween and _redo_tween.is_valid(): _redo_tween.kill()
		_redo_tween = redo_btn.create_tween()
		_redo_tween.set_ease(Tween.EASE_OUT)
		_redo_tween.set_trans(Tween.TRANS_CUBIC)
		_redo_tween.tween_property(redo_btn, "scale", Vector2(0.88, 0.88), 0.08)
	)
	redo_btn.button_up.connect(func() -> void:
		if _redo_tween and _redo_tween.is_valid(): _redo_tween.kill()
		_redo_tween = redo_btn.create_tween()
		_redo_tween.set_ease(Tween.EASE_OUT)
		_redo_tween.set_trans(Tween.TRANS_BACK)
		_redo_tween.tween_property(redo_btn, "scale", Vector2(1.0, 1.0), 0.22)
	)
	redo_btn.pressed.connect(_on_redo_pressed)
	add_child(redo_btn)
	_redo_btn = redo_btn

func _update_undo_redo_state() -> void:
	if _game == null:
		return
	if is_instance_valid(_undo_btn):
		var can = _game.can_undo()
		_undo_btn.disabled = not can
		_undo_btn.modulate.a = 1.0 if can else 0.38
		if not can:
			_undo_btn.scale = Vector2(1.0, 1.0)
	if is_instance_valid(_redo_btn):
		var can = _game.can_redo()
		_redo_btn.disabled = not can
		_redo_btn.modulate.a = 1.0 if can else 0.38
		if not can:
			_redo_btn.scale = Vector2(1.0, 1.0)

# ── Stock dealing ──────────────────────────────────────────────────────────────

func _on_stock_pressed() -> void:
	if _animating:
		return

	# Pre-flight check: only blocked if stock is empty
	if _game.stock.is_empty():
		return

	_animating = true

	# --- Snapshot what will be dealt (top N cards, col 0 first) ---
	var deal_count = mini(SpiderGame.TABLEAU_COUNT, _game.stock.size())
	# stock is popped from the back, so the first card dealt is stock[-1]
	var cards_to_deal: Array = []
	for i in range(deal_count):
		cards_to_deal.append(_game.stock[_game.stock.size() - 1 - i])

	# --- Record destination Y for each column (current top + one FACE_UP gap) ---
	var dest_positions: Array = []
	for col in range(deal_count):
		var pile: Array = _game.tableaus[col]
		var y = _get_card_y(col, pile.size())  # position the new card will land at
		dest_positions.append(Vector2(_get_col_x(col), y))

	# --- Execute game state change ---
	_game.deal_from_stock()
	if SoundManager:
		SoundManager.play_card_draw()

	# --- Re-render board (cards at final positions, invisible until animation ends) ---
	# We force a re-render with a fresh frame counter so it fires immediately
	_last_render_frame = -1
	render()

	# --- Spawn ghost cards at stock origin and animate left→right with stagger ---
	var fly_origin = _stock_pos()

	var STAGGER   = 0.06   # seconds between each card launch
	var FLY_DUR   = 0.32   # seconds for each card to reach its column

	# Hide the real rendered cards so ghosts are the only visible ones during flight.
	# Match by card object identity (cards_to_deal[i] is the SolitaireCard reference).
	var landing_views: Array = []
	var dealt_set: Array = cards_to_deal.duplicate()
	for child in get_children():
		if child is CardView and dealt_set.has(child.card):
			child.visible = false
			landing_views.append(child)

	var ghosts: Array = []
	for i in range(deal_count):
		var ghost: CardView = preload("res://scenes/CardView.tscn").instantiate()
		var dummy = SolitaireCard.new()
		# Show face-up dealt card texture
		dummy.face_up = true
		dummy.suit = cards_to_deal[i].suit
		dummy.rank = cards_to_deal[i].rank
		ghost.card = dummy
		ghost._refresh()
		ghost.position = fly_origin
		ghost.z_index  = 2000 + i
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.set_meta("_undo_ghost", true)
		add_child(ghost)
		ghosts.append(ghost)

	# Launch each ghost with a stagger
	var last_tween: Tween = null
	for i in range(deal_count):
		var ghost: CardView = ghosts[i]
		var dest: Vector2   = dest_positions[i]
		var t = create_tween()
		t.set_ease(Tween.EASE_OUT)
		t.set_trans(Tween.TRANS_CUBIC)
		# Delay start by i * STAGGER
		if i > 0:
			t.tween_interval(i * STAGGER)
		t.tween_property(ghost, "position", dest, FLY_DUR)
		last_tween = t

	# Wait for the last card to land
	if last_tween != null:
		await last_tween.finished

	# Clean up ghosts and reveal real cards
	for ghost in ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	for lv in landing_views:
		if is_instance_valid(lv):
			lv.visible = true

	_animating = false
	_last_render_frame = -1
	render()

func _on_undo_pressed() -> void:
	if _animating or not _game.can_undo():
		return

	# Store foundation state before undo
	var foundations_before = _foundation_stacks.size()

	_game.undo()

	# Check if a foundation was removed by undo
	if foundations_before > _foundation_stacks.size():
		# Animate the removed foundation back down
		await _animate_foundation_removal(foundations_before - 1)

	render()

func _on_redo_pressed() -> void:
	if _animating or not _game.can_redo():
		return

	# Store foundation state before redo
	var foundations_before = _foundation_stacks.size()

	_game.redo()

	# Check if a foundation was added back by redo
	if _foundation_stacks.size() > foundations_before:
		# Animate the newly restored foundation from tableau back to foundation
		await _animate_foundation_addition(foundations_before)

	render()

# ── Click to move ──────────────────────────────────────────────────────────────

func _on_card_clicked(card_view: CardView) -> void:
	if _animating:
		return
	var card = card_view.card
	if card == null or not card.face_up:
		return

	var src_col = -1
	var card_idx = -1
	for c in range(SpiderGame.TABLEAU_COUNT):
		var idx = _game.tableaus[c].find(card)
		if idx != -1:
			src_col = c
			card_idx = idx
			break

	if src_col == -1:
		return
	if not _game.can_move_from(src_col, card_idx):
		return

	var dest_col = -1
	for dc in range(SpiderGame.TABLEAU_COUNT):
		if dc != src_col and _game.can_place_on(card, dc):
			dest_col = dc
			break

	if dest_col == -1:
		return

	_animating = true

	var card_to_flip: SolitaireCard = null
	if card_idx > 0:
		var below = _game.tableaus[src_col][card_idx - 1] as SolitaireCard
		if not below.face_up:
			card_to_flip = below

	var stack_cards = _game.tableaus[src_col].slice(card_idx)
	var stack_views: Array = []
	for child in get_children():
		if child is CardView and stack_cards.has(child.card):
			stack_views.append(child)

	var card_count = stack_cards.size()
	var seq_before = _game.sequences_completed
	_game.move_cards(src_col, card_idx, dest_col)
	if SoundManager:
		if _game.sequences_completed > seq_before:
			SoundManager.play_card_place()
			SoundManager.play_foundation()
		else:
			SoundManager.play_card_place()

	var dest_start = _game.tableaus[dest_col].size() - card_count
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
			tween.tween_property(sv, "position", _get_card_pos(dest_col, dest_start + k), _animation_duration)
	await tween.finished

	if card_to_flip != null:
		for child in get_children():
			if child is CardView and child.card == card_to_flip:
				await _animate_card_flip(child)
				break

	_animating = false
	render()

# ── Drag to move ───────────────────────────────────────────────────────────────

func _on_card_drag_started(card_view: CardView) -> void:
	var card = card_view.card
	if card == null or not card.face_up:
		return

	var src_col = -1
	var card_idx = -1
	for c in range(SpiderGame.TABLEAU_COUNT):
		var idx = _game.tableaus[c].find(card)
		if idx != -1:
			src_col = c
			card_idx = idx
			break

	if src_col == -1 or not _game.can_move_from(src_col, card_idx):
		return

	_dragged_card_view = card_view
	_dragged_cards = _game.tableaus[src_col].slice(card_idx)

	var all_views: Array = []
	for child in get_children():
		if child is CardView and _dragged_cards.has(child.card):
			all_views.append(child)

	_dragged_card_views = all_views
	_dragged_card_offsets.clear()
	var base_global = card_view.global_position
	for cv in all_views:
		if cv != card_view:
			_dragged_card_offsets[cv] = cv.global_position - base_global

	for cv in _dragged_card_views:
		if is_instance_valid(cv):
			cv.z_index = card_view.z_index_when_dragging

func _on_card_drag_moved(_card_view: CardView, _pos: Vector2) -> void:
	pass  # Multi-card stack handled in _process

func _on_card_drag_ended(card_view: CardView, target_position: Vector2) -> void:
	if _dragged_card_view != card_view or _dragged_cards.is_empty():
		return

	var src_col = -1
	var card_idx = -1
	var top_drag_card = _dragged_cards[0] as SolitaireCard
	for c in range(SpiderGame.TABLEAU_COUNT):
		var idx = _game.tableaus[c].find(top_drag_card)
		if idx != -1:
			src_col = c
			card_idx = idx
			break

	var card_to_flip: SolitaireCard = null
	if src_col != -1 and card_idx > 0:
		var below = _game.tableaus[src_col][card_idx - 1] as SolitaireCard
		if not below.face_up:
			card_to_flip = below

	var dest_col = _get_drop_zone_at_position(target_position)
	var moved = false

	print("DEBUG: drag_ended - src: ", src_col, ", target_pos: ", target_position, ", dest: ", dest_col, ", can_place: ", (dest_col != -1 and _game.can_place_on(top_drag_card, dest_col)))

	if dest_col != -1 and src_col != -1 and dest_col != src_col:
		if _game.can_place_on(top_drag_card, dest_col) and _game.can_move_from(src_col, card_idx):
			var card_count = _dragged_cards.size()
			var seq_before_drag = _game.sequences_completed
			_game.move_cards(src_col, card_idx, dest_col)
			if SoundManager:
				if _game.sequences_completed > seq_before_drag:
					SoundManager.play_card_place()
					SoundManager.play_foundation()
				else:
					SoundManager.play_card_place()
			moved = true

			var dest_start = _game.tableaus[dest_col].size() - card_count
			var tween = create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.set_parallel(true)
			for k in range(_dragged_card_views.size()):
				var sv = _dragged_card_views[k]
				if is_instance_valid(sv):
					tween.tween_property(sv, "position", _get_card_pos(dest_col, dest_start + k), _animation_duration)
			await tween.finished

			if card_to_flip != null:
				for child in get_children():
					if child is CardView and child.card == card_to_flip:
						await _animate_card_flip(child)
						break

	if not moved:
		var snap_tween = create_tween()
		snap_tween.set_ease(Tween.EASE_OUT)
		snap_tween.set_trans(Tween.TRANS_BACK)
		snap_tween.set_parallel(true)
		for cv in _dragged_card_views:
			if is_instance_valid(cv):
				var target_pos: Vector2
				if cv == card_view:
					target_pos = card_view.original_position
				else:
					target_pos = card_view.original_position + _dragged_card_offsets.get(cv, Vector2.ZERO)
				snap_tween.tween_property(cv, "global_position", target_pos, 0.25)
		await snap_tween.finished

	for cv in _dragged_card_views:
		if is_instance_valid(cv):
			cv.z_index = 0
	_dragged_card_view = null
	_dragged_cards.clear()
	_dragged_card_views.clear()
	_dragged_card_offsets.clear()
	render()

func _get_drop_zone_at_position(pos: Vector2) -> int:
	# Check which zone contains the position
	for col in _drop_zones.keys():
		var zone: ColorRect = _drop_zones[col]
		if Rect2(zone.global_position, zone.size).has_point(pos):
			return col

	# If no exact hit, find the closest column by X position (handles off-screen drags)
	# This is especially important when dragging from right edge - finger may go off-screen
	var closest_col = -1
	var closest_dist = 9999.0
	for col in _drop_zones.keys():
		var zone: ColorRect = _drop_zones[col]
		var zone_center = zone.global_position.x + zone.size.x * 0.5
		var dist = abs(pos.x - zone_center)
		if dist < closest_dist:
			closest_dist = dist
			closest_col = col

	# Allow larger radius for edge cases (off-screen drags) - use full card width
	if closest_dist <= CARD_SIZE.x * 1.5:
		return closest_col

	return -1

# ── Animations ─────────────────────────────────────────────────────────────────

func _animate_card_flip(card_view: CardView) -> void:
	card_view.pivot_offset = card_view.size * 0.5
	var t1 = create_tween()
	t1.set_ease(Tween.EASE_IN)
	t1.set_trans(Tween.TRANS_QUAD)
	t1.tween_property(card_view, "scale:x", 0.0, 0.1)
	await t1.finished
	card_view._refresh()
	var t2 = create_tween()
	t2.set_ease(Tween.EASE_OUT)
	t2.set_trans(Tween.TRANS_QUAD)
	t2.tween_property(card_view, "scale:x", 1.0, 0.1)
	await t2.finished
	card_view.pivot_offset = Vector2.ZERO

# ── Initial deal animation ─────────────────────────────────────────────────────

func _play_deal_animation() -> void:
	_animating = true

	# Wait one frame so the Control has been laid out and size is valid
	await get_tree().process_frame

	# Collect the top (face-up) card of each column
	var top_entries: Array = []
	for col in range(SpiderGame.TABLEAU_COUNT):
		var pile: Array = _game.tableaus[col]
		if not pile.is_empty():
			var top_card = pile[-1] as SolitaireCard
			if top_card.face_up:
				top_entries.append({"col": col, "card": top_card, "idx": pile.size() - 1})

	# Temporarily flip top cards face-down so the initial render shows all face-down
	for entry in top_entries:
		(entry.card as SolitaireCard).face_up = false

	_last_render_frame = -1
	render()

	# Restore face-up state (ghosts will show the correct card face)
	for entry in top_entries:
		(entry.card as SolitaireCard).face_up = true

	var fly_origin = _stock_pos()
	const STAGGER = 0.06
	const FLY_DUR = 0.32

	var ghosts: Array = []
	var last_tween: Tween = null

	for i in range(top_entries.size()):
		var entry = top_entries[i]
		var col: int = entry.col
		var card = entry.card as SolitaireCard
		var dest = _get_card_pos(col, entry.idx)

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
	_last_render_frame = -1
	render()

# ── Win screen ─────────────────────────────────────────────────────────────────

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

	await get_tree().process_frame
	msg_label.position = Vector2((size.x - msg_label.size.x) * 0.5, size.y * 0.35)
	msg_label.pivot_offset = msg_label.size * 0.5
	play_btn.position = Vector2((size.x - 240.0) * 0.5, size.y * 0.55)

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
	_undo_btn = null
	_redo_btn = null
	_game.new_game(_game._difficulty)
	_play_deal_animation()
