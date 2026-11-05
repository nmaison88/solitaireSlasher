extends SceneTree
## Renders the "Classic" card deck (flat, bright faces; light-blue back) to card_assets/classic/.
## Needs a renderer, so run WITHOUT --headless:
##   Godot --path . --script res://tools/render_deck.gd
## Add "-- --court-only" to redraw just the J, Q and K.
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
	var first_rank := 11 if "--court-only" in OS.get_cmdline_user_args() else 1
	for suit_name in SUITS:
		for rank in range(first_rank, 14):
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
		_add_court(card, suit_name, rank)
	elif rank == 1:
		_add_suit(card, suit_name, Rect2(55, 150, 190, 215))
	else:
		_add_suit(card, suit_name, Rect2(80, 175, 140, 170))
	return card

func _add_court(card: Control, suit_name: String, rank: int) -> void:
	"""Flat vector court figure filling the card below the index, cropped by the card's bottom edge"""
	var image := Image.new()
	image.load_svg_from_string(_court_svg(suit_name, rank), 1.0)
	var art := TextureRect.new()
	art.texture = ImageTexture.create_from_image(image)
	art.position = Vector2(7, 137)
	art.size = Vector2(286, 256)
	card.add_child(art)

func _court_svg(suit_name: String, rank: int) -> String:
	var red_suit: bool = suit_name in ["Hearts", "Diamonds"]
	var ink := "#13234b"
	var gold := "#f2b632"
	var red := "#d3201f"
	var robe := red if red_suit else "#1f3a7a"
	var panel := "#1f3a7a" if red_suit else red
	var skin := "#fbe3c8"
	var hair: String = {13: "#e9e4d8", 12: "#c9792b", 11: "#c9792b"}[rank]
	var parts := PackedStringArray()
	var add := func(shape: String) -> void:
		parts.append(shape.replace("INK", ink).replace("GOLD", gold).replace("RED", red).replace("ROBE", robe).replace("PANEL", panel).replace("SKIN", skin).replace("HAIR", hair))

	# Prop behind the shoulder
	match rank:
		13:  # Sword
			add.call('<path d="M238,30 L252,30 L252,190 L238,190 Z" fill="#dfe6ee" stroke="INK" stroke-width="3"/><path d="M245,14 L252,30 L238,30 Z" fill="#dfe6ee" stroke="INK" stroke-width="3"/><path d="M222,190 L268,190 L268,200 L222,200 Z" fill="GOLD" stroke="INK" stroke-width="3"/>')
		12:  # Flower
			add.call('<path d="M44,130 C46,160 48,190 50,215" stroke="INK" stroke-width="5" fill="none"/><g fill="RED" stroke="INK" stroke-width="3"><circle cx="44" cy="92" r="13"/><circle cx="62" cy="106" r="13"/><circle cx="26" cy="106" r="13"/><circle cx="33" cy="125" r="13"/><circle cx="55" cy="125" r="13"/></g><circle cx="44" cy="110" r="10" fill="GOLD" stroke="INK" stroke-width="3"/>')
		11:  # Halberd
			add.call('<path d="M240,20 L250,20 L250,256 L240,256 Z" fill="GOLD" stroke="INK" stroke-width="3"/><path d="M245,0 L258,24 L232,24 Z" fill="#dfe6ee" stroke="INK" stroke-width="3"/><path d="M250,30 C278,30 282,62 262,74 L250,66 Z" fill="#dfe6ee" stroke="INK" stroke-width="3"/>')

	# Robe with a patterned center panel and gold trim
	add.call('<path d="M14,256 C18,204 58,176 143,170 C228,176 268,204 272,256 Z" fill="ROBE" stroke="INK" stroke-width="4"/>')
	add.call('<path d="M100,256 L112,176 L174,176 L186,256 Z" fill="PANEL" stroke="INK" stroke-width="3"/>')
	for row in 3:
		for side in [-1, 0, 1]:
			var dx: int = side * (16 + row * 3)
			add.call('<path d="M%d,%d l9,11 l-9,11 l-9,-11 Z" fill="GOLD" stroke="INK" stroke-width="2"/>' % [143 + dx, 188 + row * 23])
	for side_x in [46, 240]:
		for row in 3:
			add.call('<circle cx="%d" cy="%d" r="6" fill="GOLD" stroke="INK" stroke-width="2"/>' % [side_x + (row * 8 if side_x < 143 else -row * 8), 214 + row * 16 - (10 if row == 0 else 0)])

	# Long hair behind the neck
	if rank == 12:
		add.call('<path d="M96,70 C72,110 74,160 92,186 L124,176 L124,70 Z M190,70 C214,110 212,160 194,186 L162,176 L162,70 Z" fill="HAIR" stroke="INK" stroke-width="3"/>')
	# Neck, collar, face
	add.call('<path d="M126,120 L126,168 L160,168 L160,120 Z" fill="SKIN" stroke="INK" stroke-width="3"/>')
	add.call('<path d="M92,184 L143,160 L194,184 L176,196 L143,178 L110,196 Z" fill="GOLD" stroke="INK" stroke-width="3"/>')
	if rank == 13:  # King's side hair sits outside the face
		for y in [66, 88, 110, 132]:
			add.call('<circle cx="98" cy="%d" r="15" fill="HAIR" stroke="INK" stroke-width="3"/><circle cx="188" cy="%d" r="15" fill="HAIR" stroke="INK" stroke-width="3"/>' % [y, y])
	if rank == 11:  # Jack's page-boy curls
		for y in [74, 96, 118]:
			add.call('<circle cx="102" cy="%d" r="14" fill="HAIR" stroke="INK" stroke-width="3"/><circle cx="184" cy="%d" r="14" fill="HAIR" stroke="INK" stroke-width="3"/>' % [y, y])
	add.call('<ellipse cx="143" cy="92" rx="39" ry="50" fill="SKIN" stroke="INK" stroke-width="4"/>')
	# Features
	add.call('<path d="M120,80 q10,-7 18,-1 M150,79 q10,-6 18,1" stroke="INK" stroke-width="4" fill="none" stroke-linecap="round"/>')
	add.call('<circle cx="129" cy="90" r="4.5" fill="INK"/><circle cx="159" cy="90" r="4.5" fill="INK"/>')
	add.call('<path d="M144,92 L139,110 L148,111" stroke="INK" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round"/>')
	match rank:
		13:  # Full beard and moustache
			add.call('<path d="M104,108 C108,118 120,116 128,118 C136,114 150,114 158,118 C166,116 178,118 182,108 C188,136 170,168 143,172 C116,168 98,136 104,108 Z" fill="HAIR" stroke="INK" stroke-width="3"/>')
			add.call('<path d="M116,128 q27,-16 54,0 q-27,9 -54,0 Z" fill="#fffdf6" stroke="INK" stroke-width="3"/><path d="M134,136 q9,5 18,0" stroke="RED" stroke-width="4" fill="none" stroke-linecap="round"/>')
		12:
			add.call('<path d="M133,121 q10,8 20,0 q-10,-3 -20,0 Z" fill="RED" stroke="INK" stroke-width="2"/><circle cx="118" cy="106" r="6" fill="#f4b8a4"/><circle cx="168" cy="106" r="6" fill="#f4b8a4"/>')
		11:
			add.call('<path d="M122,116 q10,6 21,-1 q11,7 21,1 q-10,9 -21,4 q-11,5 -21,-4 Z" fill="HAIR" stroke="INK" stroke-width="2.5"/><path d="M135,127 q8,4 16,0" stroke="RED" stroke-width="3.5" fill="none" stroke-linecap="round"/>')

	# Headwear
	match rank:
		13:  # Crown
			add.call('<path d="M100,56 L92,10 L118,32 L143,2 L168,32 L194,10 L186,56 Z" fill="GOLD" stroke="INK" stroke-width="4" stroke-linejoin="round"/>')
			add.call('<path d="M100,46 L186,46 L188,62 L98,62 Z" fill="RED" stroke="INK" stroke-width="3"/>')
			add.call('<circle cx="120" cy="54" r="4" fill="GOLD"/><circle cx="143" cy="54" r="4" fill="GOLD"/><circle cx="166" cy="54" r="4" fill="GOLD"/><circle cx="143" cy="2" r="6" fill="RED" stroke="INK" stroke-width="2.5"/><circle cx="92" cy="10" r="5" fill="RED" stroke="INK" stroke-width="2.5"/><circle cx="194" cy="10" r="5" fill="RED" stroke="INK" stroke-width="2.5"/>')
		12:  # Hair over the brow and a small crown
			add.call('<path d="M104,88 C104,44 182,44 182,88 C168,64 118,64 104,88 Z" fill="HAIR" stroke="INK" stroke-width="3"/>')
			add.call('<path d="M108,54 L102,20 L124,36 L143,12 L162,36 L184,20 L178,54 Z" fill="GOLD" stroke="INK" stroke-width="4" stroke-linejoin="round"/>')
			add.call('<circle cx="143" cy="12" r="6" fill="#fffdf6" stroke="INK" stroke-width="2.5"/><circle cx="102" cy="20" r="5" fill="#fffdf6" stroke="INK" stroke-width="2.5"/><circle cx="184" cy="20" r="5" fill="#fffdf6" stroke="INK" stroke-width="2.5"/><path d="M110,46 L176,46" stroke="RED" stroke-width="6"/>')
		11:  # Flat cap with a feather
			add.call('<path d="M170,36 C196,8 226,8 232,16 C216,18 198,34 182,50 Z" fill="GOLD" stroke="INK" stroke-width="3"/>')
			add.call('<path d="M92,62 C92,20 194,20 194,62 Z" fill="ROBE" stroke="INK" stroke-width="4"/>')
			add.call('<path d="M90,54 L196,54 L198,70 L88,70 Z" fill="GOLD" stroke="INK" stroke-width="3"/>')

	return '<svg xmlns="http://www.w3.org/2000/svg" width="286" height="256" viewBox="0 0 286 256"><defs><clipPath id="c"><path d="M0,0 H286 V236 Q286,256 266,256 H20 Q0,256 0,236 Z"/></clipPath></defs><g clip-path="url(#c)">%s</g></svg>' % "".join(parts)

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
