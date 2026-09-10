extends Node
## Audio & feedback end-to-end verification (no new gameplay).
## Loaded by tests/verify_flow.gd after autoloads register. Boots the REAL game
## (scenes/main/main.tscn) headless and drives the full player flow twice:
##  menu + menu music + single UI ticks, run start, player spawn + animation,
##  enemy hit/telegraph/death feedback, level-up, boss bar, pause/resume,
##  background/foreground mute, run end + single game-over sting, restart.
## Sound counts are exact: the SFX pool is snapshotted per interaction and each
## playing voice is reverse-mapped to its registered cue.
##
##   godot --headless --path . --script res://tests/verify_flow.gd
## Returns exit code 0 only when every check passes. Run with an isolated
## XDG_DATA_HOME so the local save is untouched.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const BASIC_ENEMY := "res://scenes/enemies/basic_enemy.tscn"
const WARLORD_ENEMY := "res://scenes/enemies/warlord_enemy.tscn"

var _total := 0
var _failures: Array[String] = []
var _diags: Array = [] # [{message, severity}]
var _completed: Array[String] = [] # cues whose SFX voices finished since last drain


func _ready() -> void:
	_run()


func _check(case_name: String, passed: bool, extra: String = "") -> void:
	_total += 1
	if passed:
		print("  PASS: %s" % case_name)
	else:
		_failures.append(case_name)
		push_error("VERIFY FAIL: %s %s" % [case_name, extra])


func _on_diag(message: String, severity: StringName) -> void:
	_diags.append({"message": message, "severity": String(severity)})


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _phys(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


## Wait until `cond` returns true (polled every few frames) or timeout.
func _wait_for(cond: Callable, timeout_sec: float) -> bool:
	var timer := get_tree().create_timer(timeout_sec)
	while not cond.call():
		if timer.time_left <= 0.0:
			return false
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
	return true


func _main() -> Node:
	return get_tree().current_scene


func _ui() -> Node:
	return get_tree().current_scene.get_node("UIRoot/UI")


func _music() -> Node:
	return get_tree().current_scene.get_node("MusicManager")


func _world() -> Node:
	return get_tree().current_scene.get_node("WorldRoot")


func _find_button(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return node as Button
	return null


## {total, unknowns, by_cue: {cue_name: count}} for currently playing SFX voices.
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
	# Read the ACTIVE bed: during crossfades the outgoing player is still
	# playing, so a first-playing scan would report the stale bed.
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


## Played multiset since the last drain: finished voices + still-playing voices.
## (A short tick can finish inside one synchronous call, e.g. ENTER ARENA's
## world build, so snapshots alone would miss it.)
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


func _only_allowed(snap: Dictionary, allowed: Array) -> bool:
	if int(snap["unknowns"]) != 0:
		return false
	for cue in (snap["by_cue"] as Dictionary).keys():
		if not String(cue) in allowed:
			return false
	return true


func _run() -> void:
	get_tree().create_timer(540.0).timeout.connect(func() -> void:
		push_error("VERIFY TIMEOUT: flow did not finish in 9 minutes")
		get_tree().quit(2))
	EventBus.diagnostic.connect(_on_diag)
	_connect_completion_tracking()
	get_tree().change_scene_to_file(MAIN_SCENE)
	if not await _wait_for(func() -> bool: return get_tree().current_scene != null and get_tree().current_scene.name == "Main", 30.0):
		_check("main scene boots", false)
		await _finish()
		return
	await _frames(10)
	for loop in [1, 2]:
		print("VERIFY FLOW: loop %d — menu" % loop)
		await _menu_checks(loop)
		print("VERIFY FLOW: loop %d — run" % loop)
		await _run_checks(loop)
		print("VERIFY FLOW: loop %d — end of run" % loop)
		await _end_run_checks(loop)
		if loop == 1:
			GameRoot.request_main_menu()
			await _frames(6)
			_check("L1 back to main menu", GameRoot.get_current_state() == GameRoot.State.MAIN_MENU)
			_check("L1 menu music restored", _music().get_state() == &"menu" and _music_playing_cue() == "music_menu")
		else:
			GameRoot.request_restart()
			await _frames(6)
			_check("L2 restart reaches playing", GameRoot.get_current_state() == GameRoot.State.PLAYING)
			var player: Node = GameRoot.get_active_player()
			_check("L2 restart player alive", is_instance_valid(player))
			_check("L2 restart music calm", _music().get_state() == &"calm")
			_check("L2 restart heat reset", is_zero_approx(_music().get_heat()))
	await _finish()


func _menu_checks(loop: int) -> void:
	var tag := "L%d" % loop
	_check(tag + " state is main_menu", GameRoot.get_current_state() == GameRoot.State.MAIN_MENU)
	_check(tag + " menu screen shown", _ui()._active_screen == &"main_menu" and (_ui()._menu as Control).visible)
	_check(tag + " music state menu", _music().get_state() == &"menu")
	_check(tag + " menu bed is music_menu cue", _music_playing_cue() == "music_menu")
	var stream: AudioStream = AudioManager.get_cue_stream(&"music_menu")
	_check(tag + " menu music is recorded ogg", stream is AudioStreamOggVorbis)
	if stream is AudioStreamOggVorbis:
		_check(tag + " menu music loops", (stream as AudioStreamOggVorbis).loop)
		_check(tag + " menu music is arena_menu track", stream.resource_path.get_file() == "arena_menu.ogg")
	var buses: Array[String] = []
	for i in range(AudioServer.get_bus_count()):
		buses.append(AudioServer.get_bus_name(i))
	_check(tag + " mixer has Music bus", "Music" in buses)
	_check(tag + " mixer has SFX bus", "SFX" in buses)
	_check(tag + " mixer not muted at boot", not AudioServer.is_bus_mute(0))
	# START RUN button: exactly one confirm tick + navigation.
	var start_btn := _find_button(_ui()._menu, "START RUN")
	_check(tag + " START RUN button exists", start_btn != null)
	if start_btn == null:
		return
	_stop_all_sfx()
	start_btn.pressed.emit()
	var snap := _sfx_snapshot()
	_check(tag + " START RUN plays exactly one sound", snap["total"] == 1, str(snap))
	_check(tag + " START RUN tick is ui_confirm", _count(snap, "ui_confirm") == 1, str(snap))
	await _frames(4)
	_check(tag + " START RUN navigates to setup", _ui()._active_screen == &"run_setup")
	# ENTER ARENA button: exactly one confirm tick + run starts. Split in two:
	# the synchronous world build finishes + recycles the short tick voice
	# before any snapshot, so acoustics are measured with _launch detached,
	# then the launch fanfare is measured with it reattached.
	var enter_btn := _find_button(_ui()._setup, "ENTER ARENA")
	_check(tag + " ENTER ARENA button exists", enter_btn != null and not enter_btn.disabled)
	if enter_btn == null:
		return
	var launch_callable := Callable()
	for c in enter_btn.pressed.get_connections():
		var cb := c["callable"] as Callable
		if cb.is_valid() and String(cb.get_method()) == "_launch":
			launch_callable = cb
			enter_btn.pressed.disconnect(cb)
	_check(tag + " ENTER ARENA launch detachable", launch_callable.is_valid())
	_stop_all_sfx()
	enter_btn.pressed.emit()
	snap = _sfx_snapshot()
	_check(tag + " ENTER ARENA ticks exactly once", snap["total"] == 1, str(snap))
	_check(tag + " ENTER ARENA tick is ui_confirm", _count(snap, "ui_confirm") == 1, str(snap))
	enter_btn.pressed.connect(launch_callable)
	_stop_all_sfx()
	_drain_played()
	enter_btn.pressed.emit()
	var reached := await _wait_for(func() -> bool: return GameRoot.get_current_state() == GameRoot.State.PLAYING, 60.0)
	_check(tag + " run reaches PLAYING", reached)
	await _frames(3)
	var played := _drain_played()
	_check(tag + " launch plays wave fanfare", _count(played, "wave_started") == 1, str(played))
	_check(tag + " launch spawns opening wave", _count(played, "enemy_spawn") >= 1, str(played))
	_check(tag + " launch sounds all expected", _only_allowed(played, ["ui_confirm", "wave_started", "enemy_spawn"]), str(played))
	_check(tag + " hud visible in run", (_ui()._hud as Control).visible)


func _run_checks(loop: int) -> void:
	var tag := "L%d" % loop
	# Freeze the wave director + clear wave-1 spawns so every sound below is
	# attributable to the interaction under test.
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
	var player: Node = GameRoot.get_active_player()
	_check(tag + " player exists in tree", is_instance_valid(player) and player.is_inside_tree())
	if not is_instance_valid(player):
		return
	var health: Node = player.get_node("HealthComponent")
	health.call("set_invulnerable", 3600.0)
	health.call("heal", 100000.0)
	_ui()._banner.clear_pending()
	_check(tag + " run music is calm bed", _music().get_state() == &"calm" and _music_playing_cue() == String(_music()._arena_cue(&"music_calm")), _music_playing_cue())
	await _player_animation_checks(tag, player)
	await _enemy_feedback_checks(tag, player, container)
	await _level_up_checks(tag, player)
	await _boss_checks(tag, player, container)
	await _pause_checks(tag)
	await _background_checks(tag)


func _player_animation_checks(tag: String, player: Node) -> void:
	var anims: Array = player.find_children("*", "AnimationPlayer", true, false)
	_check(tag + " player rig has AnimationPlayer (import ok)", not anims.is_empty())
	if anims.is_empty():
		return
	var anim := anims[0] as AnimationPlayer
	_check(tag + " player animation playing", anim.is_playing())
	await _phys(4)
	_check(tag + " player idles", anim.current_animation == "Idle", anim.current_animation)
	# Walk through the real input path.
	_stop_all_sfx()
	Input.action_press("move_right")
	var saw_walk := false
	var steps := 0
	for i in range(48):
		await get_tree().physics_frame
		if anim.current_animation == "Walking_A" or anim.current_animation == "Running_A":
			saw_walk = true
		steps = maxi(steps, _count(_sfx_snapshot(), "player_step"))
	Input.action_release("move_right")
	_check(tag + " walk clip plays on input", saw_walk, anim.current_animation)
	_check(tag + " footsteps sound while walking", steps >= 1)
	await _wait_for(func() -> bool: return anim.current_animation == "Idle", 3.0)
	_check(tag + " returns to idle", anim.current_animation == "Idle", anim.current_animation)
	# Attack through the real input path.
	_stop_all_sfx()
	Input.action_press("attack")
	await _phys(2)
	Input.action_release("attack")
	var attack_clips: Array = (player.get_node("PlayerAnimation") as Node).get("attack_clips")
	var saw_attack := false
	for i in range(90):
		await get_tree().process_frame
		if anim.current_animation in attack_clips:
			saw_attack = true
			break
	var snap := _sfx_snapshot()
	_check(tag + " attack clip plays", saw_attack, anim.current_animation)
	_check(tag + " swing sound exactly once", snap["total"] == 1 and _count(snap, "player_attack") == 1, str(snap))
	await _wait_for(func() -> bool: return anim.current_animation == "Idle", 5.0)
	# Dodge through the real input path.
	_stop_all_sfx()
	Input.action_press("dodge")
	await _phys(2)
	Input.action_release("dodge")
	var saw_dodge := false
	for i in range(60):
		await get_tree().process_frame
		if String(anim.current_animation).begins_with("Dodge"):
			saw_dodge = true
			break
	snap = _sfx_snapshot()
	_check(tag + " dodge clip plays", saw_dodge, anim.current_animation)
	_check(tag + " dodge sound exactly once", snap["total"] == 1 and _count(snap, "player_dodge") == 1, str(snap))
	await _wait_for(func() -> bool: return anim.current_animation == "Idle", 5.0)


func _enemy_feedback_checks(tag: String, player: Node, container: Node) -> void:
	var cls: PackedScene = load(BASIC_ENEMY)
	var enemy: Node = cls.instantiate()
	container.add_child(enemy)
	var cfg: EnemyConfig = ContentRegistry.get_enemy(&"basic")
	enemy.call("initialize", cfg, player, 4242)
	enemy.call("set_ai_enabled", false)
	await _frames(3)
	_check(tag + " test enemy initialized", is_instance_valid(enemy))
	var feedback: Node = enemy.get_node("EnemyFeedback")
	var visual: Node3D = enemy.get_node("VisualRoot")
	var base_scale: Vector3 = visual.scale
	_check(tag + " enemy visual scale applied", base_scale.x > 0.0)
	# Non-lethal hit: one sound, overlay flash on, then off, scale preserved.
	_stop_all_sfx()
	var payload := DamagePayload.new()
	payload.amount = 5.0
	var res: DamageResult = enemy.call("apply_damage", payload)
	_check(tag + " hit accepted", res != null and res.accepted)
	var snap := _sfx_snapshot()
	_check(tag + " hit sound exactly once", snap["total"] == 1 and _count(snap, "enemy_hit") == 1, str(snap))
	# Main refactored _target_meshes() into lazy _flash_meshes (populated by the
	# apply_damage above via play_damaged); verify the real collected set. The
	# merged flash starts transparent and ramps via tween, so tick first: the
	# overlay-on assertion must observe the mounted flash, not pre-ramp state.
	await _frames(2)
	var meshes: Array = feedback.get("_flash_meshes")
	_check(tag + " flash targets exist", not meshes.is_empty())
	var overlay_set := true
	for m in meshes:
		if (m as MeshInstance3D).material_overlay != feedback.get("_flash_material"):
			overlay_set = false
	_check(tag + " hit flash overlay on", overlay_set)
	await get_tree().create_timer(0.5).timeout
	var overlay_cleared := true
	for m in meshes:
		if is_instance_valid(m) and (m as MeshInstance3D).material_overlay != null:
			overlay_cleared = false
	_check(tag + " hit flash overlay clears", overlay_cleared)
	_check(tag + " hit preserves visual scale", visual.scale.is_equal_approx(base_scale), str(visual.scale))
	# Telegraph: flash on then off, no errors.
	enemy.call("play_telegraph_feedback")
	await _frames(2)
	var tele_set := false
	for m in meshes:
		if is_instance_valid(m) and (m as MeshInstance3D).material_overlay != null:
			tele_set = true
	_check(tag + " telegraph flash shows", tele_set)
	await get_tree().create_timer(0.5).timeout
	# Spawn cue through the enemy audio node.
	_stop_all_sfx()
	enemy.call("play_spawn_sound")
	snap = _sfx_snapshot()
	_check(tag + " spawn sound exactly once", snap["total"] == 1 and _count(snap, "enemy_spawn") == 1, str(snap))
	# Lethal hit: death sound once; drops/level-up allowed but accounted.
	_stop_all_sfx()
	var lvl_before: int = (player.get_node("ExperienceComponent") as Node).call("get_level")
	var lethal := DamagePayload.new()
	lethal.amount = 999999.0
	var res2: DamageResult = enemy.call("apply_damage", lethal)
	_check(tag + " lethal hit kills", res2 != null and res2.target_died)
	snap = _sfx_snapshot()
	var lvl_after: int = (player.get_node("ExperienceComponent") as Node).call("get_level")
	_check(tag + " death sound exactly once", _count(snap, "enemy_death") == 1, str(snap))
	_check(tag + " killing blow also lands hit sound", _count(snap, "enemy_hit") == 1, str(snap))
	_check(tag + " death sounds accounted", _only_allowed(snap, ["enemy_death", "enemy_hit", "item_drop", "level_up"]), str(snap))
	_check(tag + " no surprise level-up sting", _count(snap, "level_up") == (1 if lvl_after > lvl_before else 0), str(snap))
	await get_tree().create_timer(0.55).timeout
	_check(tag + " death shrink progresses", is_instance_valid(enemy) and (enemy.get_node("VisualRoot") as Node3D).scale.length() < base_scale.length())
	await get_tree().create_timer(0.8).timeout
	_check(tag + " dead enemy freed", not is_instance_valid(enemy))


func _level_up_checks(tag: String, player: Node) -> void:
	var xp: Node = player.get_node("ExperienceComponent")
	var lvl: int = xp.call("get_level")
	var need: int = ExperienceComponent.xp_for_level(lvl)
	var anims: Array = player.find_children("*", "AnimationPlayer", true, false)
	var anim: AnimationPlayer = anims[0]
	_stop_all_sfx()
	var ups: int = xp.call("add_xp", need)
	_check(tag + " level-up triggers", ups == 1)
	var snap := _sfx_snapshot()
	_check(tag + " level-up sting exactly once", snap["total"] == 1 and _count(snap, "level_up") == 1, str(snap))
	await _frames(6)
	var banner: Node = _ui()._banner
	var announced: bool = String(banner.get("text")).contains("Level")
	if not announced:
		for entry in banner.get("_queue"):
			if String(entry["text"]).contains("Level"):
				announced = true
	_check(tag + " level-up announced", announced)
	if anim.has_animation("Cheer"):
		_check(tag + " victory clip plays", anim.current_animation == "Cheer", anim.current_animation)


func _boss_checks(tag: String, player: Node, container: Node) -> void:
	var cls: PackedScene = load(WARLORD_ENEMY)
	var boss: Node = cls.instantiate()
	container.add_child(boss)
	var cfg: EnemyConfig = ContentRegistry.get_enemy(&"warlord")
	boss.call("initialize", cfg, player, 777)
	boss.call("set_ai_enabled", false)
	(boss.get_node("BossController") as Node).set_physics_process(false)
	await _frames(3)
	_stop_all_sfx()
	(boss.get_node("BossController") as Node).call("begin_fight", 777)
	await _frames(3)
	var snap := _sfx_snapshot()
	_check(tag + " boss spawn sting exactly once", snap["total"] == 1 and _count(snap, "boss_spawned") == 1, str(snap))
	_check(tag + " boss music state", _music().get_state() == &"boss")
	_check(tag + " boss bar shown", (_ui()._boss_bar as Control).visible)
	_check(tag + " boss bar named", not String((_ui()._boss_bar as Node).get("_name_label").text).is_empty())
	# Phase change at half health: Fury sting + label.
	_stop_all_sfx()
	var health: Node = boss.get_node("HealthComponent")
	var before_phase: int = (boss.get_node("BossController") as Node).call("current_phase")
	var wound := DamagePayload.new()
	wound.amount = float(health.get("max_health")) * 0.5
	boss.call("apply_damage", wound)
	await _frames(3)
	snap = _sfx_snapshot()
	var after_phase: int = (boss.get_node("BossController") as Node).call("current_phase")
	_check(tag + " boss phase advances", after_phase == before_phase + 1, "%d->%d" % [before_phase, after_phase])
	_check(tag + " phase sting exactly once", _count(snap, "boss_phase_changed") == 1, str(snap))
	_check(tag + " phase label Fury", String((_ui()._boss_bar as Node).get("_phase_label").text).contains("Fury"))
	# Boss kill: slain sting + death sound, bar hides, music back to battle.
	_stop_all_sfx()
	var kill := DamagePayload.new()
	kill.amount = 99999999.0
	var res: DamageResult = boss.call("apply_damage", kill)
	_check(tag + " boss lethal hit kills", res != null and res.target_died)
	snap = _sfx_snapshot()
	_check(tag + " boss slain sting exactly once", _count(snap, "boss_slain") == 1, str(snap))
	_check(tag + " boss death sound once", _count(snap, "enemy_death") == 1, str(snap))
	_check(tag + " boss killing blow lands hit sound", _count(snap, "enemy_hit") == 1, str(snap))
	# Overkill through the Enrage threshold trips the phase sting on the way down.
	_check(tag + " overkill trips enrage sting", _count(snap, "boss_phase_changed") == 1, str(snap))
	_check(tag + " boss death sounds accounted", _only_allowed(snap, ["boss_slain", "enemy_death", "enemy_hit", "boss_phase_changed", "item_drop", "level_up"]), str(snap))
	await get_tree().create_timer(0.7).timeout
	_check(tag + " boss bar hides after death", not (_ui()._boss_bar as Control).visible)
	_check(tag + " music back to battle", _music().get_state() == &"battle")
	await get_tree().create_timer(0.8).timeout
	_check(tag + " dead boss freed", not is_instance_valid(boss))


func _pause_checks(tag: String) -> void:
	var pause_btn := _find_button(_ui()._hud, "PAUSE")
	_check(tag + " HUD pause button exists", pause_btn != null)
	if pause_btn == null:
		return
	_stop_all_sfx()
	pause_btn.pressed.emit()
	var snap := _sfx_snapshot()
	_check(tag + " pause tick exactly once", snap["total"] == 1 and _count(snap, "ui_confirm") == 1, str(snap))
	await _frames(3)
	_check(tag + " tree paused", get_tree().paused)
	_check(tag + " state paused", GameRoot.get_current_state() == GameRoot.State.PAUSED)
	_check(tag + " pause screen shown", _ui()._active_screen == &"paused")
	var resume_btn := _find_button(_ui()._screens["paused"], "RESUME RUN")
	_check(tag + " resume button exists", resume_btn != null)
	if resume_btn == null:
		return
	_stop_all_sfx()
	resume_btn.pressed.emit()
	snap = _sfx_snapshot()
	_check(tag + " resume tick exactly once", snap["total"] == 1 and _count(snap, "ui_confirm") == 1, str(snap))
	await _frames(3)
	_check(tag + " tree resumed", not get_tree().paused)
	_check(tag + " state back to playing", GameRoot.get_current_state() == GameRoot.State.PLAYING)


func _background_checks(tag: String) -> void:
	_stop_all_sfx()
	AudioManager._notification(NOTIFICATION_APPLICATION_PAUSED)
	await _frames(2)
	_check(tag + " background mutes master", AudioServer.is_bus_mute(0))
	_check(tag + " background flag set", AudioManager.is_background_muted())
	AudioManager._notification(NOTIFICATION_APPLICATION_RESUMED)
	await _frames(2)
	_check(tag + " foreground restores mute", AudioServer.is_bus_mute(0) == SaveManager.get_settings().muted)
	_check(tag + " background flag cleared", not AudioManager.is_background_muted())
	_check(tag + " bg/fg transition silent", int(_sfx_snapshot()["total"]) == 0)


func _end_run_checks(loop: int) -> void:
	var tag := "L%d" % loop
	var player: Node = GameRoot.get_active_player()
	_check(tag + " player present at run end", is_instance_valid(player))
	if not is_instance_valid(player):
		return
	var health: Node = player.get_node("HealthComponent")
	health.call("reset", float(health.get("max_health")))
	_stop_all_sfx()
	var lethal := DamagePayload.new()
	lethal.amount = 999999.0
	health.call("take_damage", lethal)
	var snap := _sfx_snapshot()
	_check(tag + " game-over sting exactly once", _count(snap, "game_over") == 1, str(snap))
	_check(tag + " player death sound once", _count(snap, "player_death") == 1, str(snap))
	_check(tag + " run-end sounds exact", snap["total"] == 2, str(snap))
	await _frames(4)
	_check(tag + " state game_over", GameRoot.get_current_state() == GameRoot.State.GAME_OVER)
	_check(tag + " game-over screen shown", _ui()._active_screen == &"game_over")
	_check(tag + " victory bed after run", _music().get_state() == &"victory")


func _finish() -> void:
	var errors := 0
	var audio_warnings := 0
	for d in _diags:
		if d["severity"] == "error":
			errors += 1
			push_error("VERIFY DIAG ERROR: %s" % d["message"])
		if d["severity"] == "warning" and (String(d["message"]).contains("cue unavailable") or String(d["message"]).contains("voice limit")):
			audio_warnings += 1
			push_error("VERIFY AUDIO WARNING: %s" % d["message"])
	_total += 1
	if errors > 0 or audio_warnings > 0:
		_failures.append("zero error/audio diagnostics")
	else:
		print("  PASS: zero error/audio diagnostics")
	print("VERIFY FLOW: %d checks, %d failed" % [_total, _failures.size()])
	for f in _failures:
		print("  FAILED: %s" % f)
	var code := 1 if not _failures.is_empty() else 0
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit(code)
