extends Control
## UI root controller. Owns panel switching (only one major screen visible at a time),
## hosts the touch controls, routes joystick/action intents to the active player, and
## keeps text behind UiText so localization can be added later. Screen construction is
## shared with UiFactory; the HUD lives in GameHud, upgrade cards in UpgradePanel,
## the full settings form in SettingsPanel, and the HUD extras (skill bar, minimap,
## boss frame, damage numbers, announcement banner) are built here and fed from
## EventBus. Controllers never mutate global state directly: they call GameRoot's
## command API.

const VIRTUAL_JOYSTICK := preload("res://scripts/ui/virtual_joystick.gd")
const TOUCH_ACTION := preload("res://scripts/ui/touch_action_button.gd")

## Emitted when the player clicks an upgrade card. The UI never modifies progression;
## GameRoot validates and applies it.
signal upgrade_chosen(upgrade_id: StringName)

const UPGRADE_CHOICE_COUNT := 3

## Screens (mutually exclusive).
var _main_panel: Control = null
var _settings_panel: Control = null
var _armory_panel: Control = null
var _armory_form: ArmoryPanel = null
var _pause_panel: Control = null
var _gameover_panel: Control = null
var _upgrade_panel: UpgradePanel = null
var _gameover_stats: Label = null

## HUD (overlay while playing).
var _hud: GameHud = null
var _touch_layer: Control = null
var _joystick: VirtualJoystick = null
var _attack_btn: Control = null
var _dodge_btn: Control = null
var _switch_btn: Control = null

## HUD extras (built once, fed from EventBus).
var _skill_bar: SkillBar = null
var _minimap: Minimap = null
var _boss_bar: BossHealthBar = null
var _dmg_layer: DamageNumberLayer = null
var _banner: AnnouncementBanner = null

var _last_joystick_value := Vector2.ZERO
var _active_screen := &"none"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_screens()
	_build_hud()
	_build_hud_extras()
	_build_touch()
	_upgrade_panel.choice_pressed.connect(_on_upgrade_panel_choice)
	EventBus.game_state_changed.connect(_on_state_changed)
	EventBus.player_health_changed.connect(_on_health_changed)
	EventBus.score_changed.connect(_on_score_changed)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.combo_changed.connect(_on_combo_changed)
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.enemy_damaged.connect(_on_enemy_damaged_numbers)
	EventBus.settings_changed.connect(_on_settings_changed_push)
	EventBus.run_ended.connect(func(_s: int, _w: int, _b: int) -> void:
		_refresh_gameover_best()
		_update_gameover_stats())
	EventBus.upgrade_choices_presented.connect(_on_upgrade_choices_presented)
	EventBus.upgrade_selected.connect(_on_upgrade_selected)
	_push_accessibility_settings()
	_sync_from_state()


func _process(_delta: float) -> void:
	if GameRoot.get_current_state() != GameRoot.State.PLAYING and GameRoot.get_current_state() != GameRoot.State.WAVE_TRANSITION:
		return
	var v := _joystick.get_value()
	if v != _last_joystick_value:
		_last_joystick_value = v
		var p := GameRoot.get_active_player()
		if p != null and is_instance_valid(p) and p.has_method("set_move_input"):
			p.call("set_move_input", v)


## Announcement line for tutorial/coach wiring (Main binds the TutorialManager).
func get_announcement_banner() -> AnnouncementBanner:
	return _banner


# ---------------------------- Screens ----------------------------

func _build_screens() -> void:
	_main_panel = UiFactory.make_panel(self, "MainMenuPanel")
	var box := UiFactory.center_box(_main_panel)
	UiFactory.title(loc(&"app_title"), box, _font(30))
	UiFactory.title(loc(&"app_subtitle"), box, _font(30))
	UiFactory.title("", box, _font(30))  # spacer
	var play_btn := UiFactory.button(loc(&"play"), box, _font(20))
	play_btn.pressed.connect(func() -> void: GameRoot.request_play())
	var daily_btn := UiFactory.button(loc(&"daily"), box, _font(20))
	daily_btn.pressed.connect(func() -> void: GameRoot.start_daily_run())
	var armory_btn := UiFactory.button(loc(&"armory"), box, _font(20))
	armory_btn.pressed.connect(_open_armory)
	var settings_btn := UiFactory.button(loc(&"settings"), box, _font(20))
	settings_btn.pressed.connect(_open_settings)
	var quit_btn := UiFactory.button(loc(&"quit"), box, _font(20))
	quit_btn.pressed.connect(_request_quit)
	_best_menu_labels(box)

	_build_settings_screen()
	_build_armory_screen()
	_build_pause_screen()
	_build_gameover_screen()
	_build_upgrade_screen()


func _font(base: int) -> int:
	return UiFactory.font_scaled(base)


func _best_menu_labels(box: VBoxContainer) -> void:
	var bs := Label.new()
	bs.name = "BestScoreLabel"
	bs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bs.add_theme_font_size_override("font_size", _font(16))
	box.add_child(bs)
	_refresh_best_label(bs)
	var ver := Label.new()
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.text = loc(&"version")
	ver.add_theme_font_size_override("font_size", _font(12))
	ver.modulate.a = 0.6
	box.add_child(ver)


func _build_settings_screen() -> void:
	_settings_panel = UiFactory.make_panel(self, "SettingsPanel")
	_settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := UiFactory.center_box(_settings_panel)
	UiFactory.title(loc(&"settings"), box, _font(30))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 480)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var form := SettingsPanel.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.close_requested.connect(_close_settings)
	scroll.add_child(form)


func _build_armory_screen() -> void:
	_armory_panel = UiFactory.make_panel(self, "ArmoryPanel")
	_armory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := UiFactory.center_box(_armory_panel)
	UiFactory.title(loc(&"armory"), box, _font(30))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 480)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_armory_form = ArmoryPanel.new()
	_armory_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_armory_form.close_requested.connect(_close_armory)
	scroll.add_child(_armory_form)


func _build_pause_screen() -> void:
	_pause_panel = UiFactory.make_panel(self, "PausePanel")
	var box := UiFactory.center_box(_pause_panel)
	UiFactory.title(loc(&"paused"), box, _font(30))
	var resume_btn := UiFactory.button(loc(&"resume"), box, _font(20))
	resume_btn.pressed.connect(func() -> void: GameRoot.request_resume())
	var restart_btn := UiFactory.button(loc(&"restart"), box, _font(20))
	restart_btn.pressed.connect(func() -> void: GameRoot.request_restart())
	var menu_btn := UiFactory.button(loc(&"main_menu"), box, _font(20))
	menu_btn.pressed.connect(func() -> void: GameRoot.request_main_menu())
	var armory_btn := UiFactory.button(loc(&"armory"), box, _font(20))
	armory_btn.pressed.connect(_open_armory)
	var set_btn := UiFactory.button(loc(&"settings"), box, _font(20))
	set_btn.pressed.connect(_open_settings)


func _build_gameover_screen() -> void:
	_gameover_panel = UiFactory.make_panel(self, "GameOverPanel")
	var box := UiFactory.center_box(_gameover_panel)
	UiFactory.title(loc(&"game_over"), box, _font(30))
	var stats := Label.new()
	stats.name = "RunStatsLabel"
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", _font(18))
	box.add_child(stats)
	var retry_btn := UiFactory.button(loc(&"retry"), box, _font(20))
	retry_btn.pressed.connect(func() -> void: GameRoot.request_play())
	var menu_btn := UiFactory.button(loc(&"main_menu"), box, _font(20))
	menu_btn.pressed.connect(func() -> void: GameRoot.request_main_menu())
	_gameover_stats = stats


func _build_upgrade_screen() -> void:
	_upgrade_panel = UpgradePanel.new()
	add_child(_upgrade_panel)


func _build_hud() -> void:
	_hud = GameHud.new()
	add_child(_hud)


## Skill bar, minimap, boss frame, damage numbers, announcement banner. The bar and
## minimap show only while playing; the boss frame manages itself (boss spawn ->
## death/run end); numbers + banner are always mounted but idle when empty.
func _build_hud_extras() -> void:
	_dmg_layer = DamageNumberLayer.new()
	add_child(_dmg_layer)

	_banner = AnnouncementBanner.new()
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 200
	_banner.offset_bottom = 260
	add_child(_banner)

	_boss_bar = BossHealthBar.new()
	_boss_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_bar.offset_left = -210
	_boss_bar.offset_right = 210
	_boss_bar.offset_top = 64
	_boss_bar.offset_bottom = 140
	add_child(_boss_bar)

	_minimap = Minimap.new()
	_minimap.anchor_left = 1.0
	_minimap.anchor_right = 1.0
	_minimap.offset_left = -172
	_minimap.offset_right = -12
	_minimap.offset_top = 64
	_minimap.offset_bottom = 224
	add_child(_minimap)
	_minimap.visible = false

	_skill_bar = SkillBar.new()
	_skill_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_skill_bar.offset_left = -110
	_skill_bar.offset_right = 110
	_skill_bar.offset_top = -250
	_skill_bar.offset_bottom = -160
	add_child(_skill_bar)
	_skill_bar.visible = false


func _build_touch() -> void:
	_touch_layer = Control.new()
	_touch_layer.name = "TouchControls"
	_touch_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_touch_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_touch_layer)
	_touch_layer.visible = false

	_joystick = VIRTUAL_JOYSTICK.new()
	_joystick.name = "MovementJoystick"
	_joystick.anchor_left = 0.0
	_joystick.anchor_right = 0.0
	_joystick.anchor_top = 1.0
	_joystick.anchor_bottom = 1.0
	_joystick.offset_left = 8
	_joystick.offset_right = 480
	_joystick.offset_top = -440
	_joystick.offset_bottom = 8
	_joystick.mouse_filter = Control.MOUSE_FILTER_STOP
	_touch_layer.add_child(_joystick)

	_attack_btn = TOUCH_ACTION.new()
	_attack_btn.name = "AttackButton"
	_attack_btn.action_name = "attack"
	_attack_btn.vibrate_on_press = true
	_attack_btn.anchor_left = 1.0
	_attack_btn.anchor_top = 1.0
	_attack_btn.offset_left = -150
	_attack_btn.offset_right = -38
	_attack_btn.offset_top = -180
	_attack_btn.offset_bottom = -68
	_attack_btn.pressed.connect(func() -> void:
		var p := GameRoot.get_active_player()
		if p != null and is_instance_valid(p) and p.has_method("request_attack"):
			p.call("request_attack"))
	_touch_layer.add_child(_attack_btn)

	_dodge_btn = TOUCH_ACTION.new()
	_dodge_btn.name = "DodgeButton"
	_dodge_btn.action_name = "dodge"
	_dodge_btn.radius = 44.0
	_dodge_btn.anchor_left = 1.0
	_dodge_btn.anchor_top = 1.0
	_dodge_btn.offset_left = -270
	_dodge_btn.offset_right = -182
	_dodge_btn.offset_top = -110
	_dodge_btn.offset_bottom = -22
	_dodge_btn.pressed.connect(func() -> void:
		var p := GameRoot.get_active_player()
		if p != null and is_instance_valid(p) and p.has_method("request_dodge"):
			p.call("request_dodge"))
	_touch_layer.add_child(_dodge_btn)

	_switch_btn = TOUCH_ACTION.new()
	_switch_btn.name = "SwitchWeaponButton"
	_switch_btn.action_name = "switch_weapon"
	_switch_btn.radius = 30.0
	_switch_btn.anchor_left = 1.0
	_switch_btn.anchor_top = 1.0
	_switch_btn.offset_left = -262
	_switch_btn.offset_right = -190
	_switch_btn.offset_top = -206
	_switch_btn.offset_bottom = -134
	_switch_btn.pressed.connect(func() -> void:
		var p := GameRoot.get_active_player()
		if p != null and is_instance_valid(p) and p.has_method("request_weapon_switch"):
			p.call("request_weapon_switch"))
	_touch_layer.add_child(_switch_btn)


# ---------------------------- Upgrade cards ----------------------------

func _on_upgrade_choices_presented(choices: Array) -> void:
	_upgrade_panel.present(choices)


## A card was clicked. Route ONLY through the GameRoot command; never touch progression.
func _on_upgrade_panel_choice(upgrade_id: StringName) -> void:
	if GameRoot.get_current_state() != GameRoot.State.UPGRADE_SELECTION:
		return
	if GameRoot.request_upgrade_selection(upgrade_id):
		_upgrade_panel.lock_selection()
		upgrade_chosen.emit(upgrade_id)


## After a valid selection, show a short confirmation toast on the HUD while the next
## wave begins. Respects reduced-motion (no tween when disabled).
func _on_upgrade_selected(upgrade_id: StringName) -> void:
	var cfg := ContentRegistry.get_upgrade(upgrade_id)
	if cfg == null:
		return
	_hud.show_toast("%s  •  %s" % [cfg.display_name.to_upper(), cfg.description.to_upper()])


# ---------------------------- Screen switching ----------------------------

func _show_screen(screen: StringName) -> void:
	_active_screen = screen
	_main_panel.visible = screen == &"main_menu" or screen == &"main_menu_settings"
	_settings_panel.visible = screen == &"settings"
	_armory_panel.visible = screen == &"armory"
	_pause_panel.visible = screen == &"paused"
	_gameover_panel.visible = screen == &"game_over"
	_upgrade_panel.visible = screen == &"upgrade_selection"
	var playing := screen == &"playing" or screen == &"wave_transition"
	_hud.visible = playing
	_touch_layer.visible = playing
	_skill_bar.visible = playing
	_minimap.visible = playing
	# Boss frame self-manages (boss spawn -> death/run end); numbers + banner idle
	# silently when empty, so they stay mounted across all screens.


func _sync_from_state() -> void:
	var state := GameRoot.get_current_state()
	match state:
		GameRoot.State.MAIN_MENU:
			_show_screen(&"main_menu")
		GameRoot.State.PLAYING, GameRoot.State.WAVE_TRANSITION:
			_show_screen(&"playing")
		GameRoot.State.UPGRADE_SELECTION:
			_show_screen(&"upgrade_selection")
		GameRoot.State.PAUSED:
			_show_screen(&"paused")
		GameRoot.State.GAME_OVER:
			_show_screen(&"game_over")
			_update_gameover_stats()
		_:
			_show_screen(&"main_menu")


func _on_state_changed(_p: StringName, _c: StringName) -> void:
	# Reflect every canonical state change onto the panel stack.
	_sync_from_state()


func _open_settings() -> void:
	_show_screen(&"settings")


func _close_settings() -> void:
	if GameRoot.get_current_state() == GameRoot.State.MAIN_MENU:
		_show_screen(&"main_menu")
	elif GameRoot.get_current_state() == GameRoot.State.PAUSED:
		_show_screen(&"paused")


func _open_armory() -> void:
	if _armory_form != null:
		_armory_form.refresh()
	_show_screen(&"armory")


func _close_armory() -> void:
	if GameRoot.get_current_state() == GameRoot.State.MAIN_MENU:
		_show_screen(&"main_menu")
	elif GameRoot.get_current_state() == GameRoot.State.PAUSED:
		_show_screen(&"paused")


func _request_quit() -> void:
	get_tree().quit()


# ---------------------------- HUD updates ----------------------------

func _on_health_changed(current: float, maximum: float) -> void:
	_hud.set_health(current, maximum)


func _on_score_changed(score: int, _delta: int) -> void:
	_hud.set_score(score)


func _on_wave_started(wave_number: int, _planned: int) -> void:
	_hud.set_wave(wave_number)


func _on_combo_changed(combo: int, best: int) -> void:
	_hud.set_combo(combo)


func _on_currency_changed(currency: int, _delta: int) -> void:
	_hud.set_currency(currency)


## Damage-number glue: every accepted enemy hit pops a floating number (gold crits).
func _on_enemy_damaged_numbers(enemy: Node, result: DamageResult) -> void:
	if _dmg_layer == null or result == null or not result.accepted:
		return
	if not (enemy is Node3D):
		return
	var pos := (enemy as Node3D).global_position + Vector3(0, 1.2, 0)
	_dmg_layer.spawn_damage_number(pos, result.final_amount, result.was_critical)


## Push reduced-motion + number budget from settings (live on settings_changed).
func _on_settings_changed_push(_settings: SettingsData) -> void:
	_push_accessibility_settings()


func _push_accessibility_settings() -> void:
	var reduced := false
	if SaveManager != null and SaveManager.has_method("get_settings"):
		var s: SettingsData = SaveManager.call("get_settings")
		if s != null and s.has_method("get_reduced_motion"):
			reduced = bool(s.call("get_reduced_motion"))
	if _banner != null:
		_banner.set_reduced_motion(reduced)
	if _dmg_layer != null:
		_dmg_layer.set_reduced_motion(reduced)
		_dmg_layer.set_max_live(_perf_number_budget())


func _perf_number_budget() -> int:
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group("performance_monitor"):
			if node != null and node.has_method("max_damage_numbers"):
				return int(node.call("max_damage_numbers"))
	return 32


func _refresh_best_label(label: Label) -> void:
	label.text = "%s %d    %s %d" % [
		loc(&"best_score"), GameRoot.get_best_score(),
		loc(&"best_wave"), GameRoot.get_best_wave(),
	]


func _refresh_gameover_best() -> void:
	for child in _main_panel.find_children("*", "Label", true, false):
		if child.name == "BestScoreLabel":
			_refresh_best_label(child)


func _update_gameover_stats() -> void:
	if _gameover_stats == null:
		return
	var run := GameRoot.get_run()
	var secs := int(run.elapsed_seconds)
	var summary := run.summary()
	_gameover_stats.text = "%s: %d\n%s: %d\n%s: %d\n%s: %ds\n%s: %d" % [
		loc(&"score"), summary.score,
		loc(&"wave_reached"), summary.current_wave,
		loc(&"kills"), summary.kills,
		loc(&"time_survived"), secs,
		loc(&"best_score"), GameRoot.get_best_score(),
	]


# ---------------------------- Localization ----------------------------

func loc(key: StringName) -> String:
	return UiText.get(key)


func get_debug_snapshot() -> Dictionary:
	return {
		"active_screen": String(_active_screen),
		"joystick_active": _joystick.is_active(),
		"joystick_value": _joystick.get_value(),
	}
