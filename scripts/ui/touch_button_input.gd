class_name TouchButtonInput
extends Node
## Native multi-touch for gameplay Buttons (skills and pause). Godot's BaseButton
## listens to mouse/ui_accept, so a second finger cannot rely on mouse emulation
## while the first finger owns the movement stick. Menus keep release semantics.
## gui_input is emitted BEFORE BaseButton's native handler; accepting synthetic
## mouse copies here prevents a second activation of the same touch.

var _button: Button
var _touch_index := -1


static func attach(button: Button) -> TouchButtonInput:
	var existing := button.get_node_or_null("TouchButtonInput") as TouchButtonInput
	if existing != null:
		return existing
	var input := TouchButtonInput.new()
	input.name = "TouchButtonInput"
	input._button = button
	button.add_child(input)
	return input


func _ready() -> void:
	_button.gui_input.connect(_on_gui_input)
	_button.visibility_changed.connect(_on_visibility_changed)
	_button.resized.connect(cancel)


func _on_gui_input(event: InputEvent) -> void:
	if event == null or not is_instance_valid(_button):
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		_button.accept_event()
		return
	if not event is InputEventScreenTouch:
		return
	var touch := event as InputEventScreenTouch
	_button.accept_event()
	if touch.canceled:
		if touch.index == _touch_index:
			cancel()
		return
	if not touch.pressed:
		if touch.index == _touch_index:
			cancel()
		return
	if _touch_index >= 0 or touch.index < 0 or _button.disabled:
		return
	if not _button.is_visible_in_tree() or not _button.can_process():
		return
	if not touch.position.is_finite() or not Rect2(Vector2.ZERO, _button.size).has_point(touch.position):
		return
	_touch_index = touch.index
	_button.pressed.emit()


func _input(event: InputEvent) -> void:
	# Releases outside the original button still retire that finger's claim.
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index == _touch_index and (touch.canceled or not touch.pressed):
			cancel()


func cancel() -> void:
	_touch_index = -1


func _on_visibility_changed() -> void:
	if not _button.is_visible_in_tree():
		cancel()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT,
		NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_PAUSED, NOTIFICATION_EXIT_TREE]:
		cancel()
