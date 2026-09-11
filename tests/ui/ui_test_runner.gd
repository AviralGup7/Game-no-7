extends Node
## Real-node UI tests, isolated from Main/world assembly and from the user's save.
## Run via scripts/ui/run_ui_validation.sh, never against a personal save directory.
const UI_SCENE := preload("res://scenes/ui/ui_root.tscn")
var _ui
var _viewport: SubViewport
var _total := 0
var _failures: Array[String] = []
var _meta: MetaProgression
var _player: Node

func _ready() -> void:
	if "--isolated-ui-tests" not in OS.get_cmdline_user_args():
		push_error("Use scripts/ui/run_ui_validation.sh to isolate test save data.")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _check(case_name: String, passed: bool) -> void:
	_total += 1
	if not passed:
		_failures.append(case_name)
		push_error("UI FAIL: " + case_name)

func _settle() -> void:
	for i in range(4): await get_tree().process_frame

func _run() -> void:
	_meta = MetaProgression.new()
	add_child(_meta)
	GameRoot.set_world_builder(build_world)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_ui = UI_SCENE.instantiate()
	_viewport.add_child(_ui)
	await _settle()
	_check("boot maps to menu", _screen() == "main_menu")
	_check("fresh or restored save is readable", SaveManager.get_settings() != null)
	_check("menu reads persisted record", _ui._menu._records.text.contains(str(SaveManager.get_best_score())))
	_check("no menu damage overlay", not _ui._numbers.visible)
	# Modularisation smoke: the HUD vitals are a dedicated UiGauges dock and the
	# confirm modal is a wired UiModal controller.
	_check("hud gauges dock is a real component", is_instance_valid(_ui._hud._gauges) and _ui._hud._gauges is UiGauges)
	_check("gauges expose wired meters",
		_ui._hud._gauges.health_bar != null and _ui._hud._gauges.stamina_bar != null and _ui._hud._gauges.xp_bar != null)
	_check("modal controller wired to dialog", is_instance_valid(_ui._modal) and _ui._confirm != null)
	_check("unknown states fail to status screen", _ui.screen_for_state(&"unknown") == &"status")
	for state in [&"starting_run", &"loading", &"error"]:
		_check("status mapping " + String(state), _ui.screen_for_state(state) == &"status")
	_ui._navigate(&"run_setup")
	await _settle()
	_check("menu opens setup without starting gameplay", _screen() == "run_setup" and GameRoot.get_current_state() == GameRoot.State.MAIN_MENU)
	_check("starter content can launch", not _ui._setup._start.disabled)
	_check("supplied arena catalogue loaded", _ui._setup._arena_ids.size() == 3)
	var original_arena := ContentRegistry.get_selected_arena_id()
	_ui._setup._arenas.select(1)
	_ui._setup._refresh_details()
	_check("arena browsing does not mutate selection", ContentRegistry.get_selected_arena_id() == original_arena)
	if not GameRoot.has_method("request_arena_selection") and _ui._setup._arena_ids[1] != original_arena:
		_check("unsupported arena selection fails closed", _ui._setup._start.disabled)
	_ui._setup.present(false)
	_ui._setup._launch()
	await _settle()
	_check("setup launches via GameRoot", GameRoot.get_current_state() == GameRoot.State.PLAYING and _screen() == "playing")
	_check("gameplay HUD visible", _ui._hud.visible and _ui._skill_bar.visible)
	GameRoot.request_pause()
	await _settle()
	_check("pause modal and tree pause agree", _screen() == "paused" and get_tree().paused)
	_check("boss and skill overlays gated during pause", not _ui._boss_gate.visible and not _ui._skill_bar.visible)
	_ui._navigate(&"settings")
	await _settle()
	_check("settings keeps canonical pause state", _screen() == "settings" and GameRoot.get_current_state() == GameRoot.State.PAUSED)
	_check("floating screen mounts through shared overlay", _ui._screens[&"settings"].mouse_filter == Control.MOUSE_FILTER_STOP)
	var previous := SaveManager.get_settings().to_dict().duplicate(true)
	_ui._settings._draft.set_master_volume(0.17)
	_check("settings uses a copy", is_equal_approx(SaveManager.get_settings().master_volume, float(previous.master_volume)))
	_ui._close_auxiliary()
	_check("settings back returns to pause", _screen() == "paused")
	_ui._navigate(&"settings")
	_check("discarded settings reload saved values", is_equal_approx(_ui._settings._draft.master_volume, float(previous.master_volume)))
	_ui._settings._begin_rebind(&"attack")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	_ui._settings._input(escape)
	_check("Escape cancels rebind rather than unpausing", not _ui._settings.is_rebinding() and get_tree().paused)
	_ui._settings._begin_rebind(&"attack")
	var conflict := InputRemapper.get_bindings(&"dodge")[0]
	_ui._settings._finish_rebind(conflict)
	_check("conflicting binding stays in capture", _ui._settings.is_rebinding())
	_ui._settings.cancel_edit()
	_ui._settings._apply()
	var stored_volume := SaveManager.get_settings().master_volume
	_ui._settings._draft.set_master_volume(0.29)
	_check("further edits after Save stay staged", is_equal_approx(SaveManager.get_settings().master_volume, stored_volume))
	_ui._close_auxiliary()
	GameRoot.request_resume()
	await _settle()
	_check("resume returns to gameplay", _screen() == "playing" and not get_tree().paused)
	await _test_touch()
	await _test_upgrades()
	await _test_hud_and_effects()
	EventBus.enemy_killed.emit(null, &"grunt", 50, 20)
	GameRoot.request_game_over()
	await _settle()
	_check("positive reward reflects service finalization", _ui._summary._reward > 0)
	_check("game over captured after finalization", _screen() == "game_over" and not _ui._summary._summary.is_empty())
	var wallet := SaveManager.get_meta_wallet()
	_ui._summary.show_page(&"run_summary")
	_check("detailed summary page", _screen() == "run_summary")
	_ui._summary.show_page(&"meta_reward")
	_check("reward page", _screen() == "meta_reward")
	for i in range(3):
		_ui._summary.show_page(&"run_summary")
		_ui._summary.show_page(&"meta_reward")
	_check("reviewing rewards never double grants", SaveManager.get_meta_wallet() == wallet)
	_ui._navigate(&"armory")
	_check("postrun armory preserves canonical game over", GameRoot.get_current_state() == GameRoot.State.GAME_OVER)
	_ui._close_auxiliary()
	_check("Armory back returns to rewards", _screen() == "meta_reward")
	GameRoot.request_main_menu()
	await _settle()
	_check("postrun returns to menu", _screen() == "main_menu")
	_ui._navigate(&"daily")
	_check("daily has preview before launch", _ui._setup._daily and _ui._setup._daily_info.visible and GameRoot.get_current_state() == GameRoot.State.MAIN_MENU)
	_ui._setup._launch()
	await _settle()
	_check("daily uses existing command and seed", GameRoot.is_daily_run() and GameRoot.get_run().run_seed == DailyChallenge.seed_for_today())
	GameRoot.request_game_over()
	await _settle()
	GameRoot.request_restart()
	_check("retry preserves daily mode", GameRoot.is_daily_run())
	GameRoot.request_main_menu()
	await _settle()
	await _test_layouts()
	_test_layout_solver()
	_test_armory_and_save()
	await _test_tutorial()
	_check("summary zero time is finite", not RunSummaryPanel.performance({"kills": 9, "elapsed_seconds": 0}).contains("inf"))
	_check("summary clock handles hours", RunSummaryPanel.duration(3661) == "61:01")
	_check("summary clock clamps negative time", RunSummaryPanel.duration(-1) == "00:00")
	print("UI TESTS: %d checks, %d failed" % [_total, _failures.size()])
	for failure in _failures: print("FAIL: " + failure)
	get_tree().paused = false
	_ui.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)

func _screen() -> String:
	return _ui.get_debug_snapshot().active_screen

func _test_touch() -> void:
	_ui._touch.show()
	var joystick: TouchJoystick = _ui._touch.joystick
	joystick._begin(2, Vector2(100, 100))
	joystick._update(Vector2(145, 110))
	_check("touch stick acquires input", joystick.is_active() and joystick.get_value().length() > 0)
	var lift := InputEventScreenTouch.new()
	lift.index = 2
	lift.pressed = false
	joystick._input(lift)
	_check("normal release ends quietly without arming resume-ignore",
		not joystick.is_active() and joystick.get_value() == Vector2.ZERO and joystick._resume_ignore <= 0.0)
	joystick._begin(2, Vector2(100, 100))
	joystick._update(Vector2(145, 110))
	GameRoot.request_pause()
	await _settle()
	_check("modal cancels captured stick", not joystick.is_active() and joystick.get_value() == Vector2.ZERO)
	var button: TouchActionButton = _ui._touch._buttons[0]
	var emitted := [0]
	button.pressed.connect(func() -> void: emitted[0] += 1)
	var press := InputEventScreenTouch.new()
	press.index = 3
	press.pressed = true
	button._gui_input(press)
	_check("button fires on press-down", emitted[0] == 1)
	var second_press := InputEventScreenTouch.new()
	second_press.index = 4
	second_press.pressed = true
	button._gui_input(second_press)
	_check("second finger cannot double-fire a held button", emitted[0] == 1)
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = button.get_global_transform_with_canvas() * Vector2(500, 0)
	button._input(drag)
	_check("FIRE captures drag outside its bounds", button.get_aim_input().is_equal_approx(Vector2.RIGHT))
	drag.index = 4
	drag.position = button.get_global_transform_with_canvas() * Vector2(0, 500)
	button._input(drag)
	_check("other finger cannot redirect FIRE", button.get_aim_input().is_equal_approx(Vector2.RIGHT))
	var reload_button: TouchActionButton = _ui._touch._buttons[3]
	_check("manual reload is a separate touch action", reload_button.action_name == "reload")
	reload_button._gui_input(second_press)
	_check("reload finger does not release FIRE", button.is_held() and reload_button.is_held())
	reload_button.cancel()
	var emulated := InputEventMouseButton.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.pressed = false
	button._input(emulated)
	_check("synthetic mouse release cannot clear FIRE", button.is_held())
	var wrong_release := InputEventScreenTouch.new()
	wrong_release.index = 4
	wrong_release.pressed = false
	button._gui_input(wrong_release)
	_check("other finger release neither fires nor clears the hold", emitted[0] == 1 and button._held)
	var release := InputEventScreenTouch.new()
	release.index = 3
	release.pressed = false
	button._gui_input(release)
	_check("owning release clears without firing", emitted[0] == 1 and not button._held)
	_check("release clears aim", button.get_aim_input() == Vector2.ZERO)
	button._gui_input(press)
	var aborted := InputEventScreenTouch.new()
	aborted.index = 3
	aborted.canceled = true
	aborted.pressed = true
	button._input(aborted)
	_check("Android cancellation clears FIRE and aim", not button.is_held() and button.get_aim_input() == Vector2.ZERO)
	var count_after_cancel: int = emitted[0]
	button.cancel()
	button._fire()
	_check("cancelled button never fires", emitted[0] == count_after_cancel)
	GameRoot.request_resume()
	await _settle()

func _test_upgrades() -> void:
	GameRoot.begin_wave_transition()
	await _settle()
	_check("interwave has distinct presentation state", _screen() == "wave_transition")
	GameRoot.request_pause()
	GameRoot.request_resume()
	_check("pause resumes the original interwave state", _screen() == "wave_transition")
	GameRoot.end_wave_transition()
	EventBus.wave_started.emit(1, 3)
	var accepted := GameRoot.present_upgrade_selection_for_wave(1)
	await _settle()
	_check("wave opens upgrades through command", accepted and _screen() == "upgrade_selection")
	_check("upgrade choices are unlocked", not _ui._upgrade.is_locked() and _ui._upgrade._card_buttons.size() > 0)
	var before := GameRoot.get_run().selected_upgrades.duplicate()
	_ui._choose_upgrade(&"missing_upgrade")
	_check("invalid upgrade does not lock or mutate run", not _ui._upgrade.is_locked() and before == GameRoot.get_run().selected_upgrades)
	_ui._upgrade._card_buttons[0].pressed.emit()
	await _settle()
	_check("accepted choice locks cards", _ui._upgrade.is_locked())
	_check("accepted choice resumes gameplay", GameRoot.get_current_state() == GameRoot.State.PLAYING)
	var selected := GameRoot.get_run().selected_upgrades.duplicate()
	_ui._upgrade._card_buttons[0].pressed.emit()
	_check("double tap does not add a second upgrade", selected == GameRoot.get_run().selected_upgrades)

func _test_hud_and_effects() -> void:
	EventBus.player_health_changed.emit(18, 100)
	EventBus.stamina_changed.emit(42, 100)
	EventBus.wave_progressed.emit(3, 7, 12)
	_check("health has numeric low warning", _ui._hud._gauges.health_caption.text.contains("LOW HP") and is_equal_approx(_ui._hud._gauges.health_bar.value, 0.18))
	_check("stamina numeric and bar match", _ui._hud._gauges.stamina_caption.text.contains("42") and is_equal_approx(_ui._hud._gauges.stamina_bar.value, 0.42))
	_check("wave progress displayed", (_ui._hud._wave_label.text.contains("7 of 12") or _ui._hud._wave_label.text.contains("7/12")))
	_ui._hud._on_xp(15, 2, 15, 60)
	_check("XP bar displays component progress", is_equal_approx(_ui._hud._gauges.xp_bar.value, 0.25))
	_ui._banner.clear_all()
	_ui._banner.announce("Duplicate")
	_ui._banner.announce("Duplicate")
	_check("banner coalesces pending duplicates", _ui._banner.pending_count() == 1)
	for i in range(10): _ui._banner.announce("Announcement %d" % i)
	_check("banner queue bounded", _ui._banner.pending_count() <= 6)
	_ui._banner.set_reduced_motion(true)
	_ui._banner._process(0.1)
	_check("reduced motion banner has no pop", _ui._banner.scale == Vector2.ONE)
	# Bounded means clamped to MAX_POOL, not pinned to the initial pool size.
	# Asserting DEFAULT_POOL here would re-enshrine the bug where set_max_live()
	# clamped to the starting pool, so the ULTRA tier's request for 48 numbers
	# silently stayed at 32.
	_ui._numbers.set_max_live(999)
	_check("damage number pool bounded", _ui._numbers._max_live == DamageNumberLayer.MAX_POOL)
	_ui._numbers.set_max_live(48)
	_check("damage number pool honours a tier request", _ui._numbers._max_live == 48)
	_ui._numbers.set_max_live(1)
	_check("damage number pool has a floor", _ui._numbers._max_live == 4)
	_ui._numbers.set_max_live(DamageNumberLayer.DEFAULT_POOL)
	# Boss bar binds a typed EnemyBase (+BossController); give it the required
	# minimal child set (HealthComponent + EnemyStateMachine), exactly like the
	# encounter fixtures in run_tests.gd.
	var boss := EnemyBase.new()
	var hp := HealthComponent.new()
	hp.name = "HealthComponent"
	boss.add_child(hp)
	var boss_machine := EnemyStateMachine.new()
	boss_machine.name = "EnemyStateMachine"
	boss.add_child(boss_machine)
	add_child(boss)
	EventBus.boss_spawned.emit(boss, &"warlord")
	_check("boss event shows frame", _ui._boss_bar.visible)
	_ui._boss_bar.set_reduced_motion(true)
	hp.health_changed.emit(40, 100)
	_ui._boss_bar._process(0.1)
	_check("reduced motion boss ghost snaps", is_equal_approx(_ui._boss_bar._ghost.value, 0.4))
	boss.queue_free()
	await _settle()

func _test_layouts() -> void:
	var margins := UiSafeArea.insets(Vector2(1280, 720), Vector2(2560, 1440), Rect2(80, 0, 2400, 1400))
	_check("physical cutouts map to logical insets", margins == Vector4(40, 0, 40, 20))
	_check("missing safe area has no false inset", UiSafeArea.insets(Vector2(1280, 720), Vector2.ZERO, Rect2()) == Vector4.ZERO)
	for resolution in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(1024, 768), Vector2i(720, 1280)]:
		_viewport.size = resolution
		await _settle()
		for screen in [&"main_menu", &"run_setup", &"settings", &"armory", &"help", &"upgrade_selection", &"paused"]:
			_ui._show_screen(screen)
			await _settle()
			var panel: Control = _ui._screens[screen]
			_check("panel fits %s at %s" % [screen, resolution], panel.size.x <= resolution.x + 1 and panel.size.y <= resolution.y + 1)
			var fits := true
			for control in panel.find_children("*", "Button", true, false):
				if control.is_visible_in_tree():
					var rect: Rect2 = control.get_global_rect()
					fits = fits and rect.position.x >= -1 and rect.end.x <= resolution.x + 1
			_check("buttons fit horizontally %s at %s" % [screen, resolution], fits)
		_ui._show_screen(&"playing")
		_ui._touch.show()
		await _settle()
		var stick: Control = _ui._touch.joystick
		_check("stick does not cover skills %s" % resolution, not stick.get_rect().intersects(_ui._skill_bar.get_rect()))
		for button in _ui._touch._buttons:
			_check("touch target inside %s" % resolution, Rect2(Vector2.ZERO, Vector2(resolution)).encloses(button.get_rect()))
			_check("stick does not cover action %s" % resolution, not stick.get_rect().intersects(button.get_rect()))
			_check("skills do not cover action %s" % resolution, not _ui._skill_bar.get_rect().intersects(button.get_rect()))
	var large := SettingsData.new()
	large.text_scale = 2
	large.high_contrast = true
	large.reduced_motion = true
	_ui._apply_settings(large)
	_ui._show_screen(&"settings")
	await _settle()
	_check("live text scale metadata applied", _ui._menu.get_theme_default_font() == UiTheme.REGULAR)
	_ui._apply_settings(SaveManager.get_settings())

## Pure geometry contract for the overlay solver: exercised over every common
## Android resolution (16:9, 18:9, 19.5:9, 4:3, portrait) at every text scale.
func _test_layout_solver() -> void:
	var resolutions := [
		Vector2(1280, 720), Vector2(1920, 1080), Vector2(2340, 1080), Vector2(2400, 1080),
		Vector2(960, 540), Vector2(1024, 768), Vector2(1600, 720), Vector2(720, 1280),
		Vector2(1080, 2340), Vector2(800, 1280), Vector2(2560, 1600), Vector2(640, 360),
	]
	var controls := ["stick", "skills", "attack", "dodge", "swap", "reload"]
	var all_keys := controls + ["top_bar", "vitals", "minimap", "boss", "banner", "toast"]
	for view in resolutions:
		for scale in [1.0, 1.4, 2.0]:
			var plan := UiLayout.compute(view, scale)
			var tag := "%dx%d @%.1f" % [view.x, view.y, scale]
			for key in all_keys:
				var rect: Rect2 = plan[key]
				if UiLayout.is_collapsed(rect):
					continue
				_check("%s inside safe area %s" % [key, tag],
					rect.position.x >= -0.5 and rect.position.y >= -0.5
					and rect.end.x <= view.x + 0.5 and rect.end.y <= view.y + 0.5)
			for key in ["attack", "dodge", "swap", "reload"]:
				var target: Rect2 = plan[key]
				_check("%s meets touch floor %s" % [key, tag],
					minf(target.size.x, target.size.y) >= UiLayout.MIN_TOUCH - 0.01)
			for i in range(all_keys.size()):
				for j in range(i + 1, all_keys.size()):
					var a: Rect2 = plan[all_keys[i]]
					var b: Rect2 = plan[all_keys[j]]
					if UiLayout.is_collapsed(a) or UiLayout.is_collapsed(b):
						continue
					if all_keys[i] == "top_bar" or all_keys[j] == "top_bar":
						continue
					_check("%s and %s do not overlap %s" % [all_keys[i], all_keys[j], tag],
						not a.intersects(b))
	# Degenerate inputs must never produce a NaN or out-of-bounds rect.
	var sanitized := UiLayout.sanitize(Rect2(Vector2(NAN, -900), Vector2(INF, -5)), Vector2(1280, 720))
	_check("solver sanitizes degenerate rects",
		sanitized.position.x >= 0.0 and sanitized.size.x <= 1280.0 and sanitized.size.y >= 1.0)


func _test_armory_and_save() -> void:
	GameRoot.request_main_menu()
	_ui._navigate(&"armory")
	_meta.grant_currency(1000) # Test fixture uses service command, not UI state writes.
	_ui._armory.refresh()
	var rank := _meta.get_rank(&"whetstone")
	if not _meta.is_maxed(&"whetstone"):
		_meta.grant_currency(_meta.price_of(&"whetstone"))
		_ui._armory._on_buy(_meta, &"whetstone")
		_check("Armory delegates accepted purchase", _meta.get_rank(&"whetstone") == rank + 1)
	var settings := SettingsData.new()
	settings.from_dict(SaveManager.get_settings().to_dict())
	settings.set_reduced_motion(true)
	settings.set_text_scale(1.2)
	SaveManager.save_settings(settings)
	_check("settings persist through existing API", SaveManager.save_now())
	_check("existing ranks available to presentation", SaveManager.get_meta_ranks().size() > 0)
	_ui._armory.refresh()
	_check("Armory shows current wallet", _ui._armory._wallet_label.text.contains(str(_meta.get_wallet())))


func build_world(_arena: StringName) -> void:
	# Registered with GameRoot as the world-builder seam (Main does this at
	# runtime; the UI harness substitutes its own typed Callable).
	if is_instance_valid(_player):
		_player.free()
	_player = preload("res://tests/ui/ui_player_double.gd").new()
	add_child(_player)
	GameRoot.set_active_player(_player)


func _test_tutorial() -> void:
	var tutorial := TutorialManager.new()
	add_child(tutorial)
	tutorial.bind_banner(_ui._banner)
	tutorial.replay_next_run()
	GameRoot.request_play()
	await _settle()
	_check("first run activates coach", tutorial.is_active())
	GameRoot.request_pause()
	var before := tutorial._step_timer
	tutorial._process(5)
	_check("coach does not advance while paused", tutorial._step_timer == before)
	GameRoot.request_resume()
	for i in range(TutorialManager.STEP_ORDER.size()):
		tutorial._process(TutorialManager.STEP_TIMEOUT + 1)
	_check("timeout never falsely persists tutorial completion", not SaveManager.is_tutorial_completed())
	tutorial._on_run_started(1, 1)
	tutorial.skip_tutorial()
	_check("explicit skip uses existing save flag", SaveManager.is_tutorial_completed())
	tutorial.replay_next_run()
	_check("coach replay resets only tutorial flag", not SaveManager.is_tutorial_completed())
	GameRoot.request_main_menu()
	_check("coach stops on menu", not tutorial.is_active())
	tutorial.queue_free()
	await _settle()
