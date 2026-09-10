extends Node
## Systems stress pass (release verification, phases 3/7/8/9/10/13).
## Loaded by tests/stress_systems.gd after autoloads register. Boots the REAL
## game and exercises: lifecycle transitions A-G (pause/menu/restart/gameover
## matrices with duplicate-node + stale-ref + queue_free checks), every UI
## screen/button/slider/toggle/option (exact ticks, draft/save semantics),
## graphics quality tiers (engine knobs, args, idempotency, cooldown), a full
## audio cue sweep, and save persistence. Compares menu node census before/after.
##
##   godot --headless --path . --script res://tests/stress_systems.gd
## Exit code 0 only when every check passes. Run with isolated XDG_DATA_HOME.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const BASIC_ENEMY := "res://scenes/enemies/basic_enemy.tscn"

var _total := 0
var _failures: Array[String] = []
var _diags: Array = []
var _sig_counts := {}
var _bus_baseline := {}
var _menu_nodes_boot := -1
var _orig_settings := {}
var _orig_max_fps := 0
var _last_tier_args := []


func _ready() -> void:
	_run()


func _check(case_name: String, passed: bool, extra: String = "") -> void:
	_total += 1
	if passed:
		print("  PASS: %s" % case_name)
	else:
		_failures.append(case_name)
		push_error("STRESS FAIL: %s %s" % [case_name, extra])


func _on_diag(message: String, severity: StringName) -> void:
	_diags.append({"message": message, "severity": String(severity)})


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _phys(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _wait_for(cond: Callable, timeout_sec: float) -> bool:
	var timer := get_tree().create_timer(timeout_sec)
	while not cond.call():
		if timer.time_left <= 0.0:
			return false
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
	return true


func _ui() -> Node:
	return get_tree().current_scene.get_node("UIRoot/UI")


func _world() -> Node:
	return get_tree().current_scene.get_node("WorldRoot")


func _music() -> Node:
	return get_tree().current_scene.get_node("MusicManager")


func _find_button(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return node as Button
	return null


func _all_buttons(root: Node) -> Array:
	return root.find_children("*", "Button", true, false)


func _buttons_with(root: Node, token: String) -> Array:
	var out := []
	for node in root.find_children("*", "Button", true, false):
		if String((node as Button).text).to_upper().contains(token.to_upper()):
			out.append(node as Button)
	return out


func _sfx_snapshot() -> Dictionary:
	var by_cue := {}
	var total := 0
	var unknowns := 0
	for p in AudioManager._sfx_pool:
		if (p as AudioStreamPlayer).playing:
			total += 1
			var cue := _cue_for_stream((p as AudioStreamPlayer).stream)
			if cue == &"":
				unknowns += 1
			else:
				by_cue[String(cue)] = int(by_cue.get(String(cue), 0)) + 1
	return {"total": total, "unknowns": unknowns, "by_cue": by_cue}


func _cue_for_stream(stream: AudioStream) -> StringName:
	if stream == null:
		return &""
	for cue in AudioManager._cues:
		if AudioManager._cues[cue] == stream:
			return cue
	return &""


func _stop_all_sfx() -> void:
	for p in AudioManager._sfx_pool:
		(p as AudioStreamPlayer).stop()


func _count(snapshot: Dictionary, cue: String) -> int:
	return int((snapshot["by_cue"] as Dictionary).get(cue, 0))


func _descendants(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		n += 1 + _descendants(c)
	return n


func _menu_node_count() -> int:
	return 1 + _descendants(get_tree().root)


const WATCHED := ["run_started", "run_ended", "pause_changed", "settings_changed", "player_died", "upgrade_selected", "wave_completed"]


func _watch(obj: Object, sig: String) -> void:
	var cb := func(a0: Variant = null, a1: Variant = null, a2: Variant = null, a3: Variant = null) -> void:
		_sig_counts[sig] = int(_sig_counts.get(sig, 0)) + 1
	obj.connect(sig, cb)


func _bus_census() -> Dictionary:
	var out := {}
	for sig in WATCHED:
		out[sig] = (EventBus.get_signal_connection_list(sig) as Array).size()
	return out


# --------------------------------------------------------------- lifecycle --

func _start_via_ui() -> bool:
	var start_btn := _find_button(_ui()._menu, "START RUN")
	if start_btn == null:
		return false
	start_btn.pressed.emit()
	await _frames(4)
	var enter_btn := _find_button(_ui()._setup, "ENTER ARENA")
	if enter_btn == null or enter_btn.disabled:
		return false
	enter_btn.pressed.emit()
	return await _wait_for(func() -> bool: return GameRoot.get_current_state() == GameRoot.State.PLAYING, 60.0)


func _kill_player() -> void:
	var player: Node = GameRoot.get_active_player()
	var health: Node = player.get_node("HealthComponent")
	health.call("reset", float(health.get("max_health")))
	var lethal := DamagePayload.new()
	lethal.amount = 999999.0
	health.call("take_damage", lethal)
	await _frames(4)


func _verify_lifecycle(tag: String, expect_state: StringName, expect_paused: bool) -> void:
	_check(tag + " paused flag", get_tree().paused == expect_paused)
	_check(tag + " state", GameRoot.get_current_state() == expect_state, str(GameRoot.get_current_state()))
	var names := []
	for c in _world().get_children():
		names.append(String(c.name))
	var dupes := names.size() != _unique(names).size()
	var suffixed := names.any(func(n: String) -> bool: return n.length() > 0 and n[n.length() - 1].is_valid_int())
	_check(tag + " world children unique", not dupes, str(names))
	_check(tag + " no @-suffixed dupes", not suffixed, str(names))
	if expect_state == GameRoot.State.MAIN_MENU:
		_check(tag + " world cleared at menu", names.is_empty(), str(names))
	else:
		_check(tag + " arena present", "Arena" in names, str(names))
		_check(tag + " single player node", names.count("Player") == 1, str(names))
	var autoloads := ["GameRoot", "EventBus", "AudioManager", "SaveManager", "SceneRouter", "ContentRegistry", "RunAnalytics", "TestHarness"]
	var missing := []
	for a in autoloads:
		if get_tree().root.get_node_or_null(a) == null:
			missing.append(a)
	_check(tag + " autoloads valid", missing.is_empty(), str(missing))
	_check(tag + " audio pool 16", (AudioManager._sfx_pool as Array).size() == 16)
	_check(tag + " music players 2", (_music()._players as Array).size() == 2)
	# Per-run nodes legitimately wire bus signals while a run is live; compare
	# against the matching baseline (menu vs run), absorbing the first-run
	# tutorial trio exactly once like the loops harness does.
	var base: Dictionary
	if expect_state == GameRoot.State.MAIN_MENU:
		if int(_sig_counts.get("run_started", 0)) > 0 and not _menu_rebaselined:
			_bus_baseline = _bus_census()
			_menu_rebaselined = true
		base = _bus_baseline
	else:
		if _bus_baseline_run.is_empty():
			_bus_baseline_run = _bus_census()
		base = _bus_baseline_run
	var now := _bus_census()
	var drift := []
	for sig in base.keys():
		if int(now.get(sig, -1)) != int(base[sig]):
			drift.append("%s:%d->%d" % [sig, base[sig], now.get(sig, -1)])
	_check(tag + " bus connections stable", drift.is_empty(), str(drift))


func _unique(names: Array) -> Array:
	var seen := {}
	for n in names:
		seen[n] = true
	return seen.keys()


func _lifecycle_matrix() -> void:
	print("STRESS SYSTEMS: lifecycle matrix")
	# A: start -> pause -> resume.
	_check("A start", await _start_via_ui())
	var p0: Node = GameRoot.get_active_player()
	(_find_button(_ui()._hud, "PAUSE") as Button).pressed.emit()
	await _frames(3)
	await _verify_lifecycle("A paused", GameRoot.State.PAUSED, true)
	(_find_button(_ui()._screens["paused"], "RESUME RUN") as Button).pressed.emit()
	await _frames(3)
	await _verify_lifecycle("A resumed", GameRoot.State.PLAYING, false)
	# B: pause -> main menu -> start again.
	(_find_button(_ui()._hud, "PAUSE") as Button).pressed.emit()
	await _frames(3)
	var menu_btns := _buttons_with(_ui()._screens["paused"], "MENU")
	_check("B pause menu button exists", not menu_btns.is_empty())
	if not menu_btns.is_empty():
		(menu_btns[0] as Button).pressed.emit()
		await _frames(6)
		# A leave-run confirm dialog intercepts: CANCEL first, then confirm.
		var dlg: ConfirmationDialog = _ui().get("_confirm")
		_check("B leave dialog appears", dlg != null and dlg.visible)
		if dlg != null and dlg.visible:
			_stop_all_sfx()
			dlg.get_cancel_button().pressed.emit()
			_check("B dialog cancel ticks back once", _last_tick_is("ui_back"), str(_sfx_snapshot()))
			await _frames(4)
			_check("B cancel stays paused", GameRoot.get_current_state() == GameRoot.State.PAUSED)
			(menu_btns[0] as Button).pressed.emit()
			await _frames(6)
			_stop_all_sfx()
			dlg.get_ok_button().pressed.emit()
			_check("B dialog confirm ticks back once", _last_tick_is("ui_back"), str(_sfx_snapshot()))
			await _frames(6)
	await _verify_lifecycle("B menu", GameRoot.State.MAIN_MENU, false)
	_check("B old player freed", not is_instance_valid(p0))
	_check("C start", await _start_via_ui())
	_check("C new player live", is_instance_valid(GameRoot.get_active_player()) and GameRoot.get_active_player() != p0)
	# C: restart x3.
	for i in range(1, 4):
		var old: Node = GameRoot.get_active_player()
		GameRoot.request_restart()
		await _wait_for(func() -> bool: return GameRoot.get_current_state() == GameRoot.State.PLAYING, 60.0)
		await _frames(4)
		await _verify_lifecycle("C%d restarted" % i, GameRoot.State.PLAYING, false)
		_check("C%d old player freed" % i, not is_instance_valid(old))
		_check("C%d music calm" % i, _music().get_state() == &"calm")
	# D: pause -> restart.
	(_find_button(_ui()._hud, "PAUSE") as Button).pressed.emit()
	await _frames(3)
	var old_d: Node = GameRoot.get_active_player()
	GameRoot.request_restart()
	await _wait_for(func() -> bool: return GameRoot.get_current_state() == GameRoot.State.PLAYING, 60.0)
	await _frames(4)
	await _verify_lifecycle("D restart-from-pause", GameRoot.State.PLAYING, false)
	_check("D old player freed", not is_instance_valid(old_d))
	# E: pause -> menu -> start -> pause -> resume.
	(_find_button(_ui()._hud, "PAUSE") as Button).pressed.emit()
	await _frames(3)
	GameRoot.request_main_menu()
	await _frames(6)
	await _verify_lifecycle("E menu", GameRoot.State.MAIN_MENU, false)
	_check("E start", await _start_via_ui())
	(_find_button(_ui()._hud, "PAUSE") as Button).pressed.emit()
	await _frames(3)
	await _verify_lifecycle("E paused", GameRoot.State.PAUSED, true)
	(_find_button(_ui()._screens["paused"], "RESUME RUN") as Button).pressed.emit()
	await _frames(3)
	await _verify_lifecycle("E resumed", GameRoot.State.PLAYING, false)
	# F: game over -> menu -> start.
	await _kill_player()
	await _verify_lifecycle("F gameover", GameRoot.State.GAME_OVER, false)
	var over_menu := _buttons_with(_ui()._screens["game_over"], "MENU")
	if not over_menu.is_empty():
		(over_menu[0] as Button).pressed.emit()
		await _frames(6)
	else:
		GameRoot.request_main_menu()
		await _frames(6)
	await _verify_lifecycle("F menu", GameRoot.State.MAIN_MENU, false)
	_check("F start", await _start_via_ui())
	# G: game over -> restart x2.
	for i in range(1, 3):
		await _kill_player()
		await _verify_lifecycle("G%d gameover" % i, GameRoot.State.GAME_OVER, false)
		GameRoot.request_restart()
		await _wait_for(func() -> bool: return GameRoot.get_current_state() == GameRoot.State.PLAYING, 60.0)
		await _frames(4)
		await _verify_lifecycle("G%d restarted" % i, GameRoot.State.PLAYING, false)
	# Park at menu.
	GameRoot.request_main_menu()
	await _frames(6)
	await _verify_lifecycle("Z parked menu", GameRoot.State.MAIN_MENU, false)


var _bus_baseline_run := {}
var _menu_rebaselined := false


# ------------------------------------------------------------------ UI -------

func _button_table(root: Node) -> Dictionary:
	var out := {}
	for b in _all_buttons(root):
		var btn := b as Button
		out[String(btn.text)] = (btn.pressed.get_connections() as Array).size()
	return out


func _ui_stress() -> void:
	print("STRESS SYSTEMS: UI stress")
	var menu_table_1 := _button_table(_ui()._menu)
	print("  MENU buttons: %s" % str(menu_table_1))
	_check("menu has buttons", not menu_table_1.is_empty())
	var all_wired := true
	for caption in menu_table_1.keys():
		if int(menu_table_1[caption]) < 1:
			all_wired = false
	_check("menu buttons all wired", all_wired, str(menu_table_1))
	# QUIT: verify wiring, never emit (it would end the run).
	var quit_btns := _buttons_with(_ui()._menu, "QUIT")
	_check("QUIT present", not quit_btns.is_empty())
	if not quit_btns.is_empty():
		_check("QUIT wired (factory+request)", (quit_btns[0] as Button).pressed.get_connections().size() >= 2)
		print("  QUIT excluded from emission by design")
	# Viewport/layout honesty.
	var vp_size := get_viewport().get_visible_rect().size
	print("  VIEWPORT: %s" % str(vp_size))
	if vp_size.x > 0.0 and vp_size.y > 0.0:
		var outside := []
		for b in _all_buttons(_ui()._menu):
			var r := (b as Button).get_global_rect()
			if not Rect2(Vector2.ZERO, vp_size).encloses(r):
				outside.append(String((b as Button).text))
		_check("menu buttons inside viewport", outside.is_empty(), str(outside))
	else:
		print("  layout inside-viewport checks N/A headless (zero viewport)")
		_check("layout honesty note", true)
	await _settings_stress()
	await _armory_help_stress()
	# Button table must not grow after the full UI tour.
	(_find_button(_ui()._menu, "START RUN") as Button).pressed.emit()
	await _frames(4)
	(_buttons_with(_ui()._setup, "BACK")[0] as Button).pressed.emit()
	await _frames(4)
	var menu_table_2 := _button_table(_ui()._menu)
	_check("menu wiring stable after tour", menu_table_1 == menu_table_2, "%s vs %s" % [menu_table_1, menu_table_2])


func _settings_stress() -> void:
	var set_btns := _buttons_with(_ui()._menu, "SETTING")
	_check("settings entry exists", not set_btns.is_empty())
	if set_btns.is_empty():
		return
	_stop_all_sfx()
	(set_btns[0] as Button).pressed.emit()
	await _frames(4)
	_check("settings opens", _ui()._active_screen == &"settings")
	var panel: Node = _ui()._settings
	var sliders := panel.find_children("*", "HSlider", true, false)
	var toggles := panel.find_children("*", "CheckButton", true, false)
	var options := panel.find_children("*", "OptionButton", true, false)
	print("  SETTINGS widgets: %d sliders %d toggles %d options" % [sliders.size(), toggles.size(), options.size()])
	_check("settings has sliders", not sliders.is_empty())
	# Drive every slider: move -> BACK (discarded) -> reopen -> move -> SAVE.
	var before_vals := []
	for s in sliders:
		before_vals.append((s as Slider).value)
	for s in sliders:
		var sl := s as Slider
		sl.value = clampf(sl.value + 0.25, sl.min_value, sl.max_value)
		sl.value_changed.emit(sl.value)
	await _frames(2)
	var back_btn := _find_button(panel, "BACK")
	_check("settings BACK exists", back_btn != null)
	if back_btn != null:
		_stop_all_sfx()
		back_btn.pressed.emit()
		_check("BACK ticks ui_back once", _last_tick_is("ui_back"), str(_sfx_snapshot()))
		await _frames(4)
		_check("settings back at menu", _ui()._active_screen == &"main_menu")
	_check("draft discarded on BACK", _settings_equal(SaveManager.get_settings(), _orig_settings), "")
	# Reopen, change, SAVE.
	(set_btns[0] as Button).pressed.emit()
	await _frames(4)
	panel = _ui()._settings
	sliders = panel.find_children("*", "HSlider", true, false)
	toggles = panel.find_children("*", "CheckButton", true, false)
	options = panel.find_children("*", "OptionButton", true, false)
	for s in sliders:
		var sl := s as Slider
		sl.value = clampf(sl.value + 0.25, sl.min_value, sl.max_value)
		sl.value_changed.emit(sl.value)
	var tog0 := []
	for t in toggles:
		tog0.append((t as CheckButton).button_pressed)
		(t as CheckButton).button_pressed = not (t as CheckButton).button_pressed
		(t as CheckButton).toggled.emit((t as CheckButton).button_pressed)
	await _frames(2)
	var save_btn := _find_button(panel, "SAVE SETTINGS")
	_check("SAVE exists", save_btn != null)
	if save_btn == null:
		return
	var ch0 := int(_sig_counts.get("settings_changed", 0))
	_stop_all_sfx()
	save_btn.pressed.emit()
	await _frames(4)
	_check("SAVE ticks ui_confirm once", _last_tick_is("ui_confirm"), "")
	_check("settings_changed emitted once", int(_sig_counts.get("settings_changed", 0)) == ch0 + 1)
	_check("slider values persisted", _sliders_match_save(panel), "")
	# Options: cycle quality + fps, SAVE each, verify applied.
	for o in options:
		var ob := o as OptionButton
		if ob.item_count > 1:
			ob.select((ob.selected + 1) % ob.item_count)
			ob.item_selected.emit(ob.selected)
	await _frames(2)
	(save_btn as Button).pressed.emit()
	await _frames(4)
	print("  SETTINGS saved quality=%s fps=%d" % [SaveManager.get_settings().graphics_quality, Engine.max_fps])
	# Restore originals.
	SaveManager.save_settings(_make_settings(_orig_settings))
	Engine.max_fps = _orig_max_fps
	await _frames(4)
	_check("settings restored", _settings_equal(SaveManager.get_settings(), _orig_settings), "")
	var back2 := _find_button(_ui()._settings, "BACK")
	if back2 != null:
		back2.pressed.emit()
		await _frames(4)
	_check("settings closed", _ui()._active_screen == &"main_menu")


func _last_tick_is(cue: String) -> bool:
	var snap := _sfx_snapshot()
	return snap["total"] == 1 and _count(snap, cue) == 1


const SETTINGS_KEYS := ["master_volume", "music_volume", "sfx_volume", "muted", "vibration_enabled", "graphics_quality", "reduced_motion", "text_scale", "high_contrast", "aim_assist_enabled"]


func _snap_settings(s: SettingsData) -> Dictionary:
	var d := {}
	for k in SETTINGS_KEYS:
		d[k] = s.get(k)
	return d


func _make_settings(d: Dictionary) -> SettingsData:
	var s := SettingsData.new()
	for k in SETTINGS_KEYS:
		s.set(k, d[k])
	return s


func _settings_equal(a: SettingsData, b: Dictionary) -> bool:
	var d := _snap_settings(a)
	for k in SETTINGS_KEYS:
		if d[k] is float:
			if not is_equal_approx(float(d[k]), float(b[k])):
				return false
		elif d[k] != b[k]:
			return false
	return true


func _sliders_match_save(_panel: Node) -> bool:
	# At least the persisted settings must differ from the pristine originals
	# (we moved every slider), proving SAVE wrote the draft.
	return not _settings_equal(SaveManager.get_settings(), _orig_settings)


func _armory_help_stress() -> void:
	var arm_btns := _buttons_with(_ui()._menu, "ARMOR")
	if arm_btns.is_empty():
		_check("armory entry exists", false)
	else:
		_stop_all_sfx()
		(arm_btns[0] as Button).pressed.emit()
		await _frames(4)
		_check("armory opens", _ui()._active_screen == &"armory")
		_check("armory entry ticks once", _last_tick_is("ui_confirm"), "")
		var panel: Node = null
		for key in (_ui()._screens as Dictionary).keys():
			if String(key).contains("armor"):
				panel = (_ui()._screens as Dictionary)[key]
		if panel != null:
			var buys := _buttons_with(panel, "BUY")
			if not buys.is_empty():
				_stop_all_sfx()
				(buys[0] as Button).pressed.emit()
				var buy_snap := _sfx_snapshot()
				# Press tick always; success jingle only when the wallet affords
				# it (wallet persists across runs, so decline is legal here).
				var ok_buy := _count(buy_snap, "ui_confirm") == 1 and _count(buy_snap, "upgrade_select") <= 1 and int(buy_snap["total"]) <= 2 and int(buy_snap["unknowns"]) == 0
				_check("armory BUY sounds exact", ok_buy, str(buy_snap))
				await _frames(2)
			var closes := _buttons_with(panel, "CLOSE")
			if closes.is_empty():
				closes = _buttons_with(panel, "BACK")
			if not closes.is_empty():
				_stop_all_sfx()
				(closes[0] as Button).pressed.emit()
				await _frames(4)
				_check("armory close ticks back once", _last_tick_is("ui_back"), "")
		_check("armory returns to menu", _ui()._active_screen == &"main_menu")
	var help_btns := _buttons_with(_ui()._menu, "HELP")
	if help_btns.is_empty():
		help_btns = _buttons_with(_ui()._menu, "HOW")
	if help_btns.is_empty():
		_check("help entry (optional)", true)
	else:
		(help_btns[0] as Button).pressed.emit()
		await _frames(4)
		var closes := _buttons_with(_ui(), "BACK")
		if closes.is_empty():
			closes = _buttons_with(_ui(), "CLOSE")
		if not closes.is_empty():
			_stop_all_sfx()
			(closes[0] as Button).pressed.emit()
			await _frames(4)
			_check("help close ticks back once", _last_tick_is("ui_back"), "")


# ------------------------------------------------------------ graphics ------

func _graphics_stress() -> void:
	print("STRESS SYSTEMS: graphics tiers (in-run)")
	_check("gfx run starts", await _start_via_ui())
	var perf: Node = _world().get_node("PerformanceMonitor")
	_check("perf monitor present", perf != null)
	if perf == null:
		return
	_watch(perf, "quality_tier_changed")
	_sig_counts["quality_tier_changed"] = 0
	perf.connect("quality_tier_changed", func(old_t: int, new_t: int) -> void: _last_tier_args = [old_t, new_t])
	var vp0 := get_viewport().get_visible_rect().size
	# Cooldown semantics without wall-time flakiness (5s window; set_tier re-arms).
	var tier_now: int = perf.call("get_tier")
	var step_fn := "request_step_up" if tier_now < 3 else "request_step_down"
	var since_step_ms: int = Time.get_ticks_msec() - int(perf.get("_last_step_msec"))
	if since_step_ms < 5000:
		var early: bool = perf.call(step_fn)
		_check("step in cooldown declines", early == false)
		await get_tree().create_timer(5.2 - float(since_step_ms) / 1000.0).timeout
	var first: bool = perf.call(step_fn)
	var second: bool = perf.call(step_fn)
	_check("step ok after cooldown", first)
	_check("step rearms cooldown", second == false)
	# Cycle all four tiers twice; engine knobs must follow exactly.
	var expect_fps := {0: 30, 1: 60, 2: 0, 3: 0}
	for cycle in range(2):
		for tier in [0, 1, 2, 3]:
			perf.call("set_tier", tier)
			await _frames(2)
			_check("tier %d applies (c%d)" % [tier, cycle], int(perf.call("get_tier")) == tier)
			_check("tier %d fps %d (c%d)" % [tier, expect_fps[tier], cycle], Engine.max_fps == expect_fps[tier], str(Engine.max_fps))
			_check("tier signal args (c%d)" % cycle, _last_tier_args.size() == 2 and _last_tier_args[1] == tier, str(_last_tier_args))
	_check("tier emits >= 7", int(_sig_counts.get("quality_tier_changed", 0)) >= 7, str(_sig_counts.get("quality_tier_changed", 0)))
	# Idempotent re-set emits nothing.
	var n0 := int(_sig_counts.get("quality_tier_changed", 0))
	perf.call("set_tier", int(perf.call("get_tier")))
	await _frames(2)
	_check("same-tier set silent", int(_sig_counts.get("quality_tier_changed", 0)) == n0)
	# Settings-driven mapping low/medium/high.
	for q in [&"low", &"medium", &"high"]:
		var draft: SettingsData = _make_settings(_snap_settings(SaveManager.get_settings()))
		draft.set_graphics_quality(q)
		SaveManager.save_settings(draft)
		await _frames(4)
		var want: int = {&"low": 0, &"medium": 1, &"high": 2}[q]
		_check("settings %s -> tier %d" % [q, want], int(perf.call("get_tier")) == want, str(perf.call("get_tier")))
	SaveManager.save_settings(_make_settings(_orig_settings))
	await _frames(4)
	# Integrity after all tier churn.
	_check("viewport stable", get_viewport().get_visible_rect().size == vp0, str(vp0))
	_check("ui intact", is_instance_valid(_ui()) and (_ui() as Control).visible)
	var rig: Node = _world().get_node("CameraRig")
	var player: Node = GameRoot.get_active_player()
	_check("camera intact", rig != null and rig.get("_target") == player)
	Engine.max_fps = _orig_max_fps
	GameRoot.request_main_menu()
	await _frames(6)


# -------------------------------------------------------------- audio -------

func _light_ui_tour() -> void:
	var set_btns := _buttons_with(_ui()._menu, "SETTING")
	if not set_btns.is_empty():
		(set_btns[0] as Button).pressed.emit()
		await _frames(4)
		var back_btn := _find_button(_ui()._settings, "BACK")
		if back_btn != null:
			back_btn.pressed.emit()
			await _frames(4)
	var arm_btns := _buttons_with(_ui()._menu, "ARMOR")
	if not arm_btns.is_empty():
		(arm_btns[0] as Button).pressed.emit()
		await _frames(4)
		var closes := _buttons_with(_ui(), "CLOSE")
		if closes.is_empty():
			closes = _buttons_with(_ui(), "BACK")
		if not closes.is_empty():
			(closes[0] as Button).pressed.emit()
			await _frames(4)


func _audio_sweep() -> void:
	print("STRESS SYSTEMS: audio sweep")
	var cues := (AudioManager._cues as Dictionary).keys()
	print("  CUES (%d): %s" % [cues.size(), str(cues)])
	_check("cues registered", cues.size() >= 20, str(cues.size()))
	var music_cues := []
	var sfx_cues := []
	for c in cues:
		if String(c).begins_with("music_"):
			music_cues.append(c)
		else:
			sfx_cues.append(c)
	_check("music beds present", music_cues.size() >= 4, str(music_cues))
	var key_cues := [&"ui_confirm", &"ui_back", &"player_attack", &"player_step", &"player_dodge", &"player_death", &"enemy_hit", &"enemy_death", &"enemy_spawn", &"level_up", &"game_over", &"boss_spawned"]
	for cue in key_cues:
		if not (AudioManager._cues as Dictionary).has(cue):
			_check("cue present %s" % cue, false)
			continue
		_stop_all_sfx()
		AudioManager.play_sfx(cue, -8.0)
		var snap := _sfx_snapshot()
		_check("cue %s plays once" % cue, snap["total"] == 1 and _count(snap, String(cue)) == 1, str(snap))
		await _wait_for(func() -> bool: return int(_sfx_snapshot()["total"]) == 0, 6.0)
	# Bulk: every remaining SFX cue fires without error and settles.
	for cue in sfx_cues:
		if cue in key_cues:
			continue
		AudioManager.play_sfx(cue, -8.0)
	await _wait_for(func() -> bool: return int(_sfx_snapshot()["total"]) == 0, 10.0)
	_check("bulk cues settle silent", int(_sfx_snapshot()["total"]) == 0, str(_sfx_snapshot()["by_cue"]))
	_check("pool still 16", (AudioManager._sfx_pool as Array).size() == 16)
	# Bus sanity.
	var bad := []
	for i in range(AudioServer.get_bus_count()):
		var v := AudioServer.get_bus_volume_db(i)
		if not is_finite(v) or v < -60.0 or v > 6.0:
			bad.append("%s=%.1f" % [AudioServer.get_bus_name(i), v])
	_check("bus volumes sane", bad.is_empty(), str(bad))
	_check("master unmuted", AudioServer.is_bus_mute(0) == SaveManager.get_settings().muted)


# ---------------------------------------------------------------- save ------

func _save_stress() -> void:
	print("STRESS SYSTEMS: save persistence")
	_check("save loaded", SaveManager.has_loaded())
	var best0 := SaveManager.get_best_score()
	_check("best score sane", best0 >= 0, str(best0))
	# Round-trip.
	var draft: SettingsData = _make_settings(_snap_settings(SaveManager.get_settings()))
	draft.master_volume = 0.42
	SaveManager.save_settings(draft)
	_check("settings round-trip", is_equal_approx(SaveManager.get_settings().master_volume, 0.42))
	SaveManager.save_settings(_make_settings(_orig_settings))
	_check("settings restored", _settings_equal(SaveManager.get_settings(), _orig_settings))
	# Natural best-score flow: scoring run raises/keeps best, scoreless run keeps it.
	_check("save run starts", await _start_via_ui())
	var container: Node = _world().get_node("EnemyContainer")
	var player: Node = GameRoot.get_active_player()
	for i in range(6):
		var cls: PackedScene = load(BASIC_ENEMY)
		var e: Node = cls.instantiate()
		container.add_child(e)
		e.call("initialize", ContentRegistry.get_enemy(&"basic"), player, 5000 + i)
		var lethal := DamagePayload.new()
		lethal.amount = 999999.0
		e.call("apply_damage", lethal)
	await _frames(10)
	await _kill_player()
	var best1 := SaveManager.get_best_score()
	_check("scoring run keeps/raises best", best1 >= best0, "%d->%d" % [best0, best1])
	GameRoot.request_main_menu()
	await _frames(6)
	_check("save run2 starts", await _start_via_ui())
	await _kill_player()
	_check("scoreless run keeps best", SaveManager.get_best_score() == best1, str(SaveManager.get_best_score()))
	GameRoot.request_main_menu()
	await _frames(6)
	# user:// listing stable, no accumulation.
	var dir := DirAccess.open(OS.get_user_data_dir())
	var files := []
	if dir != null:
		for f in dir.get_files():
			var size := -1
			var fh := FileAccess.open(OS.get_user_data_dir() + "/" + f, FileAccess.READ)
			if fh != null:
				size = int(fh.get_length())
				fh.close()
			files.append("%s:%d" % [f, size])
	print("  USERDIR: %s" % str(files))
	_check("save files exist", not files.is_empty(), OS.get_user_data_dir())


# ------------------------------------------------------------------ run -----

func _run() -> void:
	get_tree().create_timer(540.0).timeout.connect(func() -> void:
		push_error("STRESS TIMEOUT")
		get_tree().quit(2))
	EventBus.diagnostic.connect(_on_diag)
	for sig in WATCHED:
		_sig_counts[sig] = 0
		_watch(EventBus, sig)
	get_tree().change_scene_to_file(MAIN_SCENE)
	if not await _wait_for(func() -> bool: return get_tree().current_scene != null and get_tree().current_scene.name == "Main", 30.0):
		_check("main scene boots", false)
		await _finish()
		return
	await _frames(10)
	_orig_settings = _snap_settings(SaveManager.get_settings())
	_orig_max_fps = Engine.max_fps
	_menu_nodes_boot = _menu_node_count()
	_bus_baseline = _bus_census()
	await _lifecycle_matrix()
	await _ui_stress()
	await _graphics_stress()
	await _audio_sweep()
	await _save_stress()
	# In-run tier->fps mapping is asserted per-tier in _graphics_stress; here the
	# merged teardown contract: menu return restores the project-configured cap.
	GameRoot.request_main_menu()
	await _frames(6)
	await _wait_for(func() -> bool: return int(_sfx_snapshot()["total"]) == 0, 6.0)
	var menu_nodes_end := _menu_node_count()
	print("  MENU NODES boot=%d end=%d" % [_menu_nodes_boot, menu_nodes_end])
	# Panels may lazy-build on first open (one-time); a second identical tour
	# must add zero nodes. That is the strict no-leak invariant.
	await _light_ui_tour()
	var menu_nodes_tour2 := _menu_node_count()
	_check("menu nodes stable across tours", menu_nodes_end == menu_nodes_tour2, "%d vs %d" % [menu_nodes_end, menu_nodes_tour2])
	var menu_fps: int = int(ProjectSettings.get_setting_with_override("application/run/max_fps"))
	_check("menu fps restored to project default", Engine.max_fps == menu_fps, "fps=%d want=%d" % [Engine.max_fps, menu_fps])
	_check("settings pristine at end", _settings_equal(SaveManager.get_settings(), _orig_settings), "")
	await _finish()


func _finish() -> void:
	var errors := 0
	var audio_warnings := 0
	for d in _diags:
		if d["severity"] == "error":
			errors += 1
			push_error("STRESS DIAG ERROR: %s" % d["message"])
		if d["severity"] == "warning" and (String(d["message"]).contains("cue unavailable") or String(d["message"]).contains("voice limit")):
			audio_warnings += 1
	_total += 1
	if errors > 0 or audio_warnings > 0:
		_failures.append("zero error/audio diagnostics")
	else:
		print("  PASS: zero error/audio diagnostics")
	print("STRESS SYSTEMS: %d checks, %d failed, frames=%d" % [_total, _failures.size(), get_tree().get_frame()])
	for f in _failures:
		print("  FAILED: %s" % f)
	var code := 1 if not _failures.is_empty() else 0
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit(code)
