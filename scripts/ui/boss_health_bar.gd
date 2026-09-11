class_name BossHealthBar
extends VBoxContainer

## Top-of-screen boss frame: name + phase pips + health bar with ghost (recent
## damage) trailing. Binds on EventBus.boss_spawned, tracks the boss's
## HealthComponent, hides on death/run end. Code-built, no scene assets.

var _name_label: Label = null
var _phase_label: Label = null
var _bar: ProgressBar = null
var _ghost: ProgressBar = null
var _boss: EnemyBase = null
var _health: HealthComponent = null
var _ghost_value := 1.0
var _reduced_motion := false
var _health_label: Label
var _fade_tween: Tween = null
var _spawn_token := 0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_font_override("font", UiTheme.BOLD)
	_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_name_label.add_theme_constant_override("outline_size", 5)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_name_label)
	_phase_label = Label.new()
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_font_size_override("font_size", 15)
	_phase_label.modulate = UiTheme.GOLD
	_phase_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_phase_label)
	_health_label = UiFactory.label("", self, 18)
	_health_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_health_label.add_theme_constant_override("outline_size", 4)
	add_theme_constant_override("separation", 2)
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


## Build one layered meter bar. Because the ghost + live fill must stack inside
## a fixed-height Control, they use full-rect anchoring here (the HUD's simple
## gauges use UiFactory.gauge instead). The fill still reuses the shared
## UiTheme.bar styling token so boss/HUD meters read identically.
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
	bg.set_corner_radius_all(UiTheme.RADIUS_SM)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", UiTheme.bar(fill))
	return bar


func _on_boss_spawned(boss: Node, _boss_id: StringName) -> void:
	_unbind()
	_spawn_token += 1
	var enemy := boss as EnemyBase
	_boss = enemy
	_name_label.text = _boss_name(boss)
	_phase_label.text = "BOSS ENCOUNTER"
	_ghost_value = 1.0
	_bar.value = 1.0
	_ghost.value = 1.0
	if enemy != null:
		_health = enemy.get_health_component()
		if _health != null:
			_health.health_changed.connect(_on_health_changed)
			_on_health_changed(_health.current_health, _health.max_health)
		if not enemy.died.is_connected(_on_boss_died):
			enemy.died.connect(_on_boss_died)
	visible = true
	_fade_to(1.0, 0.25)


func _boss_name(boss: Node) -> String:
	var enemy := boss as EnemyBase
	if enemy != null:
		var cfg := enemy.get_config()
		if cfg != null and not String(cfg.display_name).is_empty():
			return String(cfg.display_name)
	return "Boss"


func _on_health_changed(current: float, maximum: float) -> void:
	if not is_finite(current) or not is_finite(maximum) or maximum <= 0.0:
		return
	_bar.value = clampf(current / maximum, 0.0, 1.0)
	_health_label.text = "%d / %d HP" % [ceili(current), ceili(maximum)]


func _on_phase_changed(boss: Node, phase: int, max_phases: int) -> void:
	if boss != _boss:
		return
	var controller := boss.get_node_or_null("BossController") as BossController if boss != null else null
	var pname := ""
	if controller != null:
		pname = String(controller.phase_name())
	_phase_label.text = "Phase %d/%d — %s" % [phase + 1, max_phases, pname]


func _on_boss_died() -> void:
	_hide_bar()


func _on_run_ended(_score: int, _wave: int, _best: int) -> void:
	_hide_bar()


## Soft show/hide instead of blinking: fade in on spawn, fade out on death or
## run end. Instant when reduced motion is on or the node is off-tree.
func _fade_to(target: float, duration: float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	if _reduced_motion or not is_inside_tree():
		modulate.a = target
		return
	var tween := create_tween()
	_fade_tween = tween
	tween.tween_property(self, "modulate:a", target, duration)


func _hide_bar() -> void:
	_unbind()
	_spawn_token += 1
	var token := _spawn_token
	if _reduced_motion or not is_inside_tree():
		visible = false
		return
	_fade_to(0.0, 0.3)
	var tween := create_tween()
	tween.tween_interval(0.3)
	# A new boss may spawn during the fade; only hide when nothing replaced us.
	tween.tween_callback(func() -> void:
		if token == _spawn_token:
			visible = false)


func _unbind() -> void:
	if _health != null and is_instance_valid(_health) and _health.health_changed.is_connected(_on_health_changed):
		_health.health_changed.disconnect(_on_health_changed)
	if _boss != null and is_instance_valid(_boss) and _boss.died.is_connected(_on_boss_died):
		_boss.died.disconnect(_on_boss_died)
	_boss = null
	_health = null


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _bar == null:
		return
	if not is_finite(delta) or delta <= 0.0:
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

