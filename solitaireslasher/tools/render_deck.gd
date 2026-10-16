extends SceneTree
## Renders the "Classic" card deck (flat, bright faces; light-blue back) to card_assets/classic/.
## Needs a renderer, so run WITHOUT --headless:
##   Godot --path . --script res://tools/render_deck.gd
## Faces are named card<Suit><Rank>.png (e.g. cardHeartsQ.png, cardSpades10.png) plus back.png.

const WastelandStyle = preload("res://scripts/WastelandStyle.gd")
const SIZE := Vector2i(300, 400)  # 2.5x the 120x160 on-screen card, so it stays crisp
const OUT_DIR := "res://card_assets/classic"
const NAVY := Color("13234b")
const RED := Color("d3201f")
const SKY := Color("5bc0eb")
const SUITS := ["Clubs", "Diamonds", "Hearts", "Spades"]  # Matches SolitaireCard.Suit order

# Suit shapes drawn in a 320x350 box centred on the origin
const SUIT_PATHS := {
	"Spades": "M0,-160 C50,-90 150,-40 150,40 C150,110 80,140 22,95 C28,140 45,170 70,185 L-70,185 C-45,170 -28,140 -22,95 C-80,140 -150,110 -150,40 C-150,-40 -50,-90 0,-160 Z",
	"Hearts": "M0,175 C-70,110 -155,45 -155,-35 C-155,-105 -85,-145 -35,-115 C-15,-103 0,-85 0,-72 C0,-85 15,-103 35,-115 C85,-145 155,-105 155,-35 C155,45 70,110 0,175 Z",
	"Diamonds": "M0,-170 L125,0 L0,170 L-125,0 Z",
	"Clubs": "M0,-165 A70,70 0 1 1 -1,-165 Z M-80,-25 A70,70 0 1 1 -81,-25 Z M80,-25 A70,70 0 1 1 79,-25 Z M-20,20 L20,20 C25,100 45,150 75,180 L-75,180 C-45,150 -25,100 -20,20 Z",
}

var _viewport: SubViewport
var _suit_textures := {}

func _initialize() -> void:
	_render.call_deferred()

func _render() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	for suit_name in SUITS:
		_suit_textures[suit_name] = _suit_texture(suit_name)

	var count := 0
	for suit_name in SUITS:
		for rank in range(1, 14):
			await _save(_build_face(suit_name, rank), "card%s%s.png" % [suit_name, _rank_name(rank)])
			count += 1
	await _save(_build_back(), "back.png")
	print("Rendered ", count, " faces + back to ", OUT_DIR)
	quit()

func _save(card: Control, file_name: String) -> void:
	_viewport.add_child(card)
	for i in 3:
		await process_frame
	var image := _viewport.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, file_name]))
	card.queue_free()
	await process_frame

func _rank_name(rank: int) -> String:
	match rank:
		1: return "A"
		11: return "J"
		12: return "Q"
		13: return "K"
	return str(rank)

func _suit_texture(suit_name: String) -> ImageTexture:
	var color := RED if suit_name in ["Hearts", "Diamonds"] else NAVY
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="320" height="370" viewBox="-160 -175 320 370"><path d="%s" fill="#%s"/></svg>' % [SUIT_PATHS[suit_name], color.to_html(false)]
	var image := Image.new()
	image.load_svg_from_string(svg, 1.0)
	return ImageTexture.create_from_image(image)

func _card_base(fill: Color) -> Panel:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_border_width_all(7)
	style.border_color = NAVY
	style.set_corner_radius_all(26)
	style.anti_aliasing = true
	var card := Panel.new()
	card.size = Vector2(SIZE)
	card.add_theme_stylebox_override("panel", style)
	return card

func _add_suit(card: Control, suit_name: String, rect: Rect2) -> void:
	var icon := TextureRect.new()
	icon.texture = _suit_textures[suit_name]
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = rect.position
	icon.size = rect.size
	card.add_child(icon)

func _add_text(card: Control, text: String, color: Color, font_size: int, rect: Rect2, align: HorizontalAlignment) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", WastelandStyle.font(-2))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = rect.position
	label.size = rect.size
	card.add_child(label)

func _build_face(suit_name: String, rank: int) -> Control:
	var color := RED if suit_name in ["Hearts", "Diamonds"] else NAVY
	var card := _card_base(Color.WHITE)
	# Corner index: everything that must show on a stacked tableau card sits in the top 140px
	_add_text(card, _rank_name(rank), color, 128, Rect2(20, 4, 170, 136), HORIZONTAL_ALIGNMENT_LEFT)
	_add_suit(card, suit_name, Rect2(196, 22, 82, 90))

	if rank >= 11:
		# Court cards: tinted panel with a big letter and suit (no portrait art)
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = Color(color, 0.09)
		panel_style.set_border_width_all(4)
		panel_style.border_color = Color(color, 0.55)
		panel_style.set_corner_radius_all(16)
		var court := Panel.new()
		court.position = Vector2(40, 152)
		court.size = Vector2(220, 222)
		court.add_theme_stylebox_override("panel", panel_style)
		card.add_child(court)
		_add_text(card, _rank_name(rank), color, 150, Rect2(40, 150, 220, 145), HORIZONTAL_ALIGNMENT_CENTER)
		_add_suit(card, suit_name, Rect2(118, 306, 64, 56))
	elif rank == 1:
		_add_suit(card, suit_name, Rect2(55, 150, 190, 215))
	else:
		_add_suit(card, suit_name, Rect2(80, 175, 140, 170))
	return card

func _build_back() -> Control:
	var card := _card_base(Color.WHITE)
	var inner_style := StyleBoxFlat.new()
	inner_style.bg_color = SKY
	inner_style.set_corner_radius_all(16)
	inner_style.anti_aliasing = true
	var inner := Panel.new()
	inner.position = Vector2(20, 20)
	inner.size = Vector2(SIZE) - Vector2(40, 40)
	inner.add_theme_stylebox_override("panel", inner_style)
	card.add_child(inner)
	return card
