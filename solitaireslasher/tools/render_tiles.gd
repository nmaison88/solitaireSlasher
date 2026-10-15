extends SceneTree
## Renders the carousel tiles (art/tiles/*.svg -> "game icons/*_icon.png") and the app icon (-> icon.png).
## Run from the project folder:  Godot --headless --path . --script res://tools/render_tiles.gd

const TILES := {
	"solitaire": "res://game icons/solitaire_icon.png",
	"sudoku": "res://game icons/sudoku_icon.png",
	"spider": "res://game icons/spider_icon.png",
	"app_icon": "res://icon.png",  # iOS app icon (1024x1024, full bleed)
}

func _init() -> void:
	for tile_name in TILES:
		var svg := FileAccess.get_file_as_string("res://art/tiles/%s.svg" % tile_name)
		if svg.is_empty():
			push_error("Missing art/tiles/%s.svg" % tile_name)
			continue
		var image := Image.new()
		var err := image.load_svg_from_string(svg, 1.0)
		if err != OK:
			push_error("Could not rasterize %s.svg (error %d)" % [tile_name, err])
			continue
		if tile_name == "app_icon":
			image.convert(Image.FORMAT_RGB8)  # App Store rejects icons with an alpha channel
		image.save_png(ProjectSettings.globalize_path(TILES[tile_name]))
		print("Rendered ", TILES[tile_name], " ", image.get_size())
	quit()
