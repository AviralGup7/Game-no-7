class_name VirtualJoystick
extends Control
## Floating virtual movement joystick. Captures touch in its (left-half) region,
## tracks a single ownership index for multi-touch safety, and exposes a normalized
## movement value. Requires no screen-coordinate knowledge from gameplay code.

signal value_changed(value: Vector2)
signal became_active()
signal became_inactive()

@export var radius: float = 96.0
@export_range(0.0, 0.5, 0.01) var dead_zone: float = 0.12
@export var opacity: float = 0.45

const _MOUSE_INDEX := -2   # synthesised ownership index for mouse dragging (editor/desktop)

var _active := false
var _touch_index := -1
var _base := Vector2.ZERO       # base centre (control-local coordinates)
var _knob := Vector2.ZERO
var _value := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = opacity


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and not _active:
			_begin(t.index, t.position)
		elif not t.pressed and _active and t.index == _touch_index:
			_end()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _active and d.index == _touch_index:
			_update(d.position)
	elif event is InputEventMouseButton:
		# Mouse parity so the stick can be driven (and this bug reproduced) in the
		# editor without a touch device.
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed and not _active:
			_begin(_MOUSE_INDEX, mb.position)
		elif not mb.pressed and _active and _touch_index == _MOUSE_INDEX:
			_end()
	elif event is InputEventMouseMotion and _active and _touch_index == _MOUSE_INDEX:
		_update((event as InputEventMouseMotion).position)


## The stick radius divides into the drag offset, so a degenerate radius (0, negative
## or non-finite from a layout pass on an unmeasured viewport) would produce inf/NaN
## movement values. Keep it at least a thumb-width.
func _safe_radius() -> float:
	return radius if is_finite(radius) and radius >= 8.0 else 8.0


func _is_finite_v2(v: Vector2) -> bool:
	return is_finite(v.x) and is_finite(v.y)


func _begin(index: int, position: Vector2) -> void:
	if not _is_finite_v2(position):
		return
	_active = true
	_touch_index = index
	_base = position
	_knob = position
	_value = Vector2.ZERO
	became_active.emit()
	value_changed.emit(_value)
	queue_redraw()


func _end() -> void:
	_active = false
	_touch_index = -1
	_value = Vector2.ZERO
	_knob = _base
	became_inactive.emit()
	value_changed.emit(_value)
	queue_redraw()


func _update(position: Vector2) -> void:
	if not _is_finite_v2(position):
		return
	var r := _safe_radius()
	var delta := position - _base
	var length := delta.length()
	if not is_finite(length):
		return
	if length > r:
		delta = delta.normalized() * r
	_knob = _base + delta
	var normalized := delta / r
	if not _is_finite_v2(normalized):
		return
	if normalized.length() < dead_zone:
		normalized = Vector2.ZERO
	elif normalized.length() > 1.0:
		normalized = normalized.normalized()
	_value = normalized
	value_changed.emit(_value)
	queue_redraw()


func get_value() -> Vector2:
	# Consumers latch this value, so a non-finite sample must never be handed out.
	return _value if _is_finite_v2(_value) else Vector2.ZERO


func is_active() -> bool:
	return _active


func cancel() -> void:
	if _active:
		_end()


func _draw() -> void:
	# Resting hint: a dimmed ring anchored inside the capture area shows where the
	# stick lives without competing with the arena behind it.
	if not _active:
		var center := size * 0.5
		var rest := minf(_safe_radius() * 0.8, minf(size.x, size.y) * 0.42)
		draw_circle(center, rest, Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.45))
		draw_arc(center, rest, 0, TAU, 48, Color(UiTheme.CYAN.r, UiTheme.CYAN.g, UiTheme.CYAN.b, 0.75), 2.0)
		draw_circle(center, rest * 0.3, Color(UiTheme.CYAN.r, UiTheme.CYAN.g, UiTheme.CYAN.b, 0.8))
		return
	# _gui_input positions are already control-local, so draw them as-is.
	var local_base := _base
	var local_knob := _knob
	var r := _safe_radius()
	draw_circle(local_base, r, Color(0, 0, 0, 0.35))
	draw_arc(local_base, r, 0, TAU, 48, Color(UiTheme.CYAN.r, UiTheme.CYAN.g, UiTheme.CYAN.b, 0.8), 3.0)
	draw_circle(local_knob, 34.0, Color(1, 1, 1, 0.45))
	draw_arc(local_knob, 34.0, 0, TAU, 32, UiTheme.GOLD, 2.0)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.pressed and event.index == _touch_index:
		cancel()
