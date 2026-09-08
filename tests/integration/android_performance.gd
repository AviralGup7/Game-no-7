extends Node
## Opt-in real-tree regression/profile probe. Run through tool/profile_android.sh:
## uses live autoloads and Main, but writes only to an isolated test save directory.
## Headless numbers are CPU/lifecycle observations, NEVER Android/GPU benchmarks.

var _checks := 0
var _failures: Array[String] = []
var _reports: Array[Dictionary] = []


func _ready() -> void:
	if "--isolated-performance-tests" not in OS.get_cmdline_user_args():
		push_error("Use tool/profile_android.sh to isolate save data.")
		get_tree().quit(2)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures.append(label)
		push_error("PERF FAIL: " + label)


func _settle(frames: int = 4) -> void:
	for frame in range(frames):
		await get_tree().process_frame


func _snapshot(label: String) -> Dictionary:
	return {
		"label": label,
		"elapsed_msec": Time.get_ticks_msec(),
		"static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	}


func _test_audio() -> void:
	for cue in ProceduralSfx.MUSIC_CUES:
		_check("shipped music registered before Main: " + String(cue),
			AudioManager.get_cue_stream(cue) is AudioStreamOggVorbis)
	for cue in ProceduralSfx.SFX_CUES:
		_check("SFX still available: " + String(cue), AudioManager.has_cue(cue))
	var battle := AudioManager.get_cue_stream(&"music_battle")
	_check("combat music states share one compressed stream",
		battle == AudioManager.get_cue_stream(&"music_boss")
		and battle == AudioManager.get_cue_stream(&"music_victory")
		and battle == AudioManager.get_cue_stream(&"music_calm"))
	# The pure unit suite still tests deterministic synthesis of every fallback.
	var fallback := ProceduralSfx.make_sfx(&"enemy_hit")
	_check("fallback synthesis remains available", fallback != null and fallback.data.size() > 0)


func _test_model_bounds() -> void:
	var root := Node3D.new()
	var non_spatial := AnimationPlayer.new()
	root.add_child(non_spatial)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	root.add_child(mesh)
	var bounds := CharacterVisuals._bounds(root, Transform3D.IDENTITY)
	_check("bounds accepts non-3D animation children", bounds.size == Vector3.ONE)
	root.free()


func _test_enemy_feedback() -> void:
	var host := Node3D.new()
	var visual := Node3D.new()
	visual.name = "VisualRoot"
	host.add_child(visual)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	visual.add_child(mesh)
	var feedback := EnemyFeedback.new()
	host.add_child(feedback)
	add_child(host)
	feedback.play_damaged()
	var previous := feedback._feedback_tween
	feedback.play_crit()
	_check("rapid feedback cancels old tween", not previous.is_valid())
	feedback._set_flash_color(Color.WHITE)
	_check("3D flash uses material overlay", mesh.material_overlay != null)
	feedback._feedback_tween.custom_step(0.04)
	feedback.play_telegraph()
	_check("interrupting pulse cannot strand scale", visual.scale == Vector3.ONE)
	feedback._set_flash_color(Color.TRANSPARENT)
	_check("idle feedback adds no overlay pass", mesh.material_overlay == null)
	feedback.play_died()
	host.free()


func _test_owned_emitters() -> void:
	var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for iteration in range(20):
		var effects := EffectDirector.new()
		add_child(effects)
		effects.burst_at(Vector3.ZERO, Color.WHITE)
		_check("burst has exactly one owned emitter", effects.get_child_count() == 1)
		effects.free()
	_check("20 VFX teardown cycles leave no orphan emitter",
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == before)


func _test_projectiles() -> void:
	var bad_scene := PackedScene.new()
	var wrong_root := Node3D.new()
	_check("pack invalid projectile fixture", bad_scene.pack(wrong_root) == OK)
	wrong_root.free()
	var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var pool := ProjectilePool.new()
	pool.pool_size = 1
	pool.projectile_scene = bad_scene
	add_child(pool)
	var shot := pool.fire({"team": Projectile.TEAM_PLAYER, "direction": Vector3.FORWARD})
	var mesh := shot.get_node("Visual/Mesh") as MeshInstance3D
	var material := mesh.material_override
	pool.release(shot)
	for iteration in range(100):
		shot = pool.fire({"team": Projectile.TEAM_ENEMY, "direction": Vector3.FORWARD})
		_check("projectile material reused", mesh.material_override == material)
		pool.release(shot)
	_check("team tint updated", (material as StandardMaterial3D).albedo_color == Color(1.0, 0.2, 0.25))
	pool.free()
	_check("rejected projectile root freed",
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == before)


func _test_pickup_tint() -> void:
	var pool := PickupManager.new()
	pool.pool_size = 1
	add_child(pool)
	var pickup := pool.spawn_pickup(&"health_orb", Vector3.ZERO)
	_check("pickup fixture spawned", pickup != null)
	if pickup != null:
		var mesh := pickup.get_node("Visual/Mesh") as MeshInstance3D
		var material := mesh.material_override
		for iteration in range(100):
			pickup._apply_tint()
		_check("pickup material reused", mesh.material_override == material)
	pool.free()


func _test_number_expiry() -> void:
	var layer := DamageNumberLayer.new()
	add_child(layer)
	var camera := Camera3D.new()
	add_child(camera)
	layer.bind_camera(camera)
	for index in range(32):
		layer.spawn_damage_number(Vector3(0, 0, -5), float(index + 1))
	_check("number pool fills", layer.live_count() == 32)
	layer._process(1.0)
	_check("all simultaneous expirations removed", layer.live_count() == 0)
	layer.spawn_text(Vector3(0, 0, -5), "Reuse")
	_check("expired label reusable", layer.live_count() == 1)
	layer.clear_all()
	layer.free()
	camera.free()


func _sample_gameplay(frame_count: int) -> Dictionary:
	var intervals: Array[float] = []
	var process_ms: Array[float] = []
	var physics_ms: Array[float] = []
	var draws := 0
	var vram := 0
	var previous := Time.get_ticks_usec()
	for frame in range(frame_count):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - previous) / 1000.0)
		previous = now
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		draws = maxi(draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		vram = maxi(vram, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	return {
		"frame_interval_ms": _distribution(intervals),
		"engine_process_ms": _distribution(process_ms),
		"engine_physics_ms": _distribution(physics_ms),
		"max_draw_calls": draws if DisplayServer.get_name() != "headless" else -1,
		"max_video_bytes": vram if DisplayServer.get_name() != "headless" else -1,
	}


func _distribution(values: Array[float]) -> Dictionary:
	values.sort()
	var count := values.size()
	return {"p50": values[int((count - 1) * 0.50)], "p95": values[int((count - 1) * 0.95)],
		"p99": values[int((count - 1) * 0.99)], "max": values[count - 1]}


func _run() -> void:
	_reports.append(_snapshot("autoloads_ready"))
	_test_audio()
	var start := Time.get_ticks_usec()
	var scene := load("res://scenes/main/main.tscn") as PackedScene
	var main := scene.instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	_reports.append({"label": "main_load_and_instantiate", "msec": (Time.get_ticks_usec() - start) / 1000.0})
	await _settle()
	_check("cold menu", GameRoot.get_current_state() == GameRoot.State.MAIN_MENU)
	_test_model_bounds()
	_test_enemy_feedback()
	_test_owned_emitters()
	_test_projectiles()
	_test_pickup_tint()
	_test_number_expiry()
	await _settle()
	var baseline_orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var menu_connections := EventBus.enemy_killed.get_connections().size()
	var menu_nodes := get_tree().get_node_count()
	var arenas := [&"default_arena", &"ember_crucible", &"frost_hollow"]
	for cycle in range(12):
		ContentRegistry.select_arena(arenas[cycle % arenas.size()])
		seed(7100 + cycle)
		start = Time.get_ticks_usec()
		GameRoot.request_play()
		var row := _snapshot("run_%02d" % cycle)
		row["build_msec"] = (Time.get_ticks_usec() - start) / 1000.0
		_check("run enters PLAYING", GameRoot.get_current_state() == GameRoot.State.PLAYING)
		var player := GameRoot.get_active_player()
		_check("run has player", is_instance_valid(player))
		if is_instance_valid(player):
			# Test-only invulnerability keeps timing samples independent of player death.
			(player.get_node("HealthComponent") as HealthComponent).set_invulnerable(30.0)
		var perf := get_tree().get_first_node_in_group("performance_monitor") as PerformanceMonitor
		if perf != null:
			perf.set_auto_scale(false)
			perf.set_tier(PerformanceMonitor.TIER_LOW if "--low-tier" in OS.get_cmdline_user_args() else PerformanceMonitor.TIER_MEDIUM)
		Input.action_press(&"attack")
		Input.action_press(&"move_right")
		row["sample"] = await _sample_gameplay(180 if cycle < 3 else 12)
		Input.action_release(&"attack")
		Input.action_release(&"move_right")
		GameRoot.request_pause()
		_check("pause", get_tree().paused)
		GameRoot.request_resume()
		GameRoot.request_game_over()
		_check("game over", GameRoot.get_current_state() == GameRoot.State.GAME_OVER)
		GameRoot.request_restart()
		await _settle()
		_check("direct restart", GameRoot.get_current_state() == GameRoot.State.PLAYING)
		GameRoot.request_main_menu()
		await _settle()
		_check("world cleared", main.get_node("WorldRoot").get_child_count() == 0)
		_check("run signals disconnected", EventBus.enemy_killed.get_connections().size() == menu_connections)
		_check("menu node count stable", get_tree().get_node_count() == menu_nodes)
		_check("run teardown leaves no orphans", int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == baseline_orphans)
		_check("menu FPS ceiling restored", Engine.max_fps == int(ProjectSettings.get_setting_with_override("application/run/max_fps")))
		row["after_menu"] = _snapshot("menu_%02d" % cycle)
		_reports.append(row)
	print("PERF REPORT: " + JSON.stringify({"display": DisplayServer.get_name(), "samples": _reports, "failures": _failures}))
	print("PERF TESTS: %d checks, %d failed" % [_checks, _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)
