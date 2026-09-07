class_name SkillBar
extends HBoxContainer

## Three skill slots with cooldown radial, key hints, lock state and touch
## buttons. Binds to a SkillController (player child) and refreshes at 10 Hz.
## Builds its slots in code so it works without extra scene assets.

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


func _make_slot(index: int) -> Button:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 0)
	var button := Button.new()
	button.custom_minimum_size = Vector2(64, 64)
	button.focus_mode = Control.FOCUS_NONE
	button.text = "—"
	button.disabled = true
	var slot := index
	button.pressed.connect(func() -> void: _on_slot_pressed(slot))
	wrapper.add_child(button)
	var cd := Label.new()
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd.add_theme_font_size_override("font_size", 13)
	cd.text = ""
	wrapper.add_child(cd)
	_cooldown_labels.append(cd)
	add_child(wrapper)
	return button


func _locate_controller() -> void:
	if _controller != null and is_instance_valid(_controller):
		return
	if GameRoot != null and GameRoot.get_active_player() != null:
		var skills := (GameRoot.get_active_player() as Node).get_node_or_null("SkillController") as SkillController
		if skills != null:
			bind_controller(skills)
			return
	if is_inside_tree():
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			var skills2 := (players[0] as Node).get_node_or_null("SkillController") as SkillController
			if skills2 != null:
				bind_controller(skills2)


func bind_controller(controller: SkillController) -> void:
	if _controller != null and _controller.skill_cooldown_started.is_connected(_on_cooldown_event):
		_controller.skill_cooldown_started.disconnect(_on_cooldown_event)
	_controller = controller
	if _controller != null:
		_controller.skill_cooldown_started.connect(_on_cooldown_event)
		_refresh_all()


func _on_cooldown_event(_skill_id: StringName, _duration: float) -> void:
	_refresh_all()


func _on_slot_pressed(slot: int) -> void:
	if _controller != null:
		_controller.try_cast_slot(slot)


func _process(delta: float) -> void:
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
	if _controller == null:
		button.text = "—"
		button.disabled = true
		cd.text = ""
		return
	var cfg := _controller.slot_skill(i)
	if cfg == null:
		button.text = "—"
		button.disabled = true
		cd.text = ""
		return
	button.text = _short_name(cfg)
	var unlocked := _controller.is_unlocked(cfg.skill_id)
	var remaining := _controller.slot_cooldown(i)
	if not unlocked:
		button.disabled = true
		button.modulate = Color(0.45, 0.45, 0.45)
		cd.text = "Lv%d" % cfg.unlock_level
	elif remaining > 0.0:
		button.disabled = true
		button.modulate = Color(0.7, 0.7, 0.8)
		cd.text = "%.1f" % remaining
	else:
		button.disabled = false
		button.modulate = Color.WHITE
		cd.text = _key_hint(i)


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
	match String(cfg.input_action):
		"skill_1":
			return "Q"
		"skill_2":
			return "E"
		"skill_3":
			return "R"
	return ""
