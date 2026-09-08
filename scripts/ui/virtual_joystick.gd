class_name VirtualJoystick
extends Control
## Floating virtual movement joystick. Captures touch in its (left-half) region,
## tracks a single ownership index for multi-touch safety, and exposes a normalized
## movement value. Requires no screen-coordinate knowledge from gameplay code.

signal value_changed(value: Vector2)
signal became_active()
signal became_inactive()

@export var radius: float = 96.0
@export var dead_zone: float = 0.12
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
	if not _active:
		var center := Vector2(minf(radius + 16, size.x * 0.5), size.y * 0.5)
		draw_circle(center, radius * 0.8, UiTheme.INK)
		draw_arc(center, radius * 0.8, 0, TAU, 48, UiTheme.CYAN, 2.0)
		draw_circle(center, 24, UiTheme.CYAN)
		return
	draw_circle(_base, radius, Color(1, 1, 1, 0.10))
	draw_circle(_base, radius, Color(1, 1, 1, 0.10), false, 3.0, true)
	draw_circle(_knob, 34.0, Color(1, 1, 1, 0.30))


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not event.pressed and event.index == _touch_index:
		cancel()
