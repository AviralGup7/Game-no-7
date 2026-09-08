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
	joystick.opacity = 0.75
	add_child(joystick)
	for entry in [["attack", "request_attack", 60.0], ["dodge", "request_dodge", 48.0], ["switch_weapon", "request_weapon_switch", 48.0]]:
		var button := TouchActionButton.new()
		button.action_name = entry[0]
		button.radius = entry[2]
		button.opacity = 0.95
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
	if joystick == null:
		return
	joystick.position = Vector2(12, maxf(160, size.y - 280))
	joystick.size = Vector2(minf(size.x * 0.30, 340), minf(264, size.y - 172))
	joystick.radius = clampf(size.y * 0.12, 64, 90)
	var positions := [Vector2(-136, -148), Vector2(-252, -110), Vector2(-244, -222)]
	for i in range(_buttons.size()):
		var b := _buttons[i]
		b.position = size + positions[i]
		b.size = Vector2.ONE * b.radius * 2

func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var value := joystick.get_value()
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
	if joystick != null: joystick.modulate.a = 1.0 if enabled else 0.75
	for button in _buttons: button.modulate.a = 1.0 if enabled else 0.95

## Hardened: clamp touch deadzone.
func _validated_touch_deadzone(d: float) -> float:
    if not is_finite(d) or d < 0.0:
        return 0.2
    return clampf(d, 0.05, 1.0)

