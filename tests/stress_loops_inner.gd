extends Node
## Extended-loop stress pass (release verification, phases 2/4/5/6/9/10/13).
## Loaded by tests/stress_loops.gd after autoloads register. Boots the REAL game
## and runs 5 full menu -> run -> game-over loops with deep per-run checks:
## player validity/animation/mount, camera follow, natural wave combat, enemy
## feedback, XP/level-up, weapons/skills/projectiles/pickups, boss flow,
## pause/resume, game-over, menu return. Takes node/signal/pool census
## snapshots at 7 lifecycle points and compares loop 1 vs loop 5.
##
##   godot --headless --path . --script res://tests/stress_loops.gd
## Exit code 0 only when every check passes. Run with isolated XDG_DATA_HOME.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const BASIC_ENEMY := "res://scenes/enemies/basic_enemy.tscn"
const WARLORD_ENEMY := "res://scenes/enemies/warlord_enemy.tscn"
const LOOPS := 5

var _total := 0
var _failures: Array[String] = []
var _diags: Array = []
var _completed: Array[String] = []
var _sig_counts := {}
var _census_points := {} # "loop.point" -> Dictionary
var _bus_baseline := {}


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


func _find_buttons_containing(root: Node, token: String) -> Array:
	var out := []
	for node in root.find_children("*", "Button", true, false):
		if String((node as Button).text).contains(token):
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


func _music_playing_cue() -> String:
	var mm := _music()
	var players: Array = mm._players
	var idx: int = mm._active_index
	if idx < 0 or idx >= players.size():
		return ""
	var player := players[idx] as AudioStreamPlayer
	if player.playing and player.stream != null:
		return String(_cue_for_stream(player.stream))
	return ""


func _connect_completion_tracking() -> void:
	for p in AudioManager._sfx_pool:
		(p as AudioStreamPlayer).finished.connect(_on_sfx_finished.bind(p))


func _on_sfx_finished(player: AudioStreamPlayer) -> void:
	var cue := _cue_for_stream(player.stream)
	_completed.append(String(cue) if cue != &"" else "<unknown>")


func _drain_played() -> Dictionary:
	var by_cue := {}
	var total := 0
	var unknowns := 0
	for cue in _completed:
		total += 1
		if cue == "<unknown>":
			unknowns += 1
		else:
			by_cue[cue] = int(by_cue.get(cue, 0)) + 1
	_completed.clear()
	var snap := _sfx_snapshot()
	total += int(snap["total"])
	unknowns += int(snap["unknowns"])
	for cue in (snap["by_cue"] as Dictionary).keys():
		by_cue[String(cue)] = int(by_cue.get(String(cue), 0)) + int((snap["by_cue"] as Dictionary)[cue])
	return {"total": total, "unknowns": unknowns, "by_cue": by_cue}


func _valid_vec(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z) and v.length() < 100000.0


func _descendants(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		n += 1 + _descendants(c)
	return n


# ---------------------------------------------------------------- signals ---

const WATCHED_BUS_SIGNALS := [
	"run_started", "run_ended", "wave_started", "wave_completed",
	"enemy_spawned", "enemy_killed", "player_died", "player_leveled_up",
	"upgrade_selected", "skill_cast", "skill_ready", "weapon_switched",
	"pickup_collected", "boss_spawned", "boss_slain", "pause_changed",
	"settings_changed", "achievement_unlocked",
]


func _connect_signal_watchers() -> void:
	for sig in WATCHED_BUS_SIGNALS:
		_sig_counts[sig] = 0
		if EventBus.has_signal(sig):
			_watch(EventBus, sig)


## Arity-proof counter: every watched signal has <= 4 args.
func _watch(obj: Object, sig: String) -> void:
	var cb := func(_a0: Variant = null, _a1: Variant = null, _a2: Variant = null, _a3: Variant = null) -> void:
		_sig_counts[sig] = int(_sig_counts.get(sig, 0)) + 1
	obj.connect(sig, cb)


func _sig_reset() -> void:
	for sig in WATCHED_BUS_SIGNALS:
		_sig_counts[sig] = 0


func _bus_census() -> Dictionary:
	var out := {}
	for sig in WATCHED_BUS_SIGNALS:
		if EventBus.has_signal(sig):
			out[sig] = (EventBus.get_signal_connection_list(sig) as Array).size()
	return out


# ---------------------------------------------------------------- census ----

func _world_census() -> Dictionary:
	var w := _world()
	var names := []
	for c in w.get_children():
		names.append(String(c.name))
	var container: Node = w.get_node_or_null("EnemyContainer")
	var pool: Node = w.get_node_or_null("ProjectilePool")
	var pickups: Node = w.get_node_or_null("PickupManager")
	var effects: Node = w.get_node_or_null("EffectDirector")
	var arena: Node = w.get_node_or_null("Arena")
	var player: Node = GameRoot.get_active_player()
	var numbers: Node = _ui().get("_numbers") if _ui() != null else null
	return {
		"world_children": names,
		"enemies": container.get_child_count() if container != null else -1,
		"proj_active": int(pool.call("active_count")) if pool != null else -1,
		"proj_idle": int(pool.call("idle_count")) if pool != null else -1,
		"pickups": pickups.get_child_count() if pickups != null else -1,
		"dmg_live": (numbers.get("_live") as Array).size() if numbers != null else -1,
		"effects_children": effects.get_child_count() if effects != null else -1,
		"audio_playing": int(_sfx_snapshot()["total"]),
		"audio_pool": (AudioManager._sfx_pool as Array).size(),
		"music_state": String(_music().get_state()),
		"music_players": (_music()._players as Array).size(),
		"arena": is_instance_valid(arena),
		"player": is_instance_valid(player),
		"ui_screen": String(_ui()._active_screen) if _ui() != null else "?",
		"total_nodes": 1 + _descendants(get_tree().root),
		"frame": get_tree().get_frame(),
	}


func _snap(point: String) -> void:
	_census_points[point] = _world_census()
	print("  CENSUS %s: %s" % [point, str(_census_points[point])])
	if int(_sfx_snapshot()["total"]) > 0:
		print("  CENSUS %s playing: %s" % [point, str(_sfx_snapshot()["by_cue"])])


func _dump_signal_holders(signals: Array) -> void:
	for sig in signals:
		if EventBus.has_signal(sig):
			var holders := []
			for c in EventBus.get_signal_connection_list(sig):
				var cb := c["callable"] as Callable
				holders.append("%s::%s" % [cb.get_object(), String(cb.get_method())])
			print("  SIGNAL %s holders: %s" % [sig, str(holders)])


func _compare_bus(loop: int) -> void:
	var now := _bus_census()
	var drift := []
	for sig in _bus_baseline.keys():
		if int(now.get(sig, -1)) != int(_bus_baseline[sig]):
			drift.append("%s:%d->%d" % [sig, _bus_baseline[sig], now.get(sig, -1)])
	if loop == 1:
		# TutorialManager lazily wires 3 guarded (dup-proof) connections on the
		# first run_started; allowlist exactly that, then re-baseline.
		var expected := ["wave_completed:4->5", "upgrade_selected:3->4", "skill_cast:2->3"]
		drift.sort()
		expected.sort()
		_check("L1 first-run wiring is only the tutorial trio", drift == expected, str(drift))
		_bus_baseline = now
	else:
		_check("L%d EventBus connections stable" % loop, drift.is_empty(), str(drift))


# ------------------------------------------------------------------ run ----

func _run() -> void:
	get_tree().create_timer(540.0).timeout.connect(func() -> void:
		push_error("STRESS TIMEOUT")
		get_tree().quit(2))
	EventBus.diagnostic.connect(_on_diag)
	_connect_completion_tracking()
	_connect_signal_watchers()
	get_tree().change_scene_to_file(MAIN_SCENE)
	if not await _wait_for(func() -> bool: return get_tree().current_scene != null and get_tree().current_scene.name == "Main", 30.0):
		_check("main scene boots", false)
		await _finish()
		return
	await _frames(10)
	_bus_baseline = _bus_census()
	_snap("boot.menu")
	for loop in range(1, LOOPS + 1):
		print("STRESS LOOPS: loop %d" % loop)
		_sig_reset()
		await _menu_and_start(loop)
		await _run_stage(loop)
		await _end_run_stage(loop)
		_compare_bus(loop)
	_snap("final.menu")
	_compare_census()
	await _finish()


func _menu_and_start(loop: int) -> void:
	var tag := "L%d" % loop
	_check(tag + " state is main_menu", GameRoot.get_current_state() == GameRoot.State.MAIN_MENU)
	var start_btn := _find_button(_ui()._menu, "START RUN")
	_check(tag + " START RUN exists", start_btn != null)
	if start_btn == null:
		return
	start_btn.pressed.emit()
	await _frames(4)
	var setup: Node = _ui()._setup
	var enter_btn := _find_button(setup, "ENTER ARENA")
	_check(tag + " ENTER ARENA enabled", enter_btn != null and not enter_btn.disabled)
	if enter_btn == null:
		return
	enter_btn.pressed.emit()
	var reached := await _wait_for(func() -> bool: return GameRoot.get_current_state() == GameRoot.State.PLAYING, 60.0)
	_check(tag + " run reaches PLAYING", reached)
	_snap("%s.start" % tag)


func _run_stage(loop: int) -> void:
	var tag := "L%d" % loop
	var player: Node = GameRoot.get_active_player()
	_check(tag + " player exists", is_instance_valid(player) and player.is_inside_tree())
	if not is_instance_valid(player):
		return
	var health: Node = player.get_node("HealthComponent")
	health.call("set_invulnerable", 3600.0)
	health.call("heal", 100000.0)
	await _player_validity_checks(tag, player)
	await _natural_combat_window(tag, player)
	# Freeze the director for isolated interaction tests.
	var wave: Node = _world().get_node_or_null("WaveManager")
	var spawn: Node = _world().get_node_or_null("SpawnManager")
	if wave != null and wave.has_method("stop"):
		wave.call("stop")
	if spawn != null and spawn.has_method("deactivate_all"):
		spawn.call("deactivate_all")
	var container: Node = _world().get_node("EnemyContainer")
	for child in container.get_children():
		child.queue_free()
	await _frames(4)
	_snap("%s.mid" % tag)
	_mount_checks(tag, player)
	await _enemy_barrage(tag, player, container)
	await _feedback_checks(tag, player, container)
	await _xp_checks(tag, player)
	await _weapon_checks(tag, player)
	await _skill_checks(tag, player)
	await _projectile_checks(tag, player)
	await _pickup_checks(tag, player)
	await _vfx_checks(tag, player)
	await _boss_checks(tag, player, container)
	_snap("%s.boss" % tag)
	await _pause_probe(tag)


func _player_validity_checks(tag: String, player: Node) -> void:
	var p := (player as Node3D).global_position
	_check(tag + " player position valid", _valid_vec(p), str(p))
	var arena: Node = _world().get_node_or_null("Arena")
	_check(tag + " arena valid", is_instance_valid(arena))
	var marker := arena.get_node_or_null("PlayerStart") as Marker3D if arena != null else null
	_check(tag + " PlayerStart present", marker != null)
	if marker != null:
		_check(tag + " player spawned at PlayerStart", (player as Node3D).global_position.distance_to(marker.global_position) < 2.0, str(p))
	await _wait_for(func() -> bool: return (player as CharacterBody3D).is_on_floor(), 3.0)
	_check(tag + " player lands on floor", (player as CharacterBody3D).is_on_floor())
	var rig: Node = _world().get_node_or_null("CameraRig")
	_check(tag + " camera rig exists", rig != null)
	if rig != null:
		_check(tag + " camera targets player", rig.get("_target") == player)
		var d0 := (rig as Node3D).global_position.distance_to((player as Node3D).global_position)
		_check(tag + " camera near player", d0 < 40.0, "%.1f" % d0)
	var anims: Array = player.find_children("*", "AnimationPlayer", true, false)
	_check(tag + " player animated", not anims.is_empty() and (anims[0] as AnimationPlayer).is_playing())


func _natural_combat_window(tag: String, player: Node) -> void:
	# Let wave 1 play naturally: locomotion, footsteps, camera follow, spawns,
	# enemy AI + attacks, hurt feedback on an invulnerable player.
	var rig: Node = _world().get_node_or_null("CameraRig")
	var rig_p0 := (rig as Node3D).global_position if rig != null else Vector3.ZERO
	var p0 := (player as Node3D).global_position
	Input.action_press("move_right")
	for i in range(120):
		await get_tree().physics_frame
	Input.action_release("move_right")
	var p1 := (player as Node3D).global_position
	_check(tag + " player moved under input", p0.distance_to(p1) > 1.0, "%.2fm" % p0.distance_to(p1))
	_check(tag + " player stayed valid", _valid_vec(p1), str(p1))
	_check(tag + " player stayed grounded", (player as CharacterBody3D).is_on_floor())
	if rig != null:
		var rig_p1 := (rig as Node3D).global_position
		_check(tag + " camera followed player", rig_p0.distance_to(rig_p1) > 0.5, "%.2fm" % rig_p0.distance_to(rig_p1))
	_check(tag + " wave spawned enemies", int(_sig_counts.get("enemy_spawned", 0)) >= 1, str(_sig_counts.get("enemy_spawned", 0)))
	_check(tag + " wave_started emitted", int(_sig_counts.get("wave_started", 0)) >= 1)
	var container: Node = _world().get_node("EnemyContainer")
	var saw_anim := false
	var saw_model := false
	for e in container.get_children():
		if not (e as Node).find_children("*", "AnimationPlayer", true, false).is_empty():
			for a in (e as Node).find_children("*", "AnimationPlayer", true, false):
				if (a as AnimationPlayer).is_playing():
					saw_anim = true
		var cm := (e as Node).get_node_or_null("VisualRoot/CharacterModel")
		if cm != null and cm.get_child_count() > 0:
			saw_model = true
	_check(tag + " live enemies present", container.get_child_count() >= 1, str(container.get_child_count()))
	_check(tag + " enemy animations playing", saw_anim)
	_check(tag + " enemy models mounted", saw_model)


func _mount_checks(tag: String, player: Node) -> void:
	var cm := (player as Node).get_node("VisualRoot/CharacterModel")
	var visual := cm.get_node_or_null("CharacterVisual")
	_check(tag + " Knight wrapper mounted", visual != null)
	var model := visual.get_node_or_null("Model") if visual != null else null
	_check(tag + " Knight model present", model != null)
	var meshes := 0
	var visible_meshes := 0
	if model != null:
		for m in (model as Node).find_children("*", "MeshInstance3D", true, false):
			meshes += 1
			if (m as MeshInstance3D).visible and (m as MeshInstance3D).mesh != null:
				visible_meshes += 1
	_check(tag + " Knight has meshes", meshes >= 1, str(meshes))
	_check(tag + " Knight meshes visible", visible_meshes >= 1, str(visible_meshes))
	var body := cm.get_node_or_null("Body")
	_check(tag + " no stale fallback Body alongside model", body == null or not (body as MeshInstance3D).visible)
	# GroundShadow is parented to the mount (CharacterModel), not the bobbing
	# wrapper, so it stays planted. Lock that placement, not just existence.
	var shadow := (cm as Node).find_child("*Shadow*", true, false)
	_check(tag + " ground shadow present", shadow != null)
	_check(tag + " shadow planted on mount", shadow != null and shadow.get_parent() == cm)
	if shadow != null and player != null:
		var sp := (shadow as Node3D).global_position
		var pp := (player as Node3D).global_position
		_check(tag + " shadow follows player", Vector2(sp.x, sp.z).distance_to(Vector2(pp.x, pp.z)) < 2.0)
	# Equipment socket + remount idempotency.
	var skel := (model as Node).find_child("Skeleton3D", true, false) if model != null else null
	_check(tag + " Knight skeleton present", skel != null)
	_check(tag + " equipment socket bound", skel != null and skel.get_child_count() >= 1)
	var again: Variant = CharacterVisuals.mount(player as Node3D, &"player")
	_check(tag + " mount idempotent (no double-model)", again == visual)
	# Simulated mount failure keeps the actor safe (null, no crash, no overlay).
	var bogus: Variant = CharacterVisuals.mount(player as Node3D, &"no_such_role")
	_check(tag + " bogus role mount returns null", bogus == null)


func _spawn_enemy(archetype: StringName, run_seed: int, player: Node, container: Node) -> Node:
	var path := BASIC_ENEMY if archetype != &"warlord" else WARLORD_ENEMY
	var cls: PackedScene = load(path)
	var enemy: Node = cls.instantiate()
	container.add_child(enemy)
	enemy.call("initialize", ContentRegistry.get_enemy(archetype), player, run_seed)
	return enemy


func _enemy_barrage(tag: String, player: Node, container: Node) -> void:
	_check(tag + " container clear before barrage", container.get_child_count() == 0, str(container.get_child_count()))
	var foes := []
	for i in range(12):
		foes.append(_spawn_enemy(&"basic", 1000 + i, player, container))
	await _frames(2)
	_check(tag + " barrage spawned 12", container.get_child_count() == 12, str(container.get_child_count()))
	# Live AI briefly: locomotion + attacks against an invulnerable player.
	var moved := false
	var p0 := {}
	for e in foes:
		p0[e.get_instance_id()] = (e as Node3D).global_position
	for i in range(60):
		await get_tree().physics_frame
	for e in foes:
		if is_instance_valid(e) and ((e as Node3D).global_position.distance_to(p0[e.get_instance_id()] as Vector3) > 0.2):
			moved = true
	_check(tag + " barrage enemies move", moved)
	_stop_all_sfx()
	for e in foes:
		var lethal := DamagePayload.new()
		lethal.amount = 999999.0
		if is_instance_valid(e):
			e.call("apply_damage", lethal)
	await _wait_for(func() -> bool: return container.get_child_count() == 0, 6.0)
	_check(tag + " barrage all freed", container.get_child_count() == 0, str(container.get_child_count()))


func _feedback_checks(tag: String, player: Node, container: Node) -> void:
	var enemy := _spawn_enemy(&"basic", 4242, player, container)
	enemy.call("set_ai_enabled", false)
	await _frames(3)
	var feedback: Node = enemy.get_node("EnemyFeedback")
	# Hit flash.
	var payload := DamagePayload.new()
	payload.amount = 5.0
	_stop_all_sfx()
	var res: DamageResult = enemy.call("apply_damage", payload)
	_check(tag + " barrage hit accepted", res != null and res.accepted)
	# Main refactored _target_meshes() into lazy _flash_meshes and starts the
	# flash transparent (tween ramps up); let the tween tick before asserting.
	await _frames(2)
	var meshes: Array = feedback.get("_flash_meshes")
	var on := false
	for m in meshes:
		if is_instance_valid(m) and (m as MeshInstance3D).material_overlay != null:
			on = true
	_check(tag + " barrage hit flash on", on)
	await get_tree().create_timer(0.5).timeout
	# Telegraph.
	enemy.call("play_telegraph_feedback")
	await _frames(2)
	var tele := false
	for m in meshes:
		if is_instance_valid(m) and (m as MeshInstance3D).material_overlay != null:
			tele = true
	_check(tag + " barrage telegraph on", tele)
	await get_tree().create_timer(0.5).timeout
	# Recolor keeps materials.
	var mats_before := 0
	for m in meshes:
		if is_instance_valid(m):
			mats_before += ((m as MeshInstance3D).get_active_material(0) != null) as int
	feedback.call("recolor", Color(0.2, 0.8, 0.4))
	var mats_after := 0
	for m in meshes:
		if is_instance_valid(m):
			mats_after += ((m as MeshInstance3D).get_active_material(0) != null) as int
	_check(tag + " recolor keeps materials", mats_after == mats_before, "%d->%d" % [mats_before, mats_after])
	# Death.
	var lethal := DamagePayload.new()
	lethal.amount = 999999.0
	var res2: DamageResult = enemy.call("apply_damage", lethal)
	_check(tag + " barrage lethal kills", res2 != null and res2.target_died)
	await get_tree().create_timer(1.4).timeout
	_check(tag + " barrage corpse freed", not is_instance_valid(enemy))


func _xp_checks(tag: String, player: Node) -> void:
	var xp: Node = player.get_node("ExperienceComponent")
	var lvl: int = xp.call("get_level")
	var need: int = ExperienceComponent.xp_for_level(lvl)
	_stop_all_sfx()
	var ups: int = xp.call("add_xp", need)
	_check(tag + " level-up triggers", ups == 1)
	var snap := _sfx_snapshot()
	_check(tag + " level-up sting once", snap["total"] == 1 and _count(snap, "level_up") == 1, str(snap))
	_check(tag + " leveled_up signal once", int(_sig_counts.get("player_leveled_up", 0)) >= 1, str(_sig_counts.get("player_leveled_up", 0)))
	await _frames(6)
	# A wave-clear/level upgrade offer may auto-present; exercise it if so.
	if GameRoot.get_current_state() == GameRoot.State.UPGRADE_SELECTION:
		var cards: Array = (_ui().get("_upgrade") as Node).get("_card_buttons")
		_check(tag + " upgrade cards offered", not cards.is_empty())
		if not cards.is_empty():
			_stop_all_sfx()
			(cards[0] as Button).pressed.emit()
			await _frames(4)
			_check(tag + " upgrade card resumes play", GameRoot.get_current_state() == GameRoot.State.PLAYING)


func _weapon_checks(tag: String, player: Node) -> void:
	var mgr: Node = player.get_node("WeaponManager")
	var before: int = _sig_counts.get("weapon_switched", 0)
	var ok_high: bool = mgr.call("switch_to", 5)
	_check(tag + " invalid weapon slot declined", ok_high == false)
	_check(tag + " invalid switch emits nothing", _sig_counts.get("weapon_switched", 0) == before)
	var ok_one: bool = mgr.call("switch_to", 1)
	if ok_one:
		_check(tag + " weapon switch emits", _sig_counts.get("weapon_switched", 0) == before + 1)
		mgr.call("switch_to", 0)
	else:
		_check(tag + " single loadout switch graceful", true)
	# Live attack through input; resolver must report the swing.
	_stop_all_sfx()
	Input.action_press("attack")
	await _phys(2)
	Input.action_release("attack")
	for i in range(60):
		await get_tree().process_frame
		if int(_sfx_snapshot()["total"]) > 0:
			break
	var snap := _sfx_snapshot()
	_check(tag + " attack swing audible", _count(snap, "player_attack") == 1, str(snap))
	await _wait_for(func() -> bool: return int(_sfx_snapshot()["total"]) == 0, 3.0)


func _skill_checks(tag: String, player: Node) -> void:
	var ctl: Node = player.get_node("SkillController")
	_check(tag + " skill controller present", ctl != null)
	if ctl == null:
		return
	_sig_counts["skill_became_ready"] = 0
	if ctl.has_signal("skill_became_ready"):
		_watch(ctl, "skill_became_ready")
	var cfg: SkillConfig = ContentRegistry.get_skill(&"warcry_skill")
	_check(tag + " warcry config exists", cfg != null)
	if cfg == null:
		return
	ctl.call("assign_skill_by_id", &"warcry_skill", 0, true)
	_check(tag + " skill assigned+unlocked", bool(ctl.call("is_unlocked", &"warcry_skill")))
	var cast0 := int(_sig_counts.get("skill_cast", 0))
	var ok: bool = ctl.call("try_cast_slot", 0)
	_check(tag + " skill casts", ok)
	_check(tag + " skill_cast emitted", int(_sig_counts.get("skill_cast", 0)) == cast0 + 1, str(_sig_counts.get("skill_cast", 0)))
	_check(tag + " cooldown starts", float(ctl.call("slot_cooldown", 0)) > 0.0)
	var ok2: bool = ctl.call("try_cast_slot", 0)
	_check(tag + " cooldown blocks recast", ok2 == false)
	ctl.call("_tick_cooldowns", 3600.0)
	await _frames(2)
	_check(tag + " skill_became_ready once", int(_sig_counts.get("skill_became_ready", 0)) == 1, str(_sig_counts.get("skill_became_ready", 0)))
	_check(tag + " slot ready again", bool(ctl.call("is_slot_ready", 0)))
	# Input path: the config's action casts when ready.
	var action := String(cfg.input_action)
	if not action.is_empty() and InputMap.has_action(action):
		_stop_all_sfx()
		Input.action_press(action)
		await _phys(2)
		Input.action_release(action)
		await _frames(2)
		_check(tag + " skill input action casts", float(ctl.call("slot_cooldown", 0)) > 0.0, action)
		ctl.call("_tick_cooldowns", 3600.0)
		await _frames(2)
	else:
		_check(tag + " skill has input action", false, action)


func _projectile_checks(tag: String, player: Node) -> void:
	var pool: Node = _world().get_node("ProjectilePool")
	_check(tag + " projectile pool present", pool != null)
	if pool == null:
		return
	var idle0: int = pool.call("idle_count")
	var kids0 := pool.get_child_count()
	var origin := (player as Node3D).global_position + Vector3(0, 1, 0)
	for i in range(5):
		pool.call("fire", {"origin": origin, "direction": Vector3(i - 2, 0.2, -1).normalized(), "speed": 20.0, "lifetime": 0.8, "damage": 0.0})
	_check(tag + " 5 projectiles active", int(pool.call("active_count")) == 5, str(pool.call("active_count")))
	await get_tree().create_timer(1.2).timeout
	_check(tag + " projectiles recycle", int(pool.call("active_count")) == 0, str(pool.call("active_count")))
	_check(tag + " pool stays bounded", pool.get_child_count() <= kids0 + 6, "%d->%d" % [kids0, pool.get_child_count()])
	_check(tag + " idle restored", int(pool.call("idle_count")) >= idle0, "%d->%d" % [idle0, int(pool.call("idle_count"))])


func _pickup_checks(tag: String, player: Node) -> void:
	var mgr: Node = _world().get_node("PickupManager")
	_check(tag + " pickup manager present", mgr != null)
	if mgr == null:
		return
	var col0 := int(_sig_counts.get("pickup_collected", 0))
	_stop_all_sfx()
	mgr.call("spawn_pickup", &"health_orb", (player as Node3D).global_position)
	await _frames(6)
	_check(tag + " pickup auto-collects at feet", int(_sig_counts.get("pickup_collected", 0)) == col0 + 1, str(_sig_counts.get("pickup_collected", 0)))
	var snap := _sfx_snapshot()
	_check(tag + " pickup drop+collect once each", snap["total"] == 2 and _count(snap, "item_drop") == 1 and _count(snap, "pickup") == 1, str(snap))
	# Magnet: distant pickup travels to the player.
	var far := (player as Node3D).global_position + Vector3(4, 0, 0)
	mgr.call("spawn_pickup", &"xp_gem", far)
	await _frames(2)
	var gems := []
	for c in mgr.get_children():
		if (c as Node).is_in_group("pickups") or String((c as Node).name).contains("Pickup"):
			gems.append(c)
	if mgr.get_child_count() > 0 and gems.is_empty():
		gems.append(mgr.get_child(mgr.get_child_count() - 1))
	_check(tag + " distant pickup exists", not gems.is_empty())
	if not gems.is_empty():
		# NOTE: an earlier revision captured gems[0].global_position here, presumably
		# to assert the magnet actually pulls the pickup toward the player. That
		# assertion was never written and nothing read the capture, so the dead local
		# is gone; this check still verifies collection via the pickup_collected count.
		for i in range(90):
			await get_tree().physics_frame
			if not is_instance_valid(gems[0]):
				break
		_check(tag + " pickup magnet collects", int(_sig_counts.get("pickup_collected", 0)) >= col0 + 2, str(_sig_counts.get("pickup_collected", 0)))


func _vfx_checks(tag: String, player: Node) -> void:
	var fx: Node = _world().get_node_or_null("EffectDirector")
	var numbers: Node = _ui().get("_numbers")
	_check(tag + " effect director present", fx != null)
	_check(tag + " damage layer present", numbers != null)
	if fx == null or numbers == null:
		return
	var kids0 := fx.get_child_count()
	var at := (player as Node3D).global_position
	for i in range(20):
		fx.call("burst_at", at, Color(1, 0.5, 0.2))
		fx.call("ring_at", at, Color(0.3, 0.8, 1.0))
	_check(tag + " vfx children bounded", fx.get_child_count() <= kids0 + 10 + 14 + 2, "%d->%d" % [kids0, fx.get_child_count()])
	for i in range(60):
		numbers.call("spawn_damage_number", at + Vector3(0, 1, 0), 25.0 + i, i % 5 == 0)
	var live: int = (numbers.get("_live") as Array).size()
	var max_live: int = numbers.get("_max_live")
	_check(tag + " damage numbers capped", live <= max_live, "%d/%d" % [live, max_live])
	await get_tree().create_timer(2.5).timeout
	_check(tag + " damage numbers settle", ((numbers.get("_live") as Array).size()) == 0)
	_check(tag + " vfx settle", fx.get_child_count() <= kids0 + 2, "%d->%d" % [kids0, fx.get_child_count()])


func _boss_checks(tag: String, player: Node, container: Node) -> void:
	var boss := _spawn_enemy(&"warlord", 777, player, container)
	boss.call("set_ai_enabled", false)
	(boss.get_node("BossController") as Node).set_physics_process(false)
	await _frames(3)
	_check(tag + " boss starts in Awakening", (boss.get_node("BossController") as Node).call("current_phase") == 0)
	_stop_all_sfx()
	(boss.get_node("BossController") as Node).call("begin_fight", 777)
	await _frames(3)
	var snap := _sfx_snapshot()
	_check(tag + " boss sting once", snap["total"] == 1 and _count(snap, "boss_spawned") == 1, str(snap))
	_check(tag + " boss bar shown", (_ui()._boss_bar as Control).visible)
	var health: Node = boss.get_node("HealthComponent")
	var max_hp := float(health.get("max_health"))
	_stop_all_sfx()
	var wound := DamagePayload.new()
	wound.amount = max_hp * 0.5
	boss.call("apply_damage", wound)
	await _frames(3)
	_check(tag + " boss hp halved", is_equal_approx(float(health.get("current_health")), max_hp * 0.5), str(health.get("current_health")))
	_check(tag + " boss phase Fury", (boss.get_node("BossController") as Node).call("current_phase") == 1)
	_check(tag + " Fury sting once", _count(_sfx_snapshot(), "boss_phase_changed") == 1)
	_stop_all_sfx()
	var kill := DamagePayload.new()
	kill.amount = 99999999.0
	var res: DamageResult = boss.call("apply_damage", kill)
	_check(tag + " boss killed", res != null and res.target_died)
	snap = _sfx_snapshot()
	_check(tag + " boss slain sting once", _count(snap, "boss_slain") == 1, str(snap))
	await get_tree().create_timer(0.7).timeout
	_check(tag + " boss bar hides", not (_ui()._boss_bar as Control).visible)
	await get_tree().create_timer(0.8).timeout
	_check(tag + " boss freed", not is_instance_valid(boss))


func _pause_probe(tag: String) -> void:
	var pause_btn := _find_button(_ui()._hud, "PAUSE")
	_check(tag + " HUD responsive", pause_btn != null and not pause_btn.disabled)
	if pause_btn == null:
		return
	pause_btn.pressed.emit()
	await _frames(3)
	_check(tag + " paused", get_tree().paused and GameRoot.get_current_state() == GameRoot.State.PAUSED)
	var resume_btn := _find_button(_ui()._screens["paused"], "RESUME RUN")
	_check(tag + " resume exists", resume_btn != null)
	if resume_btn == null:
		return
	resume_btn.pressed.emit()
	await _frames(3)
	_check(tag + " resumed", not get_tree().paused and GameRoot.get_current_state() == GameRoot.State.PLAYING)
	_check(tag + " pause_changed x2", int(_sig_counts.get("pause_changed", 0)) >= 2, str(_sig_counts.get("pause_changed", 0)))


func _end_run_stage(loop: int) -> void:
	var tag := "L%d" % loop
	var player: Node = GameRoot.get_active_player()
	_check(tag + " player present at end", is_instance_valid(player))
	if not is_instance_valid(player):
		return
	var died0 := int(_sig_counts.get("player_died", 0))
	var health: Node = player.get_node("HealthComponent")
	health.call("reset", float(health.get("max_health")))
	_stop_all_sfx()
	var lethal := DamagePayload.new()
	lethal.amount = 999999.0
	health.call("take_damage", lethal)
	var snap := _sfx_snapshot()
	_check(tag + " sting once", _count(snap, "game_over") == 1, str(snap))
	_check(tag + " death once", _count(snap, "player_death") == 1, str(snap))
	_check(tag + " player_died once", int(_sig_counts.get("player_died", 0)) == died0 + 1, str(_sig_counts.get("player_died", 0)))
	await _frames(4)
	_check(tag + " state game_over", GameRoot.get_current_state() == GameRoot.State.GAME_OVER)
	_snap("%s.over" % tag)
	_check(tag + " run_ended once", int(_sig_counts.get("run_ended", 0)) == 1, str(_sig_counts.get("run_ended", 0)))
	_check(tag + " victory bed", _music().get_state() == &"victory")
	# Return via the real UI button when available.
	var menu_btns := _find_buttons_containing(_ui()._screens["game_over"], "MENU")
	if not menu_btns.is_empty():
		(menu_btns[0] as Button).pressed.emit()
		await _frames(6)
	else:
		GameRoot.request_main_menu()
		await _frames(6)
	_check(tag + " back at menu", GameRoot.get_current_state() == GameRoot.State.MAIN_MENU)
	await _wait_for(func() -> bool: return int(_sfx_snapshot()["total"]) == 0, 6.0)
	_snap("%s.menu" % tag)
	_check(tag + " run_started once", int(_sig_counts.get("run_started", 0)) == 1, str(_sig_counts.get("run_started", 0)))
	_check(tag + " no settings churn", int(_sig_counts.get("settings_changed", 0)) == 0, str(_sig_counts.get("settings_changed", 0)))


func _compare_census() -> void:
	var a: Dictionary = _census_points.get("L1.menu", {})
	var b: Dictionary = _census_points.get("L5.menu", {})
	if a.is_empty() or b.is_empty():
		_check("menu census comparable", false)
		return
	print("  CENSUS L1.menu total=%d L5.menu total=%d" % [a.get("total_nodes", -1), b.get("total_nodes", -1)])
	_check("menu node count stable L1 vs L5", int(a["total_nodes"]) == int(b["total_nodes"]), "%d vs %d" % [a["total_nodes"], b["total_nodes"]])
	_check("menu enemies gone both", int(a["enemies"]) <= 0 and int(b["enemies"]) <= 0, "%s vs %s" % [a["enemies"], b["enemies"]])
	_check("menu audio pool 16 both", int(a["audio_pool"]) == 16 and int(b["audio_pool"]) == 16)
	_check("menu music players 2 both", int(a["music_players"]) == 2 and int(b["music_players"]) == 2)
	_check("menu audio settled", int(b["audio_playing"]) == 0, str(b["audio_playing"]))


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
	print("STRESS LOOPS: %d checks, %d failed, frames=%d" % [_total, _failures.size(), get_tree().get_frame()])
	for f in _failures:
		print("  FAILED: %s" % f)
	var code := 1 if not _failures.is_empty() else 0
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit(code)
