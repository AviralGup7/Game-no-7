class_name CampaignHud
extends Control
## Touch-first campaign chrome. Reuses combat controls and vitals, but deliberately
## has no score/combo, wave counter, arena selector or run-key readout.

signal map_requested
var director: CampaignDirector
var _touch: TouchControls
var _skills: SkillBar
var _gauges: UiGauges
var _vitals: PanelContainer
var _top: PanelContainer
var _location: Label
var _mission: Label
var _mini: CampaignMap
var _interact: Button
var _boss: BossHealthBar
var _toast: Label
var _message_until := 0
var _refresh := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top = PanelContainer.new()
	_top.add_theme_stylebox_override("panel", UiTheme.box(Color(0.035, 0.065, 0.11, 0.92)))
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_top.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	_location = UiFactory.title("STATION ZERO", info, 22)
	_mission = UiFactory.label("", info, 18)
	for label in [_location, _mission]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_location.modulate = UiTheme.CYAN
	var chart := UiFactory.button("MAP", row, 20, Vector2(100, 88))
	TouchButtonInput.attach(chart)
	chart.pressed.connect(func() -> void: map_requested.emit())
	var pause := UiFactory.button("PAUSE", row, 20, Vector2(112, 88))
	TouchButtonInput.attach(pause)
	pause.pressed.connect(GameRoot.request_pause)
	_vitals = PanelContainer.new()
	_vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vitals.add_theme_stylebox_override("panel", UiTheme.box(Color(0.035, 0.065, 0.11, 0.88)))
	add_child(_vitals)
	_gauges = UiGauges.new()
	_vitals.add_child(_gauges)
	_mini = CampaignMap.new()
	_mini.compact = true
	add_child(_mini)
	_boss = BossHealthBar.new()
	add_child(_boss)
	_touch = TouchControls.new()
	add_child(_touch)
	_touch.action_declined.connect(show_message)
	_skills = SkillBar.new()
	add_child(_skills)
	_skills.action_declined.connect(show_message)
	_interact = UiFactory.button("INTERACT", self, 22, Vector2(240, 88))
	TouchButtonInput.attach(_interact)
	_interact.pressed.connect(func() -> void:
		if is_instance_valid(director):
			director.try_interact())
	_toast = UiFactory.label("", self, 22)
	_toast.autowrap_mode = TextServer.AUTOWRAP_OFF
	_toast.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 5)
	resized.connect(apply_layout)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			cancel_input())


func bind(session: CampaignDirector) -> void:
	director = session
	if director != null:
		_mini.bind(director.definition, director)
		_skills.bind_controller(director.player.get_skill_controller())
		_refresh_values()
	else:
		_skills.bind_controller(null)
		_mini.director = null


func apply_layout() -> void:
	if _touch == null:
		return
	var scale := SaveManager.get_settings().text_scale
	var plan := UiLayout.compute(size, scale)
	var pad := UiLayout.gutter(size)
	_touch.apply_layout(plan, size)
	_skills.fit_touch_targets((plan.skills as Rect2).size)
	UiLayout.place(_skills, plan.skills, size)
	var top := Rect2(pad, pad, size.x - pad * 2, maxf(108, 60 * scale))
	UiLayout.place(_top, top, size)
	var controls_top := minf((plan.stick as Rect2).position.y, (plan.attack as Rect2).position.y)
	var available := maxf(controls_top - top.end.y - 24, 0)
	var vitals := Rect2(pad, top.end.y + 12, clampf(size.x * 0.26, 240, 340), minf(150 * scale + 36, available))
	UiLayout.place(_vitals, vitals, size)
	_gauges.set_compact(scale > 1.3)
	_vitals.visible = available >= 150
	var mini_size := minf(180, available)
	UiLayout.place(_mini, Rect2(size.x - pad - mini_size, top.end.y + 12, mini_size, mini_size), size)
	var skills: Rect2 = plan.skills
	var interaction := Rect2(skills.get_center().x - 132, skills.position.y - 100, 264, 88)
	UiLayout.place(_interact, interaction, size)
	var middle_left := vitals.end.x + 12
	var middle_width := maxf(_mini.position.x - middle_left - 12, 1)
	var boss_height := 110.0 * maxf(scale, 1.0)
	UiLayout.place(_boss, Rect2(middle_left, top.end.y + 12, middle_width, boss_height), size)
	var toast_top := top.end.y + boss_height + 24
	var toast_height := maxf(minf(56, interaction.position.y - toast_top - 12), 0)
	_toast.set_meta("fits", toast_height >= 24 * scale)
	UiLayout.place(_toast, Rect2(middle_left, toast_top, middle_width, toast_height), size)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_refresh += delta
	if _refresh >= 0.15:
		_refresh = 0.0
		_refresh_values()
	_toast.visible = Time.get_ticks_msec() < _message_until and bool(_toast.get_meta("fits", true))


func _refresh_values() -> void:
	if not is_instance_valid(director) or not is_instance_valid(director.player):
		return
	var player := director.player
	var sector := director.definition.sector_at(player.global_position)
	_location.text = String(sector.get("name", "SERVICE CAUSEWAY"))
	var mission := director.current_mission()
	_mission.text = "STATION SECURED / Explore remaining supply lockers" if mission.is_empty() else "%02d / %02d  %s  ·  %dm" % [
		int(director.progress.mission) + 1, director.definition.missions.size(), String(mission.title), ceili(director.distance_to_target())]
	var hp := player.get_health_component()
	_gauges.set_health(hp.get_current(), hp.get_max())
	var stamina := player.get_stamina_component()
	_gauges.set_stamina(stamina.get_current(), stamina.get_max())
	var xp := player.get_experience_component()
	_gauges.set_xp(xp.get_level(), xp.get_xp(), ExperienceComponent.xp_for_level(xp.get_level()))
	var weapon := player.get_weapon_manager().active_instance()
	if weapon != null and weapon.config != null:
		var status := "RELOAD %.1fs" % weapon.reload_remaining() if weapon.is_reloading() else "%d / %d" % [weapon.ammo, weapon.config.ammo_per_magazine]
		_gauges.set_weapon_text("%s / %s" % [weapon.config.display_name, status], "Hold FIRE and slide to aim")
	var item := director.nearest_interaction()
	_interact.visible = not item.is_empty()
	_interact.text = "BOARD" if item.get("kind", "") == "extraction" else "INTERACT"
	_interact.tooltip_text = String(item.get("name", ""))
	if not item.is_empty():
		_mission.text = String(item.name)
		if item.kind != "cache" and director.remaining_guards() > 0:
			_mission.text += " / SECURE DISTRICT FIRST"
	elif director.remaining_guards() > 0:
		_mission.text = "%s / %d HOSTILES / %dm" % [String(mission.get("title", "")), director.remaining_guards(), ceili(director.distance_to_target())]
	_mini.queue_redraw()


func show_message(text: String) -> void:
	_toast.text = text
	_message_until = Time.get_ticks_msec() + 5500


func apply_settings(settings: SettingsData) -> void:
	_touch.set_high_contrast(settings.high_contrast)
	_boss.set_reduced_motion(settings.reduced_motion)
	apply_layout.call_deferred()


func cancel_input() -> void:
	if _touch != null:
		_touch.cancel()
	if _skills != null:
		_skills.cancel_touch_input()


func get_debug_snapshot() -> Dictionary:
	return {"touch": _touch.get_debug_snapshot(), "interaction_visible": _interact.visible,
		"top": _top.get_rect(), "interact": _interact.get_rect()}
