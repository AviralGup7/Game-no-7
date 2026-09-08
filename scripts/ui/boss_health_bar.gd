class_name BossHealthBar
extends VBoxContainer

## Top-of-screen boss frame: name + phase pips + health bar with ghost (recent
## damage) trailing. Binds on EventBus.boss_spawned, tracks the boss's
## HealthComponent, hides on death/run end. Code-built, no scene assets.

var _name_label: Label = null
var _phase_label: Label = null
var _bar: ProgressBar = null
var _ghost: ProgressBar = null
var _boss: Node = null
var _health: Node = null
var _ghost_value := 1.0
var _reduced_motion := false
var _health_label: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 20)
	add_child(_name_label)
	_phase_label = Label.new()
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_font_size_override("font_size", 13)
	add_child(_phase_label)
	_health_label = UiFactory.label("", self, 18)
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(0, 16)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	_ghost = _make_bar(Color(1.0, 0.85, 0.3))
	stack.add_child(_ghost)
	_bar = _make_bar(Color(0.85, 0.15, 0.3))
	_bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	stack.add_child(_bar)
	if EventBus != null:
		if not EventBus.boss_spawned.is_connected(_on_boss_spawned):
			EventBus.boss_spawned.connect(_on_boss_spawned)
		if not EventBus.boss_phase_changed.is_connected(_on_phase_changed):
			EventBus.boss_phase_changed.connect(_on_phase_changed)
		if not EventBus.run_ended.is_connected(_on_run_ended):
			EventBus.run_ended.connect(_on_run_ended)


func _make_bar(fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


func _on_boss_spawned(boss: Node, _boss_id: StringName) -> void:
	_unbind()
	_boss = boss
	_name_label.text = _boss_name(boss)
	_phase_label.text = "BOSS ENCOUNTER"
	_ghost_value = 1.0
	_bar.value = 1.0
	_ghost.value = 1.0
	if boss is Node:
		_health = (boss as Node).get_node_or_null("HealthComponent")
		if _health != null and _health.has_signal("health_changed"):
			_health.health_changed.connect(_on_health_changed)
			_on_health_changed(_health.current_health, _health.max_health)
		if boss.has_signal("died"):
			boss.died.connect(_on_boss_died)
	visible = true


func _boss_name(boss: Node) -> String:
	if boss != null and boss.has_method("get_config"):
		var cfg: Variant = boss.call("get_config")
		if cfg != null and not String(cfg.get("display_name")).is_empty():
			return String(cfg.get("display_name"))
	return "Boss"


func _on_health_changed(current: float, maximum: float) -> void:
	if maximum <= 0.0:
		return
	_bar.value = clampf(current / maximum, 0.0, 1.0)
	_health_label.text = "%d / %d HP" % [ceili(current), ceili(maximum)]


func _on_phase_changed(boss: Node, phase: int, max_phases: int) -> void:
	if boss != _boss:
		return
	var controller := (boss as Node).get_node_or_null("BossController") if boss is Node else null
	var pname := ""
	if controller != null and controller.has_method("phase_name"):
		pname = String(controller.call("phase_name"))
	_phase_label.text = "Phase %d/%d — %s" % [phase + 1, max_phases, pname]


func _on_boss_died() -> void:
	visible = false
	_unbind()


func _on_run_ended(_score: int, _wave: int, _best: int) -> void:
	visible = false
	_unbind()


func _unbind() -> void:
	if _health != null and is_instance_valid(_health) and _health.has_signal("health_changed") and _health.health_changed.is_connected(_on_health_changed):
		_health.health_changed.disconnect(_on_health_changed)
	if _boss != null and is_instance_valid(_boss) and (_boss as Node).has_signal("died") and (_boss as Node).died.is_connected(_on_boss_died):
		(_boss as Node).died.disconnect(_on_boss_died)
	_boss = null
	_health = null


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _bar == null:
		return
	# Ghost bar eases toward the real value (recent-damage readability).
	if _reduced_motion: _ghost_value = float(_bar.value)
	_ghost_value = lerpf(_ghost_value, float(_bar.value), minf(delta * 2.5, 1.0))
	if _ghost_value < float(_bar.value):
		_ghost_value = float(_bar.value)
	_ghost.value = _ghost_value


func set_reduced_motion(value: bool) -> void:
	_reduced_motion = value
	if value and _bar != null:
		_ghost_value = float(_bar.value)
