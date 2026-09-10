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
var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(radius * 2, radius * 2)
	modulate.a = opacity
	_label = Label.new()
	_label.set_anchors_preset(PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = MOUSE_FILTER_IGNORE
	_label.text = {"attack": "ATTACK", "dodge": "DODGE", "switch_weapon": "SWAP"}.get(action_name, action_name.to_upper())
	_label.add_theme_font_override("font", UiTheme.BOLD)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 5)
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_label)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree(): cancel())


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
	# The command goes out FIRST. Haptics are presentation: a settings lookup or a
	# vibrate call that throws must never abort _fire() before the gameplay intent
	# is delivered — that silently kills the button the player just pressed
	# (the ATTACK button is the only one with vibrate_on_press, which is exactly
	# why it was the one that stopped answering).
	pressed.emit()
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
	if _held:
		draw_arc(center, r + 5.0, 0.0, TAU, 48, Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, 0.5), 2.0)


func _input(event: InputEvent) -> void:
	if not _held:
		return
	if event is InputEventScreenTouch and not event.pressed and event.index == _touch_index:
		if not get_global_rect().has_point(event.position): cancel()
	elif event is InputEventMouseButton and not event.pressed and _touch_index == -2:
		if not get_global_rect().has_point(event.position): cancel()
