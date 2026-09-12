class_name UiSafeArea
extends Control
## DisplayServer returns physical pixels; the rest of the HUD uses stretched
## logical units. Android can change cutouts/system bars without resizing the
## viewport (notably a 180-degree landscape flip), so also watch the insets.

signal safe_area_changed

const REFRESH_INTERVAL := 0.25
var _elapsed := 0.0
var _last_margins := Vector4(-1, -1, -1, -1)
var _last_logical := Vector2(-1, -1)


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(PRESET_FULL_RECT)
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(refresh)
	refresh.call_deferred()


static func insets(logical: Vector2, window_pixels: Vector2, safe: Rect2) -> Vector4:
	if not logical.is_finite() or not window_pixels.is_finite() or not safe.position.is_finite() or not safe.size.is_finite():
		return Vector4.ZERO
	if logical.x <= 0 or logical.y <= 0 or window_pixels.x <= 0 or window_pixels.y <= 0 or not safe.has_area():
		return Vector4.ZERO
	# Transient/out-of-window platform rectangles must not invert or erase HUD
	# geometry. Missing safe-area support falls back to the visible window.
	var clipped := safe.intersection(Rect2(Vector2.ZERO, window_pixels))
	if not clipped.has_area():
		return Vector4.ZERO
	var ratio := logical / window_pixels
	return Vector4(clipped.position.x * ratio.x, clipped.position.y * ratio.y,
		(window_pixels.x - clipped.end.x) * ratio.x, (window_pixels.y - clipped.end.y) * ratio.y)


func refresh() -> void:
	var parent := get_parent_control()
	if parent == null or not is_inside_tree():
		return
	var margins := Vector4.ZERO
	if OS.has_feature("mobile"):
		var safe := Rect2(DisplayServer.get_display_safe_area())
		safe.position -= Vector2(DisplayServer.window_get_position())
		margins = insets(parent.size, Vector2(DisplayServer.window_get_size()), safe)
	_apply_margins(parent.size, margins)


func _apply_margins(logical: Vector2, margins: Vector4) -> void:
	if logical == _last_logical and margins == _last_margins:
		return
	_last_logical = logical
	_last_margins = margins
	# Do not reset to full rect on each poll: that would generate false resize
	# events and cancel the player's touches four times per second.
	offset_left = margins.x
	offset_top = margins.y
	offset_right = -margins.z
	offset_bottom = -margins.w
	safe_area_changed.emit()


func _process(delta: float) -> void:
	if not OS.has_feature("mobile") or not is_finite(delta) or delta <= 0.0:
		return
	_elapsed += delta
	if _elapsed >= REFRESH_INTERVAL:
		_elapsed = 0.0
		refresh()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN,
		NOTIFICATION_WM_WINDOW_FOCUS_IN] and is_inside_tree():
		refresh.call_deferred()
