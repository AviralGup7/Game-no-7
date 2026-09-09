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

const _MOUSE_INDEX := -2

var _active := false
var _touch_index := -1
var _base := Vector2.ZERO
var _knob := Vector2.ZERO
var _value := Vector2.ZERO
var _resume_ignore := 0.0
var _rest_alpha := -1.0
var _touch_seen := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	modulate.a = opacity


func _process(delta: float) -> void:
	if _resume_ignore > 0.0:
		_resume_ignore = maxf(_resume_ignore - delta, 0.0)


func _gui_input(event: InputEvent) -> void:
	if event == null:
		InputTrace.record("null_event", "ignored")
		return
	if _resume_ignore > 0:
		var is_press := (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
		if not is_press:
			InputTrace.record("resume_ignore", event.as_text())
			return
		_resume_ignore = 0
	if event is InputEventScreenTouch:
		_touch_seen = true
		var t := event as InputEventScreenTouch
		InputTrace.record("touch", "i=%d p=%s pressed=%s active=%s own=%d" % [
			t.index, str(_finite_vec(t.position)), str(t.pressed), str(_active), _touch_index])
		if t.pressed and not _active:
			_begin(t.index, t.position)
		elif not t.pressed:
			if _active and t.index == _touch_index:
				_end()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _active and d.index == _touch_index:
			_update(d.position)
		elif _active and d.index != _touch_index:
			InputTrace.record("drag_mismatch", "i=%d own=%d" % [d.index, _touch_index])
	elif event is InputEventMouseButton:
		if _touch_seen and not (event as InputEventMouseButton).pressed:
			_touch_seen = false
		if _touch_seen:
			return
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed and not _active:
			_begin(_MOUSE_INDEX, mb.position)
		elif not mb.pressed and _active and _touch_index == _MOUSE_INDEX:
			_end()
	elif event is InputEventMouseMotion and _active and _touch_index == _MOUSE_INDEX:
		_update((event as InputEventMouseMotion).position)


func _safe_radius() -> float:
	return radius if is_finite(radius) and radius >= 8.0 else 8.0


func _is_finite_v2(v: Vector2) -> bool:
	return is_finite(v.x) and is_finite(v.y)


func _finite_vec(v: Vector2) -> Vector2:
	return v if _is_finite_v2(v) else Vector2.ZERO


func _begin(index: int, position: Vector2) -> void:
	if get_tree() != null and get_tree().paused:
		InputTrace.record("begin_paused", "ignored i=%d" % index)
		return
	if not _is_finite_v2(position):
		return
	_active = true
	_touch_index = index
	_base = position
	_knob = position
	_value = Vector2.ZERO
	InputTrace.record("begin", "i=%d pos=%s" % [index, str(position)])
	became_active.emit()
	value_changed.emit(_value)
	queue_redraw()


func _end() -> void:
	InputTrace.record("end", "i=%d value=%s" % [_touch_index, str(_value)])
	_active = false
	_touch_index = -1
	_value = Vector2.ZERO
	_knob = _base
	_restore_rest_alpha()
	became_inactive.emit()
	value_changed.emit(_value)
	queue_redraw()


func _update(position: Vector2) -> void:
	if not _active:
		return
	if _resume_ignore > 0:
		return
	if get_tree() != null and get_tree().paused:
		cancel()
		return
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
	return _value if _is_finite_v2(_value) else Vector2.ZERO


func is_active() -> bool:
	return _active


func cancel() -> void:
	if _active:
		InputTrace.dump("joystick_cancel")
		_end()
	_resume_ignore = maxf(_resume_ignore, 0.08)


func set_rest_alpha(value: float) -> void:
	_rest_alpha = clampf(value, 0.2, 1.0)
	if not _active:
		modulate.a = _rest_alpha


func _restore_rest_alpha() -> void:
	if _active:
		return
	modulate.a = _rest_alpha if _rest_alpha > 0.0 else opacity


func _draw() -> void:
	if not _active:
		var center := size * 0.5
		var inset := 8.0
		if get_viewport() != null:
			var safe := DisplayServer.get_display_safe_area()
			inset = maxf(inset, float(safe.position.x) * 0.25)
		center.x = maxf(center.x, inset)
		var rest := minf(_safe_radius() * 0.8, minf(size.x, size.y) * 0.42)
		if rest < 4.0:
			return
		var a := _rest_alpha if _rest_alpha > 0.0 else opacity
		draw_circle(center, rest, Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.45 * a))
		draw_arc(center, rest, 0, TAU, 48, Color(UiTheme.CYAN.r, UiTheme.CYAN.g, UiTheme.CYAN.b, 0.75 * a), 2.0)
		draw_circle(center, rest * 0.3, Color(UiTheme.CYAN.r, UiTheme.CYAN.g, UiTheme.CYAN.b, 0.8 * a))
		return
	var local_base := _base
	var local_knob := _knob
	var r := _safe_radius()
	var scale_f := 1.0
	if get_viewport() != null:
		scale_f = clampf(get_viewport().get_visible_rect().size.x / 1080.0, 0.75, 2.0)
	var knob_r := clampf(r * 0.34 * scale_f, 18.0, 48.0)
	draw_circle(local_base, r, Color(0, 0, 0, 0.35))
	draw_arc(local_base, r, 0, TAU, 48, Color(UiTheme.CYAN.r, UiTheme.CYAN.g, UiTheme.CYAN.b, 0.8), 3.0)
	draw_circle(local_knob, knob_r, Color(1, 1, 1, 0.45))
	draw_arc(local_knob, knob_r, 0, TAU, 32, UiTheme.GOLD, 2.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
		if _active:
			InputTrace.record("pause_gate", "what=%d" % what)
			cancel()
		_resume_ignore = 0.08
		_restore_rest_alpha()
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventScreenTouch and not event.pressed and event.index == _touch_index:
		cancel()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and _touch_index == _MOUSE_INDEX:
			cancel()
