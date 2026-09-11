class_name TouchControls
extends Control
## Input presentation only. Ownership, movement and action validation stay in
## player/GameRoot APIs. The capture region never extends under skills/actions.
signal action_declined(message: String)
var joystick: TouchJoystick
var _buttons: Array[TouchActionButton] = []
var _last_value := Vector2.ZERO

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	joystick = TouchJoystick.new()
	joystick.name = "MovementJoystick"
	joystick.opacity = 0.78
	add_child(joystick)
	# Larger attack target (thumb-friendly) per mobile guidelines; others balanced:
	# attack 64.0 base radius, dodge/swap 52.0. UiLayout scales these per screen.
	for entry in [["attack", "request_attack", 64.0], ["dodge", "request_dodge", 52.0], ["switch_weapon", "request_weapon_switch", 52.0], ["reload", "request_reload", 52.0]]:
		var button := TouchActionButton.new()
		button.action_name = entry[0]
		button.radius = entry[2]
		button.opacity = 0.96
		button.vibrate_on_press = entry[0] == "attack"
		var method: StringName = entry[1]
		button.pressed.connect(_on_button_pressed.bind(method))
		button.fire_input_changed.connect(UiCommands.fire_input)
		add_child(button)
		_buttons.append(button)
	# Layout + stuck-input backstops. These MUST live here, not in the press
	# handler below: UiRoot pushes the safe-area-aware plan via apply_layout(),
	# and this fallback only covers the first frame / a missing plan. Wiring it
	# per-press re-connected the signals on every declined tap (engine errors)
	# and stomped the safe-area plan with a full-rect recompute mid-combat.
	if not resized.is_connected(_layout):
		resized.connect(_layout)
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	_layout.call_deferred()


## Single guarded entry point for every touch action button (attack / dodge / swap).
## A declined command is normal gameplay (stamina, cooldown, holstered slot) and
## surfaces as a toast; an unexpected failure is reported through EventBus so a
## device-side problem is visible in the log instead of looking like a dead button.
func _on_button_pressed(command: StringName) -> void:
	if command == &"request_attack":
		# FIRE publishes held/aim state; it never requests frame-rate-driven shots.
		return
	if UiCommands.action(command):
		return
	action_declined.emit("Unavailable — check magazine, stamina, cooldown or equipped slots.")

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
	# Diameter must fit inside the solved stick rect: a 64 px floor used to
	# overflow a compact/short stick (110 px) and draw over the skill bar.
	var stick_short := minf(stick.size.x, stick.size.y)
	var max_r := maxf(stick_short * 0.5 - 6.0, 24.0)
	joystick.radius = clampf(stick_short * 0.42, minf(64.0, max_r), minf(96.0, max_r))
	var keys := ["attack", "dodge", "swap", "reload"]
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
	# No paused branch: this control runs PROCESS_MODE_INHERIT, so _process
	# never executes while the tree is paused and such a branch would be dead
	# code. Pause-time cleanup is owned by UiRoot._show_screen, which calls
	# cancel() (zeroing _last_value through the same path as hide/focus-out).
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
	UiCommands.fire_input(false, Vector2.ZERO)
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
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		cancel()

func get_debug_snapshot() -> Dictionary:
	return {"joystick_active": joystick.is_active(), "joystick_value": joystick.get_value()}


func set_high_contrast(enabled: bool) -> void:
	if joystick != null:
		joystick.set_rest_alpha(1.0 if enabled else 0.75)
	for button in _buttons: button.modulate.a = 1.0 if enabled else 0.88


func _exit_tree() -> void:
	UiCommands.fire_input(false, Vector2.ZERO)
