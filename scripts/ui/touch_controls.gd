class_name TouchControls
extends Control
## Input presentation only. Ownership, movement and action validation stay in
## player/GameRoot APIs. The capture region never extends under skills/actions.
signal action_declined(message: String)
var joystick: VirtualJoystick
var _buttons: Array[TouchActionButton] = []
var _last_value := Vector2.ZERO

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	joystick = VirtualJoystick.new()
	joystick.name = "MovementJoystick"
	joystick.opacity = 0.78
	add_child(joystick)
	# Larger attack target (thumb-friendly) per mobile guidelines; others balanced:
	# attack 64.0 base radius, dodge/swap 52.0. UiLayout scales these per screen.
	for entry in [["attack", "request_attack", 64.0], ["dodge", "request_dodge", 52.0], ["switch_weapon", "request_weapon_switch", 52.0]]:
		var button := TouchActionButton.new()
		button.action_name = entry[0]
		button.radius = entry[2]
		button.opacity = 0.96
		button.vibrate_on_press = entry[0] == "attack"
		var method: StringName = entry[1]
		button.pressed.connect(func() -> void:
			if not UiCommands.action(method):
				action_declined.emit("Unavailable — check stamina, cooldown or equipped slots."))
		add_child(button)
		_buttons.append(button)
	resized.connect(_layout)
	visibility_changed.connect(_on_visibility_changed)
	_layout.call_deferred()

func _layout() -> void:
	# Fallback when no plan has been pushed yet (first frame / desktop preview).
	apply_layout(UiLayout.compute(size, SaveManager.get_settings().text_scale), size)


## Place the stick and the action cluster from the shared layout solution so the
## thumb zones never overlap the skill bar, the HUD, or each other.
func apply_layout(plan: Dictionary, view: Vector2) -> void:
	if joystick == null:
		return
	var stick: Rect2 = UiLayout.sanitize(plan["stick"], view)
	joystick.position = stick.position
	joystick.size = stick.size
	joystick.radius = clampf(minf(stick.size.x, stick.size.y) * 0.42, 64.0, 96.0)
	var keys := ["attack", "dodge", "swap"]
	for i in range(_buttons.size()):
		var rect: Rect2 = UiLayout.sanitize(plan[keys[i]], view)
		var button := _buttons[i]
		button.radius = minf(rect.size.x, rect.size.y) * 0.5
		# custom_minimum_size was seeded from the button's *initial* radius in
		# _ready(); leaving it larger than the solved rect makes the Control
		# refuse to shrink and overflow the viewport on smaller screens.
		button.custom_minimum_size = rect.size
		button.position = rect.position
		button.size = rect.size
		button.queue_redraw()


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	if get_tree() != null and get_tree().paused:
		if _last_value != Vector2.ZERO:
			UiCommands.move(Vector2.ZERO)
			_last_value = Vector2.ZERO
		return
	var value := joystick.get_value()
	if not is_finite(value.x) or not is_finite(value.y):
		# Never forward a poisoned sample to the player: it would be latched into
		# locomotion until the stick is released.
		if _last_value != Vector2.ZERO:
			_last_value = Vector2.ZERO
			UiCommands.move(Vector2.ZERO)
		return
	if value != _last_value:
		_last_value = value
		UiCommands.move(value)

func cancel() -> void:
	if joystick == null:
		return
	joystick.cancel()
	for button in _buttons:
		button.cancel()
	if _last_value != Vector2.ZERO:
		UiCommands.move(Vector2.ZERO)
	_last_value = Vector2.ZERO

func _on_visibility_changed() -> void:
	if not is_visible_in_tree(): cancel()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel()

func get_debug_snapshot() -> Dictionary:
	return {"joystick_active": joystick.is_active(), "joystick_value": joystick.get_value()}


func set_high_contrast(enabled: bool) -> void:
	if joystick != null and joystick.has_method("set_rest_alpha"):
		joystick.set_rest_alpha(1.0 if enabled else 0.75)
	elif joystick != null:
		joystick.modulate.a = 1.0 if enabled else 0.75
	for button in _buttons: button.modulate.a = 1.0 if enabled else 0.88
	if joystick != null and not enabled:
		joystick.set_rest_alpha(0.7)
