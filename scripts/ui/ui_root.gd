extends Control
class_name UiRoot
## Composition and navigation only. Panels own their presentation; canonical
## state changes always come from EventBus and commands go through GameRoot.
signal upgrade_chosen(upgrade_id: StringName)
var _safe: UiSafeArea
var _backdrop: MenuBackdrop
var _screens: Dictionary = {}
var _active_screen: StringName = &"none"
var _return_screen: StringName = &"main_menu"
var _menu: MenuPanel
var _setup: RunSetupPanel
var _summary: RunSummaryPanel
var _armory: ArmoryPanel
var _settings: SettingsPanel
var _help: HelpPanel
var _upgrade: UpgradePanel
var _hud: GameHud
var _touch: TouchControls
var _skill_bar: SkillBar
var _minimap: Minimap
var _boss_bar: BossHealthBar
var _boss_gate: Control
var _banner: AnnouncementBanner
var _numbers: DamageNumberLayer
var _confirm: ConfirmationDialog
var _confirm_command: Callable
var _text_scale := 1.0
var _banner_fits := true
var _minimap_fits := true
var _boss_fits := true

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_backdrop = MenuBackdrop.new()
	_backdrop.set_anchors_preset(PRESET_FULL_RECT)
	_backdrop.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	_safe = UiSafeArea.new()
	add_child(_safe)
	_build_hud()
	_build_screens()
	EventBus.game_state_changed.connect(_on_state_changed)
	EventBus.settings_changed.connect(_apply_settings)
	EventBus.upgrade_choices_presented.connect(_upgrade.present)
	EventBus.upgrade_selected.connect(_on_upgrade_selected)
	EventBus.enemy_damaged.connect(_on_damage)
	EventBus.run_started.connect(func(_id: int, _seed: int) -> void:
		_numbers.clear_all()
		_apply_settings(SaveManager.get_settings()))
	_safe.resized.connect(_layout)
	_apply_settings(SaveManager.get_settings())
	_layout.call_deferred()
	_sync_from_state()

func _mount(key: StringName, panel: Control) -> void:
	_screens[key] = panel
	_safe.add_child(panel)
	panel.visible = false

func _build_screens() -> void:
	_menu = MenuPanel.new()
	_mount(&"main_menu", _menu)
	_menu.navigate.connect(_navigate)
	_menu.quit_requested.connect(_request_quit)
	_setup = RunSetupPanel.new()
	_mount(&"run_setup", _setup)
	_setup.back_requested.connect(func() -> void: _show_screen(&"main_menu"))
	_summary = RunSummaryPanel.new()
	_mount(&"game_over", _summary)
	_summary.page_changed.connect(func(page: StringName) -> void:
		if GameRoot.get_current_state() == GameRoot.State.GAME_OVER: _active_screen = page)
	_summary.menu_requested.connect(func() -> void: GameRoot.request_main_menu())
	_summary.armory_requested.connect(func() -> void: _navigate(&"armory"))
	_help = HelpPanel.new()
	_mount(&"help", _help)
	_help.close_requested.connect(_close_auxiliary)
	for key in [&"settings", &"armory"]:
		var panel := Control.new()
		panel.set_anchors_preset(PRESET_FULL_RECT)
		_mount(key, panel)
		var box := UiFactory.center_box(panel)
		UiFactory.title(String(key).to_upper(), box, 34)
		UiFactory.label(
			"Changes apply immediately unless a button says otherwise." if key == &"settings"
			else "Spend banked coins on permanent upgrades.", box, 18
		).modulate = UiTheme.MUTED
		if key == &"settings":
			_settings = SettingsPanel.new()
			box.add_child(_settings)
			_settings.close_requested.connect(_close_auxiliary)
		else:
			_armory = ArmoryPanel.new()
			box.add_child(_armory)
			_armory.close_requested.connect(_close_auxiliary)
	_upgrade = UpgradePanel.new()
	_mount(&"upgrade_selection", _upgrade)
	_upgrade.choice_pressed.connect(_choose_upgrade)
	_upgrade.exit_requested.connect(func() -> void: _confirm_leave(GameRoot.request_main_menu))
	_build_pause()
	var status := Control.new()
	status.set_anchors_preset(PRESET_FULL_RECT)
	_mount(&"status", status)
	var status_box := UiFactory.center_box(status)
	UiFactory.label("LOADING", status_box, 18).modulate = UiTheme.CYAN
	UiFactory.title("PREPARING THE ARENA", status_box, 34).name = "StatusTitle"
	UiFactory.label("Please wait. If loading cannot complete, return to the menu.", status_box).modulate = UiTheme.MUTED
	# Static accent rule, not a progress indicator: the loader has no measurable
	# progress to report, so it must not imply one.
	var status_rule := ColorRect.new()
	status_rule.name = "StatusRule"
	status_rule.color = UiTheme.CYAN
	status_rule.custom_minimum_size.y = 3
	status_rule.mouse_filter = MOUSE_FILTER_IGNORE
	status_box.add_child(status_rule)
	UiFactory.button("MAIN MENU", status_box, 22).pressed.connect(func() -> void: GameRoot.request_main_menu())
	_confirm = ConfirmationDialog.new()
	_confirm.title = "LEAVE THIS STAND?"
	_confirm.dialog_text = "Unfinished run progress will be lost. No end-of-run reward is granted."
	_confirm.ok_button_text = "LEAVE RUN"
	_confirm.cancel_button_text = "KEEP PLAYING"
	_confirm.confirmed.connect(func() -> void:
		UiFactory.play_press("LEAVE")
		if _confirm_command.is_valid(): _confirm_command.call())
	_confirm.canceled.connect(func() -> void: UiFactory.play_press("CANCEL"))
	add_child(_confirm)

func _build_pause() -> void:
	var panel := Control.new()
	panel.set_anchors_preset(PRESET_FULL_RECT)
	_mount(&"paused", panel)
	var box := UiFactory.center_box(panel)
	UiFactory.label("TAKE A BREATH", box, 18).modulate = UiTheme.CYAN
	UiFactory.title("PAUSED", box, 48)
	UiFactory.label("Your run is frozen. Resume when you're ready.", box, 22).modulate = UiTheme.MUTED
	# Resume is the primary action and gets the tallest target; the two
	# destructive actions share a row at the bottom so they read as secondary.
	var resume := UiFactory.button("RESUME RUN", box, 24, Vector2(260, 96))
	UiTheme.decorate(resume, "play")
	resume.pressed.connect(func() -> void: GameRoot.request_resume())
	UiFactory.button("HOW TO PLAY", box, 22).pressed.connect(func() -> void: _navigate(&"help"))
	UiFactory.button("SETTINGS", box, 22).pressed.connect(func() -> void: _navigate(&"settings"))
	var leave_row := HBoxContainer.new()
	leave_row.add_theme_constant_override("separation", UiTheme.SPACE_M)
	box.add_child(leave_row)
	for entry in [["RESTART RUN", GameRoot.request_restart], ["MAIN MENU", GameRoot.request_main_menu]]:
		var button := UiFactory.button(entry[0], leave_row, 20, Vector2(0, UiTheme.TOUCH_MIN))
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.clip_text = true
		var command: Callable = entry[1]
		button.pressed.connect(func() -> void: _confirm_leave(command))

func _build_hud() -> void:
	_hud = GameHud.new()
	_safe.add_child(_hud)
	_numbers = DamageNumberLayer.new()
	# Damage coordinates are viewport-space, not safe-area-space.
	add_child(_numbers)
	_banner = AnnouncementBanner.new()
	_safe.add_child(_banner)
	_boss_gate = Control.new()
	_boss_gate.set_anchors_preset(PRESET_FULL_RECT)
	_boss_gate.mouse_filter = MOUSE_FILTER_IGNORE
	_safe.add_child(_boss_gate)
	_boss_bar = BossHealthBar.new()
	_boss_gate.add_child(_boss_bar)
	_minimap = Minimap.new()
	_safe.add_child(_minimap)
	_skill_bar = SkillBar.new()
	_safe.add_child(_skill_bar)
	_touch = TouchControls.new()
	_safe.add_child(_touch)
	_touch.action_declined.connect(_hud.show_toast)
	_skill_bar.action_declined.connect(_hud.show_toast)

func _layout() -> void:
	if _banner == null: return
	# One solver owns every overlay rect, so HUD, minimap, boss frame, banner,
	# stick, action cluster and skill bar can never overlap on any aspect ratio.
	var view := _safe.size
	var plan := UiLayout.compute(view, _text_scale)
	_hud.apply_layout(plan, view)
	_touch.apply_layout(plan, view)
	UiLayout.place(_banner, plan["banner"], view)
	UiLayout.place(_boss_bar, plan["boss"], view)
	UiLayout.place(_minimap, plan["minimap"], view)
	_minimap_fits = not UiLayout.is_collapsed(plan["minimap"])
	_minimap.visible = _minimap.visible and _minimap_fits
	# When the solver has no room for a message element on a very short screen it
	# collapses the rect; drop the element instead of letting it overlap.
	_banner_fits = not UiLayout.is_collapsed(plan["banner"])
	_boss_fits = not UiLayout.is_collapsed(plan["boss"])
	_banner.visible = _banner.visible and _banner_fits
	_boss_gate.visible = _boss_gate.visible and _boss_fits
	var skills: Rect2 = UiLayout.sanitize(plan["skills"], view)
	_skill_bar.fit_touch_targets(skills.size)
	_skill_bar.position = skills.position
	# Apply after child minimum-size invalidations (e.g. rotating a wide tablet).
	_skill_bar.set_deferred("size", skills.size)

static func screen_for_state(state: StringName) -> StringName:
	if state in [&"starting_run", &"loading", &"error"]: return &"status"
	if state == &"wave_transition": return &"wave_transition"
	return state if state in [&"main_menu", &"playing", &"paused", &"upgrade_selection", &"game_over"] else &"status"

func _show_screen(screen: StringName) -> void:
	_active_screen = screen
	var panel_key := &"game_over" if screen in [&"run_summary", &"meta_reward"] else screen
	for key in _screens:
		_screens[key].visible = key == panel_key
	var playing := screen in [&"playing", &"wave_transition"]
	_backdrop.visible = not playing
	_hud.visible = playing
	_touch.visible = playing and (DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"))
	_skill_bar.visible = playing
	_minimap.visible = playing and _minimap_fits
	_boss_gate.visible = playing and _boss_fits
	_banner.visible = playing and _banner_fits
	_banner.set_process(playing)
	_numbers.visible = playing
	_numbers.set_process(playing)
	if not playing:
		_touch.cancel()
		_numbers.clear_all()
	if screen == &"main_menu":
		_menu.refresh()
		_banner.clear_all()
	if screen == &"upgrade_selection": _upgrade._layout_cards()
	if _screens.has(panel_key): UiFactory.focus_first.call_deferred(_screens[panel_key])

func _sync_from_state() -> void:
	_show_screen(screen_for_state(GameRoot.get_current_state()))
	# find_child returns null if the status screen was rebuilt without the title;
	# the cast would then crash on the next state change.
	var title := _screens[&"status"].find_child("StatusTitle", true, false) as Label
	if title != null:
		title.text = "ARENA UNAVAILABLE" if GameRoot.get_current_state() == GameRoot.State.ERROR else "PREPARING THE ARENA"

func _on_state_changed(_previous: StringName, _current: StringName) -> void:
	if _confirm != null: _confirm.hide()
	_sync_from_state()

func _navigate(screen: StringName) -> void:
	if screen in [&"run_setup", &"daily"]:
		_setup.present(screen == &"daily")
		_show_screen(&"run_setup")
		return
	_return_screen = _active_screen
	if screen == &"armory": _armory.refresh()
	if screen == &"settings": _settings.refresh()
	if screen == &"help": _help.refresh()
	_apply_settings(SaveManager.get_settings())
	_show_screen(screen)

func _close_auxiliary() -> void:
	if _active_screen == &"settings":
		_settings.cancel_edit()
		_settings.cancel_preview()
	_show_screen(_return_screen)

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") and not event.is_action_pressed("pause"): return
	if _confirm != null and _confirm.visible: return
	if _active_screen in [&"settings", &"armory", &"help"]:
		if _active_screen == &"settings" and _settings.is_rebinding(): return
		_close_auxiliary()
		get_viewport().set_input_as_handled()
	elif _active_screen == &"run_setup":
		_show_screen(&"main_menu")
		get_viewport().set_input_as_handled()

func _confirm_leave(command: Callable) -> void:
	_confirm_command = command
	_confirm.title = "LEAVE THIS STAND?"
	_confirm.dialog_text = "Unfinished run progress will be lost. No end-of-run reward is granted."
	_confirm.ok_button_text = "LEAVE RUN"
	_confirm.cancel_button_text = "KEEP PLAYING"
	_popup_confirm()

## Size the modal from the live viewport and the text scale so the message never
## clips at 200% text or overflows a small phone screen.
func _popup_confirm() -> void:
	var view := get_viewport_rect().size
	var width := int(clampf(view.x * 0.8, 320.0, 560.0 * _text_scale))
	var height := int(clampf(200.0 * _text_scale, 180.0, maxf(view.y * 0.8, 180.0)))
	_confirm.min_size = Vector2i(mini(width, int(view.x)), mini(height, int(view.y)))
	_confirm.popup_centered(_confirm.min_size)
	for button in [_confirm.get_ok_button(), _confirm.get_cancel_button()]:
		if button != null:
			button.custom_minimum_size = Vector2(150, UiTheme.TOUCH_MIN)
	_confirm.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm.get_ok_button().grab_focus.call_deferred()


func _choose_upgrade(id: StringName) -> void:
	if GameRoot.get_current_state() != GameRoot.State.UPGRADE_SELECTION: return
	if GameRoot.request_upgrade_selection(id):
		_upgrade.lock_selection()
		upgrade_chosen.emit(id)
	else:
		_upgrade.show_feedback("That choice is no longer available. Select another card.")

func _on_upgrade_selected(id: StringName) -> void:
	var cfg := ContentRegistry.get_upgrade(id)
	if cfg != null:
		_banner.clear_pending()
		_banner.announce("UPGRADE APPLIED / " + cfg.display_name, &"victory")

func _on_damage(enemy: Node, result: DamageResult) -> void:
	if result != null and result.accepted and is_instance_valid(enemy) and enemy is Node3D:
		_numbers.spawn_damage_number(enemy.global_position + Vector3.UP * 1.2, result.final_amount, result.was_critical)

func _apply_settings(settings: SettingsData) -> void:
	_text_scale = settings.text_scale
	theme = UiTheme.create(settings)
	UiTheme.apply_text_scale(self, settings.text_scale)
	_banner.set_reduced_motion(settings.reduced_motion)
	_numbers.set_reduced_motion(settings.reduced_motion)
	_boss_bar.set_reduced_motion(settings.reduced_motion)
	_touch.set_high_contrast(settings.high_contrast)
	for node in get_tree().get_nodes_in_group("hitstop_manager"):
		var hitstop := node as HitstopManager
		if hitstop != null:
			hitstop.set_reduced_motion(settings.reduced_motion)
	for node in get_tree().get_nodes_in_group("performance_monitor"):
		var monitor := node as PerformanceMonitor
		if monitor == null:
			continue
		var tier_idx := [&"low", &"medium", &"high"].find(settings.graphics_quality)
		if tier_idx < 0:
			tier_idx = 2  # high is the default when save carries an unknown/legacy value
		monitor.set_tier(tier_idx)
		_numbers.set_max_live(monitor.max_damage_numbers())
	_layout.call_deferred()

func get_announcement_banner() -> AnnouncementBanner: return _banner
func loc(key: StringName) -> String: return UiText.lookup(key)
func get_debug_snapshot() -> Dictionary:
	var result := _touch.get_debug_snapshot()
	result["active_screen"] = String(_active_screen)
	return result


func _request_quit() -> void:
	if SaveManager.save_now():
		get_tree().quit()
		return
	_confirm.title = "SAVE INCOMPLETE"
	_confirm.dialog_text = "Progress could not be saved. Quit anyway, or cancel and retry?"
	_confirm.ok_button_text = "QUIT ANYWAY"
	_confirm.cancel_button_text = "CANCEL"
	_confirm_command = func() -> void: get_tree().quit()
	_popup_confirm()
