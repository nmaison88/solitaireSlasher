extends RefCounted
## Shared "wasteland" menu styling: fonts, labels, buttons, panels and inputs.
## Used via preload (const WastelandStyle = preload("res://scripts/WastelandStyle.gd")).

const BONE := Color(0.93, 0.87, 0.72)
const BONE_MUTED := Color(0.93, 0.87, 0.72, 0.55)
const INK := Color(0.08, 0.05, 0.04)
const METAL := Color(0.12, 0.1, 0.09, 0.92)
const METAL_DARK := Color(0.06, 0.05, 0.04, 0.95)
const BLOOD_SHADOW := Color(0.6, 0.05, 0.03, 0.8)

const ACCENTS := {
	"Solitaire": Color(0.9, 0.18, 0.14),
	"Sudoku": Color(0.45, 0.95, 0.3),
	"Spider": Color(0.95, 0.5, 0.15),
}

const DISPLAY_NAMES := {
	"Solitaire": "SOLITAIRE SLASHER",
	"Sudoku": "SUDOKU WASTELAND",
	"Spider": "SPIDER SOLITAIRE",
}

static func accent_for(game_type: String) -> Color:
	return ACCENTS.get(game_type, ACCENTS["Solitaire"])

static func display_name(game_type: String) -> String:
	return DISPLAY_NAMES.get(game_type, game_type.to_upper())

static func font(letter_spacing: int = 0) -> FontVariation:
	var base := SystemFont.new()
	base.font_names = PackedStringArray(["Avenir Next Condensed", "Impact", "Arial Narrow", "sans-serif"])
	base.font_weight = 800
	var variation := FontVariation.new()
	variation.base_font = base
	variation.spacing_glyph = letter_spacing
	return variation

static func label(text: String, font_size: int, color: Color = BONE, letter_spacing: int = 0, outline: int = 0) -> Label:
	var result := Label.new()
	result.text = text
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.add_theme_font_override("font", font(letter_spacing))
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	if outline > 0:
		result.add_theme_constant_override("outline_size", outline)
		result.add_theme_color_override("font_outline_color", INK)
	return result

static func title(text: String, font_size: int) -> Label:
	"""Big bone-white heading with a blood-red drop shadow"""
	var result := label(text, font_size, BONE, 6, 10)
	result.add_theme_color_override("font_shadow_color", BLOOD_SHADOW)
	result.add_theme_constant_override("shadow_offset_x", 0)
	result.add_theme_constant_override("shadow_offset_y", 6)
	return result

static func style_button(button: Button, accent: Color, primary: bool = true, font_size: int = 40) -> StyleBoxFlat:
	"""Dark metal button. Primary buttons get an accent border and glow; secondary ones a muted bone border.
	Returns the normal stylebox so callers can recolor it later."""
	var normal := StyleBoxFlat.new()
	normal.bg_color = METAL
	normal.set_border_width_all(4 if primary else 3)
	normal.set_corner_radius_all(14)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	if primary:
		normal.border_color = accent
		normal.shadow_color = Color(accent, 0.45)
		normal.shadow_size = 16
	else:
		normal.border_color = Color(BONE, 0.35)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = METAL_DARK
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.border_color = Color(BONE, 0.15)
	disabled.shadow_size = 0
	normal.changed.connect(func():
		pressed.border_color = normal.border_color
		pressed.shadow_color = normal.shadow_color)

	button.add_theme_font_override("font", font(6))
	button.add_theme_font_size_override("font_size", font_size)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, BONE)
	button.add_theme_color_override("font_disabled_color", Color(BONE, 0.35))
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("focus", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	return normal

static func make_button(text: String, accent: Color, primary: bool = true, min_size: Vector2 = Vector2(440, 112), font_size: int = 40) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	style_button(button, accent, primary, font_size)
	return button

static func panel_style(accent: Color) -> StyleBoxFlat:
	"""Translucent dark card with a faint accent edge"""
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.035, 0.72)
	style.set_border_width_all(2)
	style.border_color = Color(accent, 0.35)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(28)
	return style

static func card(accent: Color) -> PanelContainer:
	var result := PanelContainer.new()
	result.add_theme_stylebox_override("panel", panel_style(accent))
	# PanelContainer defaults to STOP, which would swallow drags meant for a parent ScrollContainer
	result.mouse_filter = Control.MOUSE_FILTER_PASS
	return result

static func section_header(text: String, font_size: int = 30) -> Label:
	return label(text, font_size, BONE_MUTED, 4)

static func style_line_edit(edit: LineEdit, accent: Color, font_size: int = 36) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = METAL_DARK
	normal.set_border_width_all(3)
	normal.border_color = Color(BONE, 0.3)
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = accent
	focus.draw_center = false  # Drawn over "normal"; only the border changes
	edit.add_theme_stylebox_override("normal", normal)
	edit.add_theme_stylebox_override("focus", focus)
	edit.add_theme_font_override("font", font(2))
	edit.add_theme_font_size_override("font_size", font_size)
	edit.add_theme_color_override("font_color", BONE)
	edit.add_theme_color_override("font_placeholder_color", Color(BONE, 0.35))
	edit.add_theme_color_override("caret_color", accent)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER

static func style_slider(slider: HSlider, accent: Color) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = METAL_DARK
	track.set_border_width_all(2)
	track.border_color = Color(BONE, 0.25)
	track.set_corner_radius_all(10)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color(accent, 0.75)
	fill.border_color = accent
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var grabber := _circle_texture(56, BONE, accent)
	slider.add_theme_icon_override("grabber", grabber)
	slider.add_theme_icon_override("grabber_highlight", grabber)

static func style_check_box(check: CheckBox, accent: Color, font_size: int = 36) -> void:
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		check.add_theme_stylebox_override(state, empty)
	check.add_theme_font_override("font", font(4))
	check.add_theme_font_size_override("font_size", font_size)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		check.add_theme_color_override(state, BONE)
	check.add_theme_icon_override("unchecked", _box_texture(48, accent, false))
	check.add_theme_icon_override("checked", _box_texture(48, accent, true))
	check.add_theme_constant_override("h_separation", 18)

static func _circle_texture(diameter: int, fill: Color, rim: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var r := diameter * 0.5
	for y in diameter:
		for x in diameter:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var c := Color(0, 0, 0, 0)
			if d <= r:
				c = rim if d > r - 6.0 else fill
				c.a *= clampf(r - d, 0.0, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

static func _box_texture(side: int, accent: Color, checked: bool) -> ImageTexture:
	var img := Image.create(side, side, false, Image.FORMAT_RGBA8)
	img.fill(METAL_DARK)
	var border := accent if checked else Color(BONE, 0.5)
	for i in side:
		for t in 4:
			img.set_pixel(i, t, border)
			img.set_pixel(i, side - 1 - t, border)
			img.set_pixel(t, i, border)
			img.set_pixel(side - 1 - t, i, border)
	if checked:
		img.fill_rect(Rect2i(12, 12, side - 24, side - 24), accent)
	return ImageTexture.create_from_image(img)
