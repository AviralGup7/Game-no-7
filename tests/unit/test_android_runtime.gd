extends RefCounted
## Android input/lifecycle regressions using native Godot objects. Registered in
## the live-tree phase. These do not substitute for an APK/device test.


static func suite() -> Array:
	var results: Array = []
	var host := Control.new()
	host.size = Vector2(1280, 720)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	_buttons(results, host)
	_joystick(results, host)
	_safe_area(results, host)
	_camera(results)
	_audio_lifecycle(results)
	host.free()
	return results


static func _check(results: Array, name: String, passed: bool) -> void:
	results.append({"name": name, "passed": passed, "why": ""})


static func _touch(index: int, pressed: bool = true, canceled: bool = false) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = Vector2(40, 40)
	event.pressed = pressed
	event.canceled = canceled
	return event


static func _buttons(results: Array, host: Control) -> void:
	var skill := Button.new()
	var pause := Button.new()
	for button in [skill, pause]:
		button.size = Vector2(140, 120)
		host.add_child(button)
	var skill_touch := TouchButtonInput.attach(skill)
	var pause_touch := TouchButtonInput.attach(pause)
	var counts: Array[int] = [0, 0]
	skill.pressed.connect(func() -> void: counts[0] += 1)
	pause.pressed.connect(func() -> void: counts[1] += 1)
	_check(results, "Android button adapter is attached only once", TouchButtonInput.attach(skill) == skill_touch)
	skill_touch._on_gui_input(_touch(2))
	pause_touch._on_gui_input(_touch(3))
	_check(results, "two gameplay buttons accept independent touch fingers", counts == [1, 1])
	skill_touch._on_gui_input(_touch(4))
	skill_touch._input(_touch(4, false))
	_check(results, "other finger cannot retrigger or release a skill", counts[0] == 1 and skill_touch._touch_index == 2)
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	skill_touch._on_gui_input(mouse)
	_check(results, "emulated mouse does not double-activate native touch", counts[0] == 1)
	skill_touch._input(_touch(2, true, true))
	skill_touch._on_gui_input(_touch(2, true, true))
	_check(results, "Android canceled-down event cannot acquire a skill finger", skill_touch._touch_index == -1 and counts[0] == 1)
	skill.disabled = true
	skill_touch._on_gui_input(_touch(2))
	_check(results, "disabled skill cannot activate through native touch", counts[0] == 1)
	skill.disabled = false
	skill.hide()
	skill_touch._on_gui_input(_touch(2))
	_check(results, "hidden gameplay button ignores late touches", counts[0] == 1)
	pause_touch._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(results, "backgrounding retires gameplay button capture", pause_touch._touch_index == -1)


static func _joystick(results: Array, host: Control) -> void:
	var stick := TouchJoystick.new()
	host.add_child(stick)
	stick._begin(0, Vector2(50, 50))
	stick._update(Vector2(100, 50))
	stick._input(_touch(1, true, true))
	_check(results, "canceling another finger leaves movement intact", stick.is_active())
	stick._input(_touch(0, true, true))
	_check(results, "Android cancel outside joystick clears movement", not stick.is_active() and stick.get_value() == Vector2.ZERO)
	stick._gui_input(_touch(0, true, true))
	_check(results, "canceled-down event never starts the joystick", not stick.is_active())
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	stick._gui_input(mouse)
	_check(results, "touch mouse copy cannot reacquire the joystick", not stick.is_active())


static func _safe_area(results: Array, host: Control) -> void:
	var logical := Vector2(1280, 720)
	var pixels := Vector2(2560, 1440)
	var left := UiSafeArea.insets(logical, pixels, Rect2(80, 0, 2480, 1440))
	var right := UiSafeArea.insets(logical, pixels, Rect2(0, 0, 2480, 1440))
	_check(results, "physical cutout pixels scale into logical UI units", left == Vector4(40, 0, 0, 0) and right == Vector4(0, 0, 40, 0))
	_check(results, "out-of-window safe rectangle cannot invert UI", UiSafeArea.insets(logical, pixels, Rect2(4000, 0, 50, 50)) == Vector4.ZERO)
	_check(results, "oversized safe rectangle is clipped to the window", UiSafeArea.insets(logical, pixels, Rect2(-40, -10, 2640, 1460)) == Vector4.ZERO)
	_check(results, "nonfinite screen metrics do not poison touch geometry", UiSafeArea.insets(Vector2(NAN, 720), pixels, Rect2(0, 0, 2560, 1440)) == Vector4.ZERO)
	var safe := UiSafeArea.new()
	host.add_child(safe)
	var changes: Array[int] = [0]
	safe.safe_area_changed.connect(func() -> void: changes[0] += 1)
	safe._apply_margins(logical, left)
	safe._apply_margins(logical, right)
	_check(results, "180-degree notch flip updates offsets without a viewport resize", safe.offset_left == 0 and safe.offset_right == -40 and changes[0] == 2)
	safe._apply_margins(logical, right)
	_check(results, "unchanged safe-area polling does not cancel ongoing gestures", changes[0] == 2)


static func _camera(results: Array) -> void:
	var camera := CameraRig.new()
	camera._enabled = true
	camera._look_touch_index = 7
	camera._input_handler._touch_accum = Vector2(20, 5)
	camera._input(_touch(7, true, true))
	_check(results, "Android cancel clears camera finger and queued rotation", camera._look_touch_index == -1 and camera._input_handler._touch_accum == Vector2.ZERO)
	var drag := InputEventScreenDrag.new()
	drag.index = 7
	drag.position = Vector2(1100, 300)
	drag.relative = Vector2(25, 0)
	camera._unhandled_input(drag)
	_check(results, "drag leaving a control cannot start camera look without a fresh down", camera._look_touch_index == -1)
	camera._handle_look_touch(_touch(7, true, true))
	_check(results, "canceled camera down cannot claim a new gesture", camera._look_touch_index == -1)
	camera._look_touch_index = 7
	camera._notification(Node.NOTIFICATION_PAUSED)
	_check(results, "paused camera requires a new gesture on resume", camera._look_touch_index == -1)
	camera.free()


static func _audio_lifecycle(results: Array) -> void:
	var was_paused := AudioManager._application_paused
	var was_focused := AudioManager._application_focused
	var was_muted := AudioManager.is_background_muted()
	AudioManager._application_paused = false
	AudioManager._application_focused = true
	AudioManager._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	AudioManager._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(results, "focus-in cannot unmute a paused Android activity", AudioManager.is_background_muted())
	AudioManager._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	AudioManager._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_check(results, "resume beneath an unfocused overlay stays muted", AudioManager.is_background_muted())
	AudioManager._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(results, "matching Android resume and focus restore foreground audio", not AudioManager.is_background_muted())
	AudioManager._application_paused = was_paused
	AudioManager._application_focused = was_focused
	AudioManager._set_background_muted(was_muted)
