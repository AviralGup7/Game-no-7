extends RefCounted
## Live-node audit regressions; every fixture is freed before the next suite.

class GridArena extends FakeArena:
	var grid := ArenaNavGrid.new()

	func get_nav_grid() -> ArenaNavGrid:
		return grid


static func suite() -> Array:
	var results: Array = []
	var tree := Engine.get_main_loop() as SceneTree
	var fixture := Node3D.new()
	tree.root.add_child(fixture)
	var stages: GDScript = load("res://tests/integration_stages.gd")
	var scene: PackedScene = stages.call("_pack_test_enemy_scene")
	_test_spawns(results, fixture, scene)
	_test_objective(results, fixture, scene)
	_test_integrity(results)
	tree.root.remove_child(fixture)
	fixture.free()
	return results


static func _check(results: Array, label: String, passed: bool) -> void:
	results.append({"name": label, "passed": passed, "why": ""})


static func _config(scene: PackedScene) -> EnemyConfig:
	var cfg := EnemyConfig.new()
	cfg.archetype_id = &"audit_enemy"
	cfg.display_name = "Audit enemy"
	cfg.scene = scene
	return cfg


static func _test_spawns(results: Array, fixture: Node3D, scene: PackedScene) -> void:
	var arena := GridArena.new()
	var blockers: Array[AABB] = [AABB(Vector3(-1, -1, -1), Vector3(2, 3, 2))]
	arena.grid.build(12.0, 1.0, blockers)
	fixture.add_child(arena)
	arena.add_marker(Vector3.ZERO)  # Inside a solid landmark.
	var restricted := arena.add_marker(Vector3(8, 0, 8))
	restricted.set_meta("allowed_archetypes", [&"heavy"])
	var safe := arena.add_marker(Vector3(-8, 0, -8))
	_check(results, "distance fallback still respects marker restrictions and blockers", SpawnPlacer.fallback_point(arena, &"audit_enemy") == safe)
	restricted.set_meta("allowed_archetypes", {"malformed": true})
	_check(results, "malformed marker metadata fails closed", SpawnPlacer.fallback_point(arena, &"audit_enemy") == safe)
	_check(results, "non-finite spawn positions are rejected", not SpawnPlacer.position_is_clear(arena, Vector3(NAN, 0, 1)))
	_check(results, "blocked and out-of-bounds burst positions are rejected", not SpawnPlacer.position_is_clear(arena, Vector3.ZERO) and not SpawnPlacer.position_is_clear(arena, Vector3(12, 0, 0)))

	var target := Node3D.new()
	fixture.add_child(target)
	var container := Node3D.new()
	fixture.add_child(container)
	var manager := SpawnManager.new()
	var timer := Timer.new()
	timer.name = "SpawnTimer"
	manager.add_child(timer)
	fixture.add_child(manager)
	manager.configure(arena, target, container, 71)
	var cfg := _config(scene)
	manager.set_content_provider(func(_id: StringName) -> EnemyConfig: return cfg)
	var queue: Array[StringName] = [&"audit_enemy", &"audit_enemy"]
	manager.queue_wave(queue, 1, 0.2, 1)
	_check(results, "forced spawning obeys simultaneous cap and keeps pending ledger", manager.get_active_count() == 1 and not manager.force_spawn_one() and manager.get_pending_count() == 1)
	manager.clear()
	manager._max_simultaneous = 2
	_check(results, "split child can spawn in clear geometry", manager._spawn_split_child(cfg, Vector3(5, 0, 5), 0, 1))
	_check(results, "split child receives the arena navigation grid", manager.get_active_count() == 1 and manager._active[0].get_nav_grid() == arena.grid)
	manager._spawn_split_child(cfg, Vector3(5, 0, 5), 0, 1)
	_check(results, "split burst obeys the same population cap", manager.get_active_count() == 2 and not manager._spawn_split_child(cfg, Vector3(5, 0, 5), 0, 1))
	var splitter := _config(scene)
	splitter.splits_into = &"audit_enemy"
	splitter.split_count = 3
	splitter.split_burst = true
	manager._dispatch_split(manager._active[0], splitter, Vector3(5, 0, 5))
	_check(results, "overflow split children stay in the wave plan", manager.get_pending_count() == 3 and manager.get_active_count() == 2 and manager.get_planned_count() == 5)
	manager.clear()
	_check(results, "split children never materialize in a solid landmark", not manager._spawn_split_child(cfg, Vector3.ZERO, 0, 1))

	# Invalid scene roots and their children are Nodes, not reference-counted.
	var wrong_root := Node3D.new()
	var child := Node.new()
	wrong_root.add_child(child)
	child.owner = wrong_root
	var bad_scene := PackedScene.new()
	bad_scene.pack(wrong_root)
	wrong_root.free()
	var bad := _config(bad_scene)
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	for attempt in range(4):
		_check(results, "wrong scene root rejected: " + str(attempt), manager._instantiate_enemy(bad) == null)
	_check(results, "rejected scene roots do not leak orphan nodes", Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == orphans)

	# The 11..12 outer cells are blocked by the nav-grid wall margin. A legal
	# marker just inside that boundary must not jitter into those cells.
	for marker in arena._markers:
		marker.free()
	arena._markers.clear()
	arena.add_marker(Vector3(10.9, 0, 10.9))
	var positions_clear := true
	for seed_value in range(20):
		manager.configure(arena, target, container, seed_value)
		manager.queue_wave([&"audit_enemy"], 1, 0.2, 1)
		positions_clear = positions_clear and manager.get_active_count() == 1
		if manager.get_active_count() == 1:
			positions_clear = positions_clear and SpawnPlacer.position_is_clear(arena, manager._active[0].global_position)
	_check(results, "random spawn jitter cannot cross the arena wall", positions_clear)
	manager.clear()

	var hazards := ArenaHazards.new()
	var spike := HazardInstance.build(HazardConfig.resolve(&"spike_bed"), 0, Vector3(0, 0, 6), 1.2, 0.0)
	hazards._instances.append(spike)
	_check(results, "spawn safety accounts for player radius at spike edges", not hazards.is_spawn_clear(Vector3(0, 0, 4.5)))
	_check(results, "spawn safety leaves clear floor available", hazards.is_spawn_clear(Vector3(3, 0, 3)))
	hazards.free()


static func _test_objective(results: Array, fixture: Node3D, scene: PackedScene) -> void:
	var director := ObjectiveDirector.new()
	fixture.add_child(director)
	var center := Vector3(40, 0, 40)  # Separate from other suites' queued enemies.
	director.configure(GameMode.MODE_DEFEND, center, null)
	_check(results, "beacon receives its global pose after tree insertion", director._beacon.global_position == center)
	var enemy := scene.instantiate() as EnemyBase
	fixture.add_child(enemy)
	enemy.global_position = center
	enemy.initialize(_config(scene), null, 71)
	_check(results, "live enemies threaten beacon", director._enemies_near_beacon() == 1)
	enemy._alive = false  # Corpse still belongs to the enemies group during fade.
	_check(results, "dead enemies no longer drain beacon", director._enemies_near_beacon() == 0)
	director.configure(GameMode.MODE_DEFEND, center, null)
	_check(results, "reconfiguration replaces rather than duplicates beacon", director.get_child_count() == 1 and director._bus.size() == 1)
	director.configure(GameMode.MODE_STANDARD, center, null)
	_check(results, "leaving objective mode removes beacon and subscriptions", director.get_child_count() == 0 and director._bus.size() == 0 and not director.is_active())


static func _test_integrity(results: Array) -> void:
	var script: GDScript = load("res://scripts/save/save_manager.gd")
	var manager: Node = script.new()
	for digest in [7, {}, [], null]:
		_check(results, "wrong-type integrity digest is safely rejected: " + str(digest), not manager.call("_integrity_valid", {"integrity": {"algorithm": "sha256", "digest": digest}}))
	var serialized: String = manager.call("_serialize_save")
	var document: Dictionary = JsonHelpers.parse_safe(serialized)
	_check(results, "valid save envelope still round-trips", manager.call("_integrity_valid", document))
	var legacy := SaveSchema.default_save()
	legacy.schema_version = 6
	legacy.best_score = 123
	legacy.lifetime_statistics.total_time_seconds = 45.5
	legacy.meta_ranks = {"health": 2}
	legacy.settings.input_bindings = InputRemapper.serialize_actions([&"attack"])
	legacy["integrity"] = {"algorithm": "sha256", "digest": manager.call("_sha256_text", JSON.stringify(legacy))}
	var parsed_legacy: Dictionary = JsonHelpers.parse_safe(JSON.stringify(legacy))
	_check(results, "legacy integer-based save digests remain recoverable", manager.call("_integrity_valid", parsed_legacy))
	parsed_legacy.best_score = 124.0
	_check(results, "legacy compatibility still rejects content tampering", not manager.call("_integrity_valid", parsed_legacy))
	document.settings.master_volume = 0.23
	_check(results, "canonical save digests still reject content tampering", not manager.call("_integrity_valid", document))
	var seed_value: int = 5695371275779888110
	for elapsed in [0.876467666666667, 1.23456789012345, 360.1234567890123, 0.1]:
		var varied := SaveSchema.default_save()
		varied.last_run_build.seed = seed_value
		varied.lifetime_statistics.total_time_seconds = elapsed
		manager.set("_save", varied)
		var wire: String = manager.call("_serialize_save")
		var decoded: Dictionary = JsonHelpers.parse_safe(wire)
		_check(results, "fractional clock integrity survives disk JSON: " + str(elapsed), manager.call("_integrity_valid", decoded, wire))
		_check(results, "daily int64 seed survives JSON: " + str(elapsed), SaveSchema.normalize_save(decoded).last_run_build.seed == seed_value)
		decoded.best_score = 1234.0
		_check(results, "wire fallback cannot authenticate a different document: " + str(elapsed), not manager.call("_integrity_valid", decoded, wire))
	var awkward := {"clock": 0.876467666666667, "integrity_nested": {"integrity": "comma, brace} and quote\""}, "values": [1, 2.0]}
	var old_hash: String = manager.call("_sha256_text", JSON.stringify(awkward))
	awkward.integrity = {"algorithm": "sha256", "digest": old_hash}
	var old_wire := JSON.stringify(awkward)
	_check(results, "legacy exact wire digest survives fractional rounding and nested text", manager.call("_integrity_valid", JsonHelpers.parse_safe(old_wire), old_wire))
	_check(results, "oversized decimal seed strings are rejected before integer conversion", SaveSchema._seed_or("99999999999999999999999999") == 0)
	manager.free()
