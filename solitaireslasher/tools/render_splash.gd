extends SceneTree
## Renders the boot splash (solitaireSlasherSplash.png) from the game tiles, the menu backdrop
## shader and the app's title styling. Needs a renderer, so run WITHOUT --headless:
##   Godot --path . --script res://tools/render_splash.gd
## Render the tiles first (tools/render_tiles.gd).

const WastelandStyle = preload("res://scripts/WastelandStyle.gd")
const SIZE := Vector2i(1242, 2688)  # iPhone portrait
const OUTPUT := "res://solitaireSlasherSplash.png"

func _initialize() -> void:
	_render.call_deferred()

func _render() -> void:
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var canvas := Control.new()
	canvas.size = Vector2(SIZE)
	viewport.add_child(canvas)

	# Backdrop: the same atmosphere shader as the menu, red glow behind the tiles
	var bg := ColorRect.new()
	bg.size = Vector2(SIZE)
	bg.color = Color(0.1, 0.08, 0.07)
	var bg_material := ShaderMaterial.new()
	bg_material.shader = load("res://shaders/menu_wasteland.gdshader")
	bg_material.set_shader_parameter("aspect", float(SIZE.x) / SIZE.y)
	bg_material.set_shader_parameter("glow_center", Vector2(0.5, 0.34))
	bg_material.set_shader_parameter("glow_radius", 0.24)
	bg_material.set_shader_parameter("glow_strength", 0.6)
	bg_material.set_shader_parameter("glow_color", WastelandStyle.accent_for("Solitaire"))
	bg.material = bg_material
	canvas.add_child(bg)

	# Fanned tiles: Spider and Sudoku behind, Solitaire Slasher in front
	var center := Vector2(SIZE.x * 0.5, SIZE.y * 0.34)
	_add_tile(canvas, "spider", center + Vector2(-330, 60), 420.0, -10.0, 0.8)
	_add_tile(canvas, "sudoku", center + Vector2(330, 60), 420.0, 10.0, 0.8)
	_add_tile(canvas, "solitaire", center, 540.0, 0.0, 1.0)

	_add_label(canvas, WastelandStyle.title("SOLITAIRE", 200), SIZE.y * 0.53)
	_add_label(canvas, WastelandStyle.title("SLASHER", 200), SIZE.y * 0.53 + 230)
	var tagline := WastelandStyle.label("DEATHMATCH MULTI-GAME ARENA", 58, WastelandStyle.BONE, 8, 8)
	_add_label(canvas, tagline, SIZE.y * 0.53 + 520)
	var games := WastelandStyle.label("SOLITAIRE  ·  SPIDER  ·  SUDOKU", 44, WastelandStyle.BONE_MUTED, 6)
	_add_label(canvas, games, SIZE.y * 0.88)

	# Let the viewport draw a few frames, then save
	for i in 4:
		await process_frame
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	var err := image.save_png(ProjectSettings.globalize_path(OUTPUT))
	print("Rendered ", OUTPUT, " ", image.get_size(), " err=", err)
	quit()

func _add_tile(parent: Control, tile_name: String, center: Vector2, side: float, degrees: float, brightness: float) -> void:
	# Load straight from disk so freshly rendered tiles are used even before Godot reimports them
	var image := Image.load_from_file(ProjectSettings.globalize_path("res://game icons/%s_icon.png" % tile_name))
	var tile := TextureRect.new()
	tile.texture = ImageTexture.create_from_image(image)
	tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tile.size = Vector2(side, side)
	tile.position = center - tile.size * 0.5
	tile.pivot_offset = tile.size * 0.5
	tile.rotation_degrees = degrees
	tile.modulate = Color(brightness, brightness, brightness)
	parent.add_child(tile)

func _add_label(parent: Control, label: Label, y: float) -> void:
	label.position = Vector2(0, y)
	label.size = Vector2(SIZE.x, 0)
	parent.add_child(label)
