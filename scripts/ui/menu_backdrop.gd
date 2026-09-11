class_name MenuBackdrop
extends Control
## Painted coliseum behind every menu. Falls back to a flat ember fill if the
## chrome file is missing (headless import before the first scan).
var _art: TextureRect
var _veil: ColorRect

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_art = TextureRect.new()
	_art.set_anchors_preset(PRESET_FULL_RECT)
	_art.mouse_filter = MOUSE_FILTER_IGNORE
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.texture = UiTheme.art("menu_backdrop.jpg")
	add_child(_art)
	_veil = ColorRect.new()
	_veil.set_anchors_preset(PRESET_FULL_RECT)
	_veil.mouse_filter = MOUSE_FILTER_IGNORE
	_veil.color = Color(0.04, 0.02, 0.01, 0.38)
	add_child(_veil)
	resized.connect(queue_redraw)

func _draw() -> void:
	if _art != null and _art.texture != null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.INK)
	draw_rect(Rect2(24, size.y * 0.15, 3, size.y * 0.22), UiTheme.GOLD)
