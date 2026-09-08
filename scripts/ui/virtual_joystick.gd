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

var _active := false
var _touch_index := -1
var _base := Vector2.ZERO       # base centre (screen coordinates)
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


func _begin(index: int, position: Vector2) -> void:
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
	var delta := position - _base
	var length := delta.length()
	if length > radius:
		delta = delta.normalized() * radius
	_knob = _base + delta
	var normalized := delta / radius
	if normalized.length() < dead_zone:
		normalized = Vector2.ZERO
	elif normalized.length() > 1.0:
		normalized = normalized.normalized()
	_value = normalized
	value_changed.emit(_value)
	queue_redraw()


func get_value() -> Vector2:
	return _value


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
		var rest := minf(radius * 0.8, minf(size.x, size.y) * 0.42)
		draw_circle(center, rest, Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.45))
		draw_arc(center, rest, 0, TAU, 48, Color(UiTheme.CYAN.r, UiTheme.CYAN.g, UiTheme.CYAN.b, 0.75), 2.0)
		draw_circle(center, rest * 0.3, Color(UiTheme.CYAN.r, UiTheme.CYAN.g, UiTheme.CYAN.b, 0.8))
		return
	# _gui_input positions are already control-local, so draw them as-is.
	var local_base := _base
	var local_knob := _knob
	draw_circle(local_base, radius, Color(0, 0, 0, 0.35))
	draw_arc(local_base, radius, 0, TAU, 48, Color(UiTheme.CYAN.r, UiTheme.CYAN.g, UiTheme.CYAN.b, 0.8), 3.0)
	draw_circle(local_knob, 34.0, Color(1, 1, 1, 0.45))
	draw_arc(local_knob, 34.0, 0, TAU, 32, UiTheme.GOLD, 2.0)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.pressed and event.index == _touch_index:
		cancel()

## Hardened: validate joystick vector.
func _validated_joy_vec(v: Vector2) -> Vector2:
	if not is_finite(v.x) or not is_finite(v.y):
		return Vector2.ZERO
	if v.length_squared() > 1.5:
		return v.normalized()
	return v

