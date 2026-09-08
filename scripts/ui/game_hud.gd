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
var _toast_label: Label
var _toast_show_until := 0
var _experience: ExperienceComponent
var _vitals: VBoxContainer
var _top: HBoxContainer
var _compact := false
var _weapon_refresh := 0.0

func _ready() -> void:
	name = "GameplayHUD"
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_top = HBoxContainer.new()
	_top.set_anchors_preset(PRESET_TOP_WIDE)
	_top.offset_left = 20
	_top.offset_right = -20
	_top.offset_top = 12
	_top.mouse_filter = MOUSE_FILTER_IGNORE
	_top.resized.connect(_fit_vitals)
	add_child(_top)
	_wave_label = UiFactory.title("WAVE 1", _top, 24)
	_combo_label = UiFactory.label("", _top, 20)
	_combo_label.modulate = UiTheme.GOLD
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	_top.add_child(spacer)
	_currency_label = UiFactory.label("COINS 0", _top, 20)
	_score_label = UiFactory.title("SCORE 0", _top, 24)
	var pause := UiFactory.button("PAUSE", _top, 20, Vector2(110, 52))
	UiTheme.decorate(pause, "pause")
	pause.pressed.connect(func() -> void: GameRoot.request_pause())
	_vitals = VBoxContainer.new()
	_vitals.position = Vector2(20, 78)
	_vitals.custom_minimum_size.x = 260
	_vitals.add_theme_constant_override("separation", 3)
	_vitals.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_vitals)
	_hp_label = UiFactory.title("HEALTH —", _vitals, 20)
	_hp_bar = _meter(_vitals, Color("70e0a0"))
	_stamina_label = UiFactory.label("STAMINA —", _vitals, 18)
	_stamina_bar = _meter(_vitals, UiTheme.GOLD)
	_xp_label = UiFactory.label("LEVEL 1  /  XP 0", _vitals, 18)
	_xp_bar = _meter(_vitals, UiTheme.CYAN)
	_weapon_label = UiFactory.label("WEAPON —", _vitals, 20)
	_toast_label = UiFactory.label("", self, 22)
	_toast_label.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_toast_label.offset_left = 320
	_toast_label.offset_right = -280
	_toast_label.offset_top = -200
	_toast_label.offset_bottom = -155
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
	if GameRoot == null or not GameRoot.has_method("get_run"):
		return
	var run: Variant = GameRoot.call("get_run")
	if run == null:
		return
	if run is Dictionary:
		set_score(int((run as Dictionary).get("score", 0)))
		set_currency(int((run as Dictionary).get("currency", 0)))
		set_wave(int((run as Dictionary).get("current_wave", 1)))
		set_combo(int((run as Dictionary).get("combo", 0)))
	else:
		if "score" in run: set_score(int((run as Object).get("score")))
		if "currency" in run: set_currency(int((run as Object).get("currency")))
		if "current_wave" in run: set_wave(int((run as Object).get("current_wave")))
		if "combo" in run: set_combo(int((run as Object).get("combo")))
	_toast_label.visible = false
	var player: Node = GameRoot.call("get_active_player") as Node if GameRoot.has_method("get_active_player") else null
	if is_instance_valid(_experience) and _experience.xp_changed.is_connected(_on_xp):
		_experience.xp_changed.disconnect(_on_xp)
	_experience = null
	if not is_instance_valid(player): return
	var hp := (player as Node).get_node_or_null("HealthComponent")
	if hp != null: set_health(hp.current_health, hp.max_health)
	var stamina := player.get_node_or_null("StaminaComponent")
	if stamina != null: set_stamina(stamina.get_current(), stamina.get_max())
	_experience = player.get_node_or_null("ExperienceComponent") as ExperienceComponent
	if _experience != null:
		_experience.xp_changed.connect(_on_xp)
		_on_xp(_experience.get_xp(), _experience.get_level(), _experience.get_xp(), ExperienceComponent.xp_for_level(_experience.get_level()))
	var weapons := player.get_node_or_null("WeaponManager")
	if weapons != null: set_weapon(weapons.active_weapon_id())

func set_health(current: float, maximum: float) -> void:
	_hp_bar.value = clampf(current / maximum, 0, 1) if maximum > 0 else 0
	var low := _hp_bar.value <= 0.25
	_hp_label.text = "%s %d/%d" % [("LOW HP" if low else "HP") if _compact else ("LOW HEALTH" if low else "HEALTH"), ceili(current), ceili(maximum)]
	_hp_label.modulate = UiTheme.GOLD if low else Color.WHITE

func set_stamina(current: float, maximum: float) -> void:
	_stamina_bar.value = clampf(current / maximum, 0, 1) if maximum > 0 else 0
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

func set_score(score: int) -> void: _score_label.text = "SCORE %d" % score
func set_currency(currency: int) -> void: _currency_label.text = "COINS %d" % currency
func set_wave(wave: int) -> void: _wave_label.text = "WAVE %d" % wave
func set_combo(combo: int) -> void: _combo_label.text = "COMBO %d" % combo if combo > 1 else ""
func _wave_progress(wave: int, defeated: int, total: int) -> void:
	_wave_label.text = "W%d • %d/%d" % [wave, defeated, total] if _compact else "WAVE %d  /  %d of %d" % [wave, defeated, total]

func show_toast(message: String) -> void:
	_toast_label.text = message
	_toast_label.visible = true
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


func layout_for_size(width: float) -> void:
	if _top == null: return
	_compact = width < 1100 or SaveManager.get_settings().text_scale > 1.3
	_wave_label.custom_minimum_size.x = width * 0.23
	_score_label.custom_minimum_size.x = width * 0.18
	_currency_label.custom_minimum_size.x = width * 0.14
	_combo_label.custom_minimum_size.x = width * 0.11
	_vitals.custom_minimum_size.x = minf(width * 0.28, 280)
	_toast_label.offset_left = 20 if width < 850 else 320
	_toast_label.offset_right = -20 if width < 850 else -280
	_fit_vitals()

func _fit_vitals() -> void:
	if _vitals != null:
		_vitals.position.y = maxf(78, _top.position.y + _top.size.y + 10)


func _refresh_weapon() -> void:
	var player := GameRoot.get_active_player()
	if not is_instance_valid(player): return
	var manager := player.get_node_or_null("WeaponManager") as WeaponManager
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
