extends Carousel
## Main menu game carousel: items scale, dim and tilt continuously with their distance
## from the center, so the effect follows the finger while dragging.

const FOCUS_SCALE: float = 1.12
const SIDE_SCALE: float = 0.78
const SIDE_BRIGHTNESS: float = 0.45
const SIDE_TILT_DEGREES: float = 6.0

func _on_item_progress(item: Control, _index: int, local_index: int, _scroll: float, scroll_offset: float) -> void:
	if _distance_cache <= 0.0:
		return
	var offset := local_index - scroll_offset / _distance_cache
	var t := clampf(absf(offset), 0.0, 1.0)
	item.pivot_offset = item.size * 0.5
	item.scale = Vector2.ONE * lerpf(FOCUS_SCALE, SIDE_SCALE, t)
	item.rotation = deg_to_rad(clampf(offset, -1.0, 1.0) * SIDE_TILT_DEGREES)
	var brightness := lerpf(1.0, SIDE_BRIGHTNESS, t)
	item.modulate = Color(brightness, brightness, brightness, lerpf(1.0, 0.85, t))
