class_name TouchActionButton
extends Control
## A touch action button (attack / dodge / swap). Fires `pressed` on PRESS-DOWN
## (not on release): attack and dodge are the most time-critical verbs in a game
## about dodging telegraphs, and release semantics add the whole tap duration
## (60-150 ms) as input latency. This matches the engine's own gameplay button —
## TouchScreenButton.pressed fires "when the button is pressed (down)" — while
## menu Buttons intentionally stay release-activated. Multi-touch safe (one
## owning finger per press) with optional haptic feedback. Anti-repeat: holding
## does not re-fire; sliding off and releasing elsewhere just clears the hold.

signal pressed
## Input state only: Player consumes held fire on its physics clock.
signal fire_input_changed(held: bool, aim: Vector2)

@export var action_name: String = ""
@export var vibrate_on_press := false
@export var radius: float = 56.0
@export var opacity: float = 0.5

var _touch_index := -1
var _held := false
var _label: Label
var _press_origin := Vector2.ZERO
var _aim := Vector2.ZERO
const AIM_DEADZONE := 0.18


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(radius * 2, radius * 2)
	modulate.a = opacity
	_label = Label.new()
	_label.set_anchors_preset(PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = MOUSE_FILTER_IGNORE
	_label.text = {"attack": "FIRE", "dodge": "DODGE", "switch_weapon": "SWAP", "reload": "RELOAD"}.get(action_name, action_name.to_upper())
	_label.add_theme_font_override("font", UiTheme.BOLD)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 5)
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_label)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree(): cancel())


func _gui_input(event: InputEvent) -> void:
	# Menus still need mouse-from-touch, but gameplay must not process the
	# synthesized copy as a second finger/shot. Physical mice remain supported.
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.canceled:
			if t.index == _touch_index:
				cancel()
			return
		if t.pressed and not _held:
			_held = true
			_touch_index = t.index
			_press_origin = t.position
			_aim = Vector2.ZERO
			queue_redraw()
			_fire()
		elif not t.pressed and _held and t.index == _touch_index:
			# Release only clears the hold: the intent already went out on
			# press-down, so a release must never fire (or double-fire).
			cancel()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _held and drag.index == _touch_index:
			_update_aim(drag.position)
			accept_event()
	elif event is InputEventMouseButton:
		# Desktop parity: left-click drives the button exactly like a tap.
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and not _held:
				_held = true
				_touch_index = -2
				_press_origin = mb.position
				_aim = Vector2.ZERO
				queue_redraw()
				_fire()
			elif not mb.pressed and _held and _touch_index == -2:
				cancel()


func _fire() -> void:
	if not _held:
		return
	# The command goes out FIRST. Haptics are presentation: a settings lookup or a
	# vibrate call that throws must never abort _fire() before the gameplay intent
	# is delivered — that silently kills the button the player just pressed
	# (the ATTACK button is the only one with vibrate_on_press, which is exactly
	# why it was the one that stopped answering).
	# _fire() intentionally does NOT clear the hold: the owning finger stays
	# tracked until release (anti-repeat + release-outside-cancel). Clearing
	# here would re-arm mid-press, so a second finger down during the same tap
	# would double-fire. Release branches and cancel() own the clearing.
	pressed.emit()
	_publish_fire()
	if vibrate_on_press:
		_vibrate()
	queue_redraw()


## Haptics are best-effort and never throw into the input path. Only attempted on a
## real handheld: desktop/web have no vibrator, and Android's VIBRATE is a
## permission-gated call (see docs/ANDROID_PERMISSIONS.md), so it must not run on a
## platform that cannot grant it.
func _vibrate() -> void:
	var settings := SaveManager.get_settings()
	if settings == null or not settings.vibration_enabled:
		return
	if not OS.has_feature("mobile"):
		return
	Input.vibrate_handheld(15)


func cancel() -> void:
	_held = false
	_touch_index = -1
	_aim = Vector2.ZERO
	_publish_fire()
	queue_redraw()


func _draw() -> void:
	# Center on the allocated rect (not the radius) so any rect/radius pair
	# stays visually centered; clamp the ring to the smaller dimension.
	var center := size * 0.5
	var r := minf(radius, minf(size.x, size.y) * 0.5)
	# Touch feedback: pressed grows a gold ring and brightens the disc, so a tap
	# is confirmed visually even when the thumb hides the label.
	var col := Color("3f6b86") if _held else Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.82)
	draw_circle(center, r, col)
	draw_arc(center, r, 0.0, TAU, 48, UiTheme.GOLD if _held else UiTheme.CYAN, 4.0 if _held else 3.0)
	if _held and action_name == "attack" and _aim != Vector2.ZERO:
		draw_line(center, center + _aim * r * 0.72, UiTheme.CYAN, 3.0, true)
		draw_circle(center + _aim * r * 0.72, 7.0, UiTheme.CYAN)
	if _held:
		draw_arc(center, r + 5.0, 0.0, TAU, 48, Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, 0.5), 2.0)


func _input(event: InputEvent) -> void:
	if not _held:
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index == _touch_index and (not touch.pressed or touch.canceled):
			cancel()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index and action_name == "attack":
			# Global capture continues beyond the button's bounds. It never
			# steals another finger or leaks this drag into camera orbit.
			_update_aim(get_global_transform_with_canvas().affine_inverse() * drag.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and _touch_index == -2:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.pressed:
			cancel()
	elif event is InputEventMouseMotion and _touch_index == -2 and action_name == "attack":
		var motion := event as InputEventMouseMotion
		_update_aim(get_global_transform_with_canvas().affine_inverse() * motion.position)
		get_viewport().set_input_as_handled()


func _update_aim(local_position: Vector2) -> void:
	if action_name != "attack" or not _held:
		return
	if not local_position.is_finite():
		cancel()
		return
	var raw := (local_position - _press_origin) / maxf(radius, 1.0)
	_aim = raw.limit_length(1.0) if raw.length() > AIM_DEADZONE else Vector2.ZERO
	_publish_fire()
	queue_redraw()


func _publish_fire() -> void:
	if action_name == "attack":
		fire_input_changed.emit(_held, _aim)


func get_aim_input() -> Vector2:
	return _aim if _held else Vector2.ZERO


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		cancel()


func is_held() -> bool:
	return _held and is_visible_in_tree()
