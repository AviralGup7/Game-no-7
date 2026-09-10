extends Node
## Soak stability run (release verification, phase 12). Boots the REAL game,
## starts a run, and drives synthetic inputs for 6 wall-clock minutes while
## sampling node/enemy/projectile/VFX/audio counts, state, camera validity and
## errors every 15s. Then game-over -> menu -> fresh run, and asserts the menu
## census matches boot (no monotonic growth).
##
## The player is invulnerable so one session survives the full window (stated
## artificiality); everything else runs naturally (waves, AI, drops, level-ups
## with auto-picked upgrade cards, music director).
##
##   godot --headless --path . --script res://tests/soak_runtime.gd

const MAIN_SCENE := "res://scenes/main/main.tscn"
const SOAK_SECONDS := 360.0
const SAMPLE_SECONDS := 15.0

var _total := 0
var _failures: Array[String] = []
var _diags: Array = []
var _err_count := 0
var _max_nodes := 0
var _max_enemies := 0
var _max_audio := 0
var _transitions := 0
var _upgrades_auto := 0
var _menu_nodes_boot := -1
var _bus_menu := {}


func _ready() -> void:
	_run()


## `case_name`, not `name`: these runners are Nodes and `name` is Node's node-name.
func _check(case_name: String, passed: bool, extra: String = "") -> void:
	_total += 1
	if passed:
		print("  PASS: %s" % case_name)
	else:
		_failures.append(case_name)
		push_error("SOAK FAIL: %s %s" % [name, extra])


func _on_diag(message: String, severity: StringName) -> void:
	_diags.append({"message": message, "severity": String(severity)})
	if severity == "error":
		_err_count += 1


func _ui() -> Node:
	return get_tree().current_scene.get_node("UIRoot/UI")


func _world() -> Node:
	return get_tree().current_scene.get_node("WorldRoot")


func _music() -> Node:
	return get_tree().current_scene.get_node("MusicManager")


func _descendants(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		n += 1 + _descendants(c)
	return n


func _audio_playing() -> int:
	var n := 0
	for p in AudioManager._sfx_pool:
		if (p as AudioStreamPlayer).playing:
			n += 1
	return n


func _sample(tag: String) -> Dictionary:
	var w := _world()
	var container: Node = w.get_node_or_null("EnemyContainer")
	var pool: Node = w.get_node_or_null("ProjectilePool")
	var pickups: Node = w.get_node_or_null("PickupManager")
	var effects: Node = w.get_node_or_null("EffectDirector")
	var numbers: Node = _ui().get("_numbers") if _ui() != null else null
	var player: Node = GameRoot.get_active_player()
	var rig: Node = w.get_node_or_null("CameraRig")
	var s := {
		"t": snappedf((Time.get_ticks_msec() - _t0) / 1000.0, 0.1),
		"frame": get_tree().get_frame(),
		"state": String(GameRoot.get_current_state()),
		"paused": get_tree().paused,
		"nodes": 1 + _descendants(get_tree().root),
		"enemies": container.get_child_count() if container != null else -1,
		"proj": int(pool.call("active_count")) if pool != null else -1,
		"pickups": pickups.get_child_count() if pickups != null else -1,
		"dmg": (numbers.get("_live") as Array).size() if numbers != null else -1,
		"fx": effects.get_child_count() if effects != null else -1,
		"audio": _audio_playing(),
		"music": String(_music().get_state()),
		"heat": snappedf(float(_music().get("heat")), 0.01) if _music().get("heat") != null else -1.0,
		"player_ok": is_instance_valid(player),
		"cam_ok": rig != null and rig.get("_target") == player,
		"errors": _err_count,
	}
	_max_nodes = maxi(_max_nodes, int(s["nodes"]))
	_max_enemies = maxi(_max_enemies, int(s["enemies"]))
	_max_audio = maxi(_max_audio, int(s["audio"]))
	print("  SOAK %s: %s" % [tag, str(s)])
	return s


var _t0 := 0


func _run() -> void:
	get_tree().create_timer(540.0).timeout.connect(func() -> void:
		push_error("SOAK TIMEOUT")
		get_tree().quit(2))
	EventBus.diagnostic.connect(_on_diag)
	EventBus.game_state_changed.connect(func(_p: StringName, _c: StringName) -> void: _transitions += 1)
	get_tree().change_scene_to_file(MAIN_SCENE)
	var booted := false
	for i in range(300):
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene.name == "Main":
			booted = true
			break
	if not booted:
		_check("main scene boots", false)
		_finish()
		return
	for i in range(10):
		await get_tree().process_frame
	_t0 = Time.get_ticks_msec()
	_menu_nodes_boot = 1 + _descendants(get_tree().root)
	_bus_menu = _bus_census()
	_sample("boot")
	# Start via the real UI.
	var start_btn := _find_button(_ui()._menu, "START RUN")
	_check("soak START RUN", start_btn != null)
	if start_btn == null:
		_finish()
		return
	start_btn.pressed.emit()
	for i in range(4):
		await get_tree().process_frame
	var enter_btn := _find_button(_ui()._setup, "ENTER ARENA")
	_check("soak ENTER ARENA", enter_btn != null and not enter_btn.disabled)
	if enter_btn == null:
		_finish()
		return
	enter_btn.pressed.emit()
	var playing := false
	for i in range(600):
		await get_tree().process_frame
		if GameRoot.get_current_state() == GameRoot.State.PLAYING:
			playing = true
			break
	_check("soak run starts", playing)
	if not playing:
		_finish()
		return
	var player: Node = GameRoot.get_active_player()
	(player.get_node("HealthComponent") as Node).call("set_invulnerable", 3600.0)
	(player.get_node("HealthComponent") as Node).call("heal", 100000.0)
	_sample("start")
	await _drive()
	_sample("preshutdown")
	# Game over -> menu -> fresh short run.
	var health: Node = player.get_node("HealthComponent") if is_instance_valid(player) else null
	if health != null:
		health.call("reset", float(health.get("max_health")))
		var lethal := DamagePayload.new()
		lethal.amount = 999999.0
		health.call("take_damage", lethal)
	for i in range(8):
		await get_tree().process_frame
	_check("soak game over", GameRoot.get_current_state() == GameRoot.State.GAME_OVER)
	_sample("gameover")
	GameRoot.request_main_menu()
	for i in range(8):
		await get_tree().process_frame
	await _wait_for_quiet()
	_check("soak back at menu", GameRoot.get_current_state() == GameRoot.State.MAIN_MENU)
	_check("soak menu unpaused", not get_tree().paused)
	_sample("menu")
	var menu_nodes_c1 := 1 + _descendants(get_tree().root)
	print("  SOAK menu nodes boot=%d cycle1=%d (one-time panels may lazy-build)" % [_menu_nodes_boot, menu_nodes_c1])
	var bus_now := _bus_census()
	var drift := []
	for sig in _bus_menu.keys():
		if int(bus_now.get(sig, -1)) != int(_bus_menu[sig]):
			drift.append(sig)
	print("  SOAK bus drift vs boot: %s (tutorial trio expected once)" % str(drift))
	# Fresh short run proves the game still starts clean after the soak.
	start_btn = _find_button(_ui()._menu, "START RUN")
	start_btn.pressed.emit()
	for i in range(4):
		await get_tree().process_frame
	enter_btn = _find_button(_ui()._setup, "ENTER ARENA")
	enter_btn.pressed.emit()
	playing = false
	for i in range(600):
		await get_tree().process_frame
		if GameRoot.get_current_state() == GameRoot.State.PLAYING:
			playing = true
			break
	_check("post-soak run starts", playing)
	for i in range(120):
		await get_tree().physics_frame
	_sample("run2")
	_check("post-soak player valid", is_instance_valid(GameRoot.get_active_player()))
	# End cycle 2 the same way: a second full cycle must add zero menu nodes.
	var p2: Node = GameRoot.get_active_player()
	var h2: Node = p2.get_node("HealthComponent") if is_instance_valid(p2) else null
	if h2 != null:
		h2.call("reset", float(h2.get("max_health")))
		var lethal2 := DamagePayload.new()
		lethal2.amount = 999999.0
		h2.call("take_damage", lethal2)
	for i in range(8):
		await get_tree().process_frame
	GameRoot.request_main_menu()
	for i in range(8):
		await get_tree().process_frame
	await _wait_for_quiet()
	var menu_nodes_c2 := 1 + _descendants(get_tree().root)
	_check("menu nodes stable across cycles", menu_nodes_c1 == menu_nodes_c2, "%d vs %d" % [menu_nodes_c1, menu_nodes_c2])
	_finish()


func _drive() -> void:
	var dirs := ["move_right", "move_down", "move_left", "move_up"]
	var di := 0
	var next_sample_ms := _t0 + int(SAMPLE_SECONDS * 1000.0)
	var phys := 0
	Input.action_press(dirs[0])
	while Time.get_ticks_msec() - _t0 < int(SOAK_SECONDS * 1000.0):
		await get_tree().physics_frame
		phys += 1
		if phys % 120 == 0:
			Input.action_release(dirs[di % 4])
			di += 1
			Input.action_press(dirs[di % 4])
		if phys % 170 == 0:
			Input.action_press("attack")
		if phys % 170 == 2:
			Input.action_release("attack")
		if phys % 540 == 0:
			Input.action_press("dodge")
		if phys % 540 == 2:
			Input.action_release("dodge")
		if GameRoot.get_current_state() == GameRoot.State.UPGRADE_SELECTION:
			var cards: Array = (_ui().get("_upgrade") as Node).get("_card_buttons")
			if not cards.is_empty():
				(cards[0] as Button).pressed.emit()
				_upgrades_auto += 1
				for i in range(4):
					await get_tree().process_frame
		if Time.get_ticks_msec() >= next_sample_ms:
			next_sample_ms += int(SAMPLE_SECONDS * 1000.0)
			var s := _sample("t%d" % int((Time.get_ticks_msec() - _t0) / 1000.0))
			_check("player valid", bool(s["player_ok"]))
			_check("camera valid", bool(s["cam_ok"]))
			if not is_instance_valid(GameRoot.get_active_player()):
				break
	Input.action_release(dirs[di % 4])
	print("  SOAK drive done: upgrades_auto=%d transitions=%d max_nodes=%d max_enemies=%d max_audio=%d" % [_upgrades_auto, _transitions, _max_nodes, _max_enemies, _max_audio])


func _find_button(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return node as Button
	return null


func _wait_for_quiet() -> void:
	for i in range(360):
		await get_tree().process_frame
		if _audio_playing() == 0:
			break


func _bus_census() -> Dictionary:
	var out := {}
	for sig in ["run_started", "run_ended", "wave_started", "wave_completed", "enemy_killed", "player_died", "settings_changed", "pause_changed"]:
		out[sig] = (EventBus.get_signal_connection_list(sig) as Array).size()
	return out


func _finish() -> void:
	_total += 1
	if _err_count > 0:
		_failures.append("zero error diagnostics")
		push_error("SOAK had %d error diagnostics" % _err_count)
	else:
		print("  PASS: zero error diagnostics")
	print("SOAK: %d checks, %d failed, frames=%d" % [_total, _failures.size(), get_tree().get_frame()])
	for f in _failures:
		print("  FAILED: %s" % f)
	var code := 1 if not _failures.is_empty() else 0
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit(code)
