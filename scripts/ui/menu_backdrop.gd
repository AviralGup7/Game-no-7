class_name MenuBackdrop
extends Control
## Lightweight vector presentation, no shader, animation, or downloaded art.
func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.INK)
	var center := Vector2(size.x * 0.85, size.y * 0.55)
	var radius := minf(size.x, size.y) * 0.55
	for i in range(5):
		draw_arc(center, radius + i * 54, 0, TAU, 80, Color(0.47, 0.87, 0.92, 0.045), 1)
	draw_line(Vector2(24, 0), Vector2(24, size.y), Color(0.47, 0.87, 0.92, 0.18), 1)
	draw_rect(Rect2(24, size.y * 0.15, 3, size.y * 0.22), UiTheme.GOLD)
	draw_line(Vector2(size.x - 24, 0), Vector2(size.x - 24, size.y), Color(0.47, 0.87, 0.92, 0.18), 1)
