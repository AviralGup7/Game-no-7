class_name UiSafeArea
extends Control
## Inset all interactive presentation, not the 3D camera. DisplayServer reports
## physical screen pixels; map them into the stretched logical viewport.

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(refresh)
	refresh.call_deferred()

static func insets(logical: Vector2, window_pixels: Vector2, safe: Rect2) -> Vector4:
	if window_pixels.x <= 0 or window_pixels.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var ratio := logical / window_pixels
	return Vector4(maxf(safe.position.x, 0) * ratio.x, maxf(safe.position.y, 0) * ratio.y,
		maxf(window_pixels.x - safe.end.x, 0) * ratio.x, maxf(window_pixels.y - safe.end.y, 0) * ratio.y)

func refresh() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	if not OS.has_feature("mobile"):
		return
	var safe := Rect2(DisplayServer.get_display_safe_area())
	safe.position -= Vector2(DisplayServer.window_get_position())
	var margins := insets(get_parent_control().size, Vector2(DisplayServer.window_get_size()), safe)
	offset_left = margins.x
	offset_top = margins.y
	offset_right = -margins.z
	offset_bottom = -margins.w
