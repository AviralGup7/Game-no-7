class_name SkillBar
extends HBoxContainer

## Three skill slots with cooldown radial, key hints, lock state and touch
## buttons. Binds to a SkillController (player child) and refreshes at 10 Hz.
## Builds its slots in code so it works without extra scene assets.

signal action_declined(message: String)

const SLOT_COUNT := 3
const REFRESH_INTERVAL := 0.1

var _buttons: Array[Button] = []
var _cooldown_labels: Array[Label] = []
var _controller: SkillController = null
var _accum := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	for i in range(SLOT_COUNT):
		_buttons.append(_make_slot(i))
	_locate_controller()
	EventBus.run_started.connect(func(_id: int, _seed: int) -> void:
		bind_controller(null)
		_locate_controller())


func _make_slot(index: int) -> Button:
	var wrapper := VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_theme_constant_override("separation", 0)
	var button := Button.new()
	button.custom_minimum_size = Vector2(UiLayout.MIN_TOUCH, UiLayout.MIN_TOUCH)
	button.clip_text = true
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 18)
	button.text = "—"
	button.disabled = true
	var slot := index
	button.pressed.connect(func() -> void: _on_slot_pressed(slot))
	wrapper.add_child(button)
	var cd := Label.new()
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cd.add_theme_font_size_override("font_size", 16)
	cd.add_theme_color_override("font_outline_color", Color.BLACK)
	cd.add_theme_constant_override("outline_size", 4)
	cd.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cd.text = ""
	wrapper.add_child(cd)
	_cooldown_labels.append(cd)
	add_child(wrapper)
	return button


func _locate_controller() -> void:
	if _controller != null and is_instance_valid(_controller):
		return
	if GameRoot != null and GameRoot.get_active_player() != null:
		var skills := GameRoot.get_active_player().get_skill_controller()
		if skills != null:
			bind_controller(skills)
			return
	if is_inside_tree():
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			var skills2 := (players[0] as Player).get_skill_controller()
			if skills2 != null:
				bind_controller(skills2)


func bind_controller(controller: SkillController) -> void:
	if is_instance_valid(_controller) and _controller.skill_cooldown_started.is_connected(_on_cooldown_event):
		_controller.skill_cooldown_started.disconnect(_on_cooldown_event)
	if is_instance_valid(_controller) and _controller.has_signal("skill_became_ready") and _controller.skill_became_ready.is_connected(_on_skill_ready):
		_controller.skill_became_ready.disconnect(_on_skill_ready)
	_controller = controller
	if _controller != null:
		_controller.skill_cooldown_started.connect(_on_cooldown_event)
		if _controller.has_signal("skill_became_ready"):
			_controller.skill_became_ready.connect(_on_skill_ready)
		_refresh_all()


## SkillController.skill_cooldown_started(skill_id, duration) — 2 args.
func _on_cooldown_event(_skill_id: StringName, _duration: float) -> void:
	_refresh_all()


## SkillController.skill_became_ready(skill_id) — 1 arg. Must stay a separate
## handler: connecting the 2-arg callable above to this signal raises a runtime
## "too few arguments" error every time a skill comes off cooldown.
func _on_skill_ready(_skill_id: StringName) -> void:
	_refresh_all()


func _on_slot_pressed(slot: int) -> void:
	if not UiCommands.action(&"request_skill", [slot]):
		action_declined.emit("Skill unavailable — check stamina, cooldown and unlock level.")


func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_accum += delta
	if _accum < REFRESH_INTERVAL:
		return
	_accum = 0.0
	if _controller == null or not is_instance_valid(_controller):
		_locate_controller()
	_refresh_all()


func _refresh_all() -> void:
	for i in range(SLOT_COUNT):
		_refresh_slot(i)


func _refresh_slot(i: int) -> void:
	var button := _buttons[i]
	var cd := _cooldown_labels[i]
	if not is_instance_valid(_controller):
		button.text = "—"
		button.disabled = true
		cd.text = "EMPTY"
		button.icon = null
		return
	var cfg := _controller.slot_skill(i)
	if cfg == null:
		button.text = "—"
		button.disabled = true
		cd.text = "EMPTY"
		button.icon = null
		return
	# Long skill names clip inside a square touch target; abbreviate when narrow.
	button.text = cfg.display_name if button.custom_minimum_size.x >= 150.0 else _short_name(cfg)
	button.tooltip_text = "%s\n%s" % [cfg.display_name, cfg.description]
	button.icon = cfg.icon
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 24)
	var unlocked := _controller.is_unlocked(cfg.skill_id)
	var remaining := _controller.slot_cooldown(i)
	# Visual feedback: locked slots read as inert, cooling slots read as pending,
	# ready slots read at full strength with a cyan caption.
	if not unlocked:
		button.disabled = true
		button.modulate = Color(1, 1, 1, 0.45)
		cd.text = "LOCKED Lv%d" % cfg.unlock_level
		cd.modulate = UiTheme.MUTED
	elif remaining > 0.0:
		button.disabled = true
		button.modulate = Color(1, 1, 1, 0.7)
		cd.text = "%.1fs" % remaining
		cd.modulate = UiTheme.GOLD
	else:
		button.disabled = false
		button.modulate = Color.WHITE
		cd.text = _key_hint(i)
		cd.modulate = UiTheme.CYAN


func _short_name(cfg: SkillConfig) -> String:
	var words := String(cfg.display_name).split(" ")
	var out := ""
	for w in words:
		if not w.is_empty():
			out += w.left(1)
	return out.left(3)


func _key_hint(index: int) -> String:
	var cfg := _controller.slot_skill(index) if _controller != null else null
	if cfg == null:
		return ""
	return UiCommands.binding(cfg.input_action) + " / READY"


## Size the three slots to fill the allocated bar while never dropping below the
## Android touch-target floor. Takes the bar rect (not the viewport width) so it
## stays correct in portrait, on tablets and at large text scales.
func fit_touch_targets(bar_size: Vector2) -> void:
	var separation := 8.0
	var available := maxf(bar_size.x - separation * float(SLOT_COUNT - 1), UiLayout.MIN_TOUCH)
	var width := maxf(available / float(SLOT_COUNT), UiLayout.MIN_TOUCH)
	# Reserve room for the cooldown/hint caption beneath each button.
	var height := clampf(bar_size.y - 26.0, UiLayout.MIN_TOUCH, 132.0)
	for button in _buttons:
		button.custom_minimum_size = Vector2(width, height)


