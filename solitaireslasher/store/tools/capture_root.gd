extends Node
## Hosts the game in an off-screen viewport at full phone resolution, since macOS won't open a
## window taller than the screen. With --frames=<dir> it saves every rendered frame as a JPEG.

var _viewport: SubViewport
var _frames_dir := ""
var _frame := 0

func _ready() -> void:
	var size := Vector2i(1320, 2868)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			var parts := arg.split("=")[1].split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with("--frames="):
			_frames_dir = arg.split("=")[1]
	_viewport = SubViewport.new()
	_viewport.size = size
	_viewport.size_2d_override = Vector2i(1024, 1024 * size.y / size.x)
	_viewport.size_2d_override_stretch = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var game: Node = load("res://scenes/Main.tscn").instantiate()
	_viewport.add_child(game)
	get_tree().current_scene = game
	if _frames_dir != "":
		RenderingServer.frame_post_draw.connect(_save_frame)

func _save_frame() -> void:
	_viewport.get_texture().get_image().save_jpg("%s/f%05d.jpg" % [_frames_dir, _frame], 0.95)
	_frame += 1
