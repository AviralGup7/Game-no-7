class_name TouchActionButton
extends Control
## A touch action button (attack / dodge). Fires `pressed` once per clean press,
## with multi-touch safety and optional haptic feedback. Anti-repeat: holding does
## not re-fire.

signal pressed

@export var action_name: String = ""
@export var vibrate_on_press := false
@export var radius: float = 56.0
@export var opacity: float = 0.5

var _touch_index := -1
var _held := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(radius * 2, radius * 2)
	modulate.a = opacity


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and not _held:
			_held = true
			_touch_index = t.index
			queue_redraw()
		elif not t.pressed and _held and t.index == _touch_index:
			_fire()
	elif event is InputEventMouseButton:
		# Desktop parity: left-click drives the button exactly like a tap.
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and not _held:
				_held = true
				_touch_index = -2
				queue_redraw()
			elif not mb.pressed and _held and _touch_index == -2:
				_fire()


func _fire() -> void:
	if not _held:
		return
	_held = false
	_touch_index = -1
	if vibrate_on_press:
		var settings := SaveManager.get_settings()
		if settings.vibration_enabled:
			Input.vibrate_handheld(15)
	pressed.emit()
	queue_redraw()


func cancel() -> void:
	_held = false
	_touch_index = -1
	queue_redraw()


func _draw() -> void:
	# Center on the allocated rect (not the radius) so any rect/radius pair
	# stays visually centered; clamp the ring to the smaller dimension.
	var center := size * 0.5
	var r := minf(radius, minf(size.x, size.y) * 0.5)
	var col := Color(1, 1, 1, 0.18 if _held else 0.10)
	draw_circle(center, r, col)
	draw_arc(center, r, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
