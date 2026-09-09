class_name GameHud
extends Control
## Display-only meters. Events provide updates; run_started seeds component
## snapshots because world construction may emit its first values before binding.
var _hp_label: Label
var _hp_bar: ProgressBar
var _stamina_label: Label
var _stamina_bar: ProgressBar
var _xp_label: Label
var _xp_bar: ProgressBar
var _score_label: Label
var _wave_label: Label
var _combo_label: Label
var _currency_label: Label
var _weapon_label: Label
var _objective_label: Label
var _toast_label: Label
var _toast_show_until := 0
var _experience: ExperienceComponent
var _vitals: VBoxContainer
var _top: HBoxContainer
var _top_scrim: PanelContainer
var _vitals_scrim: PanelContainer
var _pause_button: Button
var _compact := false
var _toast_fits := true
var _weapon_refresh := 0.0
var _last_hp := 0.0
var _last_hp_max := 0.0
var _last_stamina := 0.0
var _last_stamina_max := 0.0

func _ready() -> void:
	name = "GameplayHUD"
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	# Top strip: a scrim panel keeps wave/score readable over bright arena floors.
	_top_scrim = PanelContainer.new()
	_top_scrim.mouse_filter = MOUSE_FILTER_IGNORE
	_top_scrim.add_theme_stylebox_override("panel", _scrim())
	# Clip so a long label can never bleed past the solved rect onto gameplay.
	_top_scrim.clip_contents = true
	add_child(_top_scrim)
	_top = HBoxContainer.new()
	_top.mouse_filter = MOUSE_FILTER_IGNORE
	_top.add_theme_constant_override("separation", 12)
	_top.alignment = BoxContainer.ALIGNMENT_CENTER
	_top_scrim.add_child(_top)
	_wave_label = UiFactory.title("WAVE 1", _top, 24)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_wave_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wave_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_wave_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_combo_label = UiFactory.label("", _top, 20)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_combo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_combo_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_combo_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_combo_label.modulate = UiTheme.GOLD
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	_top.add_child(spacer)
	_currency_label = UiFactory.label("COINS 0", _top, 20)
	_currency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_currency_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_currency_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_currency_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_score_label = UiFactory.title("SCORE 0", _top, 24)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_score_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Pause is the only interactive HUD widget: keep it at a full touch target.
	_pause_button = UiFactory.button(
		"PAUSE", _top, 20, Vector2(UiLayout.MIN_TOUCH * 1.4, UiLayout.MIN_TOUCH)
	)
	_pause_button.size_flags_vertical = SIZE_SHRINK_CENTER
	_pause_button.tooltip_text = "Pause the run"
	UiTheme.decorate(_pause_button, "pause")
	_pause_button.pressed.connect(func() -> void: GameRoot.request_pause())
	# Vitals: scrim panel so the meters read against any arena theme.
	_vitals_scrim = PanelContainer.new()
	_vitals_scrim.mouse_filter = MOUSE_FILTER_IGNORE
	_vitals_scrim.add_theme_stylebox_override("panel", _scrim())
	_vitals_scrim.clip_contents = true
	add_child(_vitals_scrim)
	_vitals = VBoxContainer.new()
	_vitals.add_theme_constant_override("separation", 4)
	_vitals.mouse_filter = MOUSE_FILTER_IGNORE
	_vitals_scrim.add_child(_vitals)
	_hp_label = _vital_label("HEALTH —", 20, true)
	_hp_bar = _meter(_vitals, Color("70e0a0"))
	_stamina_label = _vital_label("STAMINA —", 18, false)
	_stamina_bar = _meter(_vitals, UiTheme.GOLD)
	_xp_label = _vital_label("LEVEL 1  /  XP 0", 18, false)
	_xp_bar = _meter(_vitals, UiTheme.CYAN)
	_weapon_label = _vital_label("WEAPON —", 20, false)
	_weapon_label.modulate = UiTheme.MUTED
	# Objective line: hidden for wave/survival modes, shown for defend / collect.
	_objective_label = _vital_label("", 18, false)
	_objective_label.modulate = UiTheme.CYAN
	_objective_label.visible = false
	_toast_label = UiFactory.label("", self, 22)
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast_label.add_theme_constant_override("outline_size", 6)
	_toast_label.visible = false
	EventBus.run_started.connect(func(_id: int, _seed: int) -> void: seed_from_run())
	EventBus.player_health_changed.connect(set_health)
	EventBus.stamina_changed.connect(set_stamina)
	EventBus.score_changed.connect(func(value: int, _delta: int) -> void: set_score(value))
	EventBus.currency_changed.connect(func(value: int, _delta: int) -> void: set_currency(value))
	EventBus.combo_changed.connect(func(value: int, _best: int) -> void: set_combo(value))
	EventBus.wave_started.connect(func(wave: int, planned: int) -> void: _wave_progress(wave, 0, planned))
	EventBus.wave_progressed.connect(_wave_progress)
	EventBus.weapon_equipped.connect(func(id: StringName, _slot: int) -> void: set_weapon(id))
	EventBus.weapon_switched.connect(func(_old: StringName, id: StringName) -> void: set_weapon(id))
	EventBus.objective_progress.connect(func(label: String, _p: int, _t: int) -> void: set_objective(label))

## Translucent backing so HUD text stays legible over bright arena surfaces
## without hiding gameplay behind an opaque plate.
func _scrim() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.55)
	style.border_color = Color(UiTheme.EDGE.r, UiTheme.EDGE.g, UiTheme.EDGE.b, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _vital_label(text: String, font_size: int, bold: bool) -> Label:
	var label := UiFactory.label(text, _vitals, font_size) if not bold else UiFactory.title(text, _vitals, font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _meter(parent: Control, color: Color) -> ProgressBar:
	var meter := ProgressBar.new()
	meter.custom_minimum_size.y = 12
	meter.max_value = 1
	meter.show_percentage = false
	meter.mouse_filter = MOUSE_FILTER_IGNORE
	var fill := UiTheme.box(color, color, 0)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	meter.add_theme_stylebox_override("fill", fill)
	var bg := UiTheme.box(UiTheme.INK)
	bg.content_margin_top = 0
	bg.content_margin_bottom = 0
	meter.add_theme_stylebox_override("background", bg)
	parent.add_child(meter)
	return meter

func seed_from_run() -> void:
	var run := GameRoot.get_run()
	if run == null:
		return
	set_score(run.score)
	set_currency(run.currency)
	set_wave(run.current_wave)
	set_combo(run.combo)
	# Objective line resets each run; the director re-emits it for defend/collect.
	set_objective("")
	_toast_label.visible = false
	var player := GameRoot.get_active_player()
	if is_instance_valid(_experience) and _experience.xp_changed.is_connected(_on_xp):
		_experience.xp_changed.disconnect(_on_xp)
	_experience = null
	if not is_instance_valid(player): return
	var hp := player.get_health_component()
	if hp != null: set_health(hp.current_health, hp.max_health)
	var stamina := player.get_stamina_component()
	if stamina != null: set_stamina(stamina.get_current(), stamina.get_max())
	_experience = player.get_experience_component()
	if _experience != null:
		_experience.xp_changed.connect(_on_xp)
		_on_xp(_experience.get_xp(), _experience.get_level(), _experience.get_xp(), ExperienceComponent.xp_for_level(_experience.get_level()))
	set_weapon(player.get_weapon_manager().active_weapon_id())

func set_health(current: float, maximum: float) -> void:
	_last_hp = current
	_last_hp_max = maximum
	if not is_finite(current) or not is_finite(maximum) or maximum <= 0.0:
		_hp_bar.value = 0.0
	else:
		_hp_bar.value = clampf(current / maximum, 0, 1)
	var low := _hp_bar.value <= 0.25
	_hp_label.text = "%s %d/%d" % [("LOW HP" if low else "HP") if _compact else ("LOW HEALTH" if low else "HEALTH"), ceili(current), ceili(maximum)]
	_hp_label.modulate = UiTheme.GOLD if low else Color.WHITE

func set_stamina(current: float, maximum: float) -> void:
	_last_stamina = current
	_last_stamina_max = maximum
	if not is_finite(current) or not is_finite(maximum) or maximum <= 0.0:
		_stamina_bar.value = 0.0
	else:
		_stamina_bar.value = clampf(current / maximum, 0, 1)
	_stamina_label.text = ("ST  %d / %d" if _compact else "STAMINA  %d / %d") % [ceili(current), ceili(maximum)]

func _on_xp(_total: int, level: int, into: int, required: int) -> void:
	_xp_bar.value = clampf(float(into) / maxi(required, 1), 0, 1)
	_xp_label.text = ("L%d XP %d/%d" if _compact else "LV %d  /  XP %d / %d") % [level, into, required]
	if level >= ExperienceComponent.MAX_LEVEL:
		_xp_bar.value = 1
		_xp_label.text = "LV %d  /  MAX LEVEL" % level

func set_weapon(id: StringName) -> void:
	var cfg := ContentRegistry.get_weapon(id)
	_weapon_label.text = cfg.display_name if cfg != null else "No weapon"
	_weapon_label.tooltip_text = "Switch weapon: " + UiCommands.binding(&"switch_weapon")

func set_objective(label: String) -> void:
	_objective_label.text = label
	_objective_label.visible = not label.is_empty()

func set_score(score: int) -> void: _score_label.text = "SCORE %d" % score
func set_currency(currency: int) -> void: _currency_label.text = "COINS %d" % currency
func set_wave(wave: int) -> void: _wave_label.text = "WAVE %d" % wave
func set_combo(combo: int) -> void: _combo_label.text = "COMBO %d" % combo if combo > 1 else ""
func _wave_progress(wave: int, defeated: int, total: int) -> void:
	_wave_label.text = "W%d • %d/%d" % [wave, defeated, total] if _compact else "WAVE %d  /  %d of %d" % [wave, defeated, total]

func show_toast(message: String) -> void:
	_toast_label.text = message
	_toast_label.visible = _toast_fits
	_toast_show_until = Time.get_ticks_msec() + 3500

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_weapon_refresh += delta
	if _weapon_refresh >= 0.15:
		_weapon_refresh = 0
		_refresh_weapon()
	if _toast_show_until > 0 and Time.get_ticks_msec() > _toast_show_until:
		_toast_show_until = 0
		_toast_label.visible = false


## Position every HUD element from the shared layout solution (safe-area local).
func apply_layout(plan: Dictionary, view: Vector2) -> void:
	if _top == null: return
	_compact = bool(plan.get("compact", false)) or SaveManager.get_settings().text_scale > 1.3
	var top_bar: Rect2 = plan["top_bar"]
	var vitals: Rect2 = plan["vitals"]
	UiLayout.place(_top_scrim, top_bar, view)
	UiLayout.place(_vitals_scrim, vitals, view)
	UiLayout.place(_toast_label, plan["toast"], view)
	# Collapsed rects mean the solver found no room on this screen.
	_vitals_scrim.visible = not UiLayout.is_collapsed(vitals)
	_toast_fits = not UiLayout.is_collapsed(plan["toast"])
	if not _toast_fits:
		_toast_label.visible = false
	# Labels flex; only the interactive pause target keeps a hard minimum.
	for label in [_wave_label, _score_label, _currency_label, _combo_label]:
		label.custom_minimum_size.x = 0
	_wave_label.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_combo_label.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_currency_label.size_flags_horizontal = SIZE_SHRINK_END
	_score_label.size_flags_horizontal = SIZE_SHRINK_END
	_currency_label.visible = not _compact or top_bar.size.x > 620.0
	_vitals.custom_minimum_size.x = maxf(vitals.size.x - 28.0, 120.0)
	# Refresh compact/full wording immediately so nothing clips after a rotation.
	_relabel()


## Re-emit current values through the compact/full formatters.
func _relabel() -> void:
	if _last_hp_max > 0.0:
		set_health(_last_hp, _last_hp_max)
	if _last_stamina_max > 0.0:
		set_stamina(_last_stamina, _last_stamina_max)


func _refresh_weapon() -> void:
	var player := GameRoot.get_active_player()
	if not is_instance_valid(player): return
	var manager := player.get_weapon_manager()
	if manager == null: return
	var active := manager.active_instance()
	if active == null or active.config == null:
		_weapon_label.text = "No weapon equipped"
		return
	var status := String(active.phase).to_upper()
	if active.config.has_ammo(): status += "  %d / %d" % [active.ammo, active.config.ammo_per_magazine]
	_weapon_label.text = "%s\n%s" % [active.config.display_name, status]
	var slots := PackedStringArray()
	for index in range(2):
		var item := manager.slot_instance(index)
		slots.append(item.config.display_name if item != null and item.config != null else "Empty")
	_weapon_label.tooltip_text = "Loadout: %s\nSwitch: %s" % [" / ".join(slots), UiCommands.binding(&"switch_weapon")]

