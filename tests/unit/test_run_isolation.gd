extends RefCounted

## In-tree isolation + governor budget tests.
##
## ProjectilePool / HitstopManager / DamageNumberLayer / SpatialVoicePool are
## autoload-free, so they instantiate under the --script harness. RunIsolation
## and PoolGovernor walk groups on a live host. PickupManager / EffectDirector
## / Player keep their EventBus identifiers and are pinned by the Python
## suite rather than constructed here.

static func suite() -> Array:
	var results: Array = []
	var saved_max_fps := Engine.max_fps
	var saved_scale := Engine.time_scale
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		results.append({"name": "live tree is available", "passed": false, "why": "no SceneTree"})
		return results
	var host := Node3D.new()
	host.name = "IsolationHost"
	tree.root.add_child(host)

	_projectiles(results, host)
	_hitstop(results, host)
	_numbers(results, host)
	_spatial(results, host)
	_governor_apply(results, host)
	_isolator_walk(results, host)
	_isolator_null_safe(results)

	if is_instance_valid(host):
		tree.root.remove_child(host)
		host.free()
	Engine.max_fps = saved_max_fps
	Engine.time_scale = saved_scale
	return results


static func _shot() -> Dictionary:
	return {
		"origin": Vector3.ZERO,
		"direction": Vector3(0, 0, -1),
		"speed": 8.0,
		"lifetime": 8.0,
		"damage": 1.0,
	}


static func _projectiles(results: Array, host: Node) -> void:
	var pool := ProjectilePool.new()
	pool.name = "ProjectilePool"
	pool.pool_size = 8
	host.add_child(pool)
	results.append(_case(
		"pool pre-spawns idle shots and joins the group",
		pool.idle_count() == 8 and pool.active_count() == 0 and pool.is_in_group("projectile_pool"),
		"idle=%d active=%d" % [pool.idle_count(), pool.active_count()]))

	var fired: Array[Projectile] = []
	for _i in 3:
		var p := pool.fire(_shot())
		if p != null:
			fired.append(p)
	results.append(_case(
		"fire() moves shots from idle to active",
		fired.size() == 3 and pool.active_count() == 3 and pool.idle_count() == 5,
		"fired=%d active=%d idle=%d" % [fired.size(), pool.active_count(), pool.idle_count()]))

	pool.apply_budget(2)
	results.append(_case(
		"apply_budget trims live shots to the cap",
		pool.live_cap() == 2 and pool.active_count() <= 2,
		"cap=%d active=%d" % [pool.live_cap(), pool.active_count()]))

	var recycled := 0
	for _j in 6:
		if pool.fire(_shot()) != null:
			recycled += 1
	results.append(_case(
		"fire never exceeds the live cap even with idle leftover",
		pool.active_count() <= 2 and recycled == 6,
		"active=%d cap=%d idle=%d" % [pool.active_count(), pool.live_cap(), pool.idle_count()]))

	pool.isolate_run()
	var after := pool.fire(_shot())
	results.append(_case(
		"isolate_run drains active and refuses further fire",
		pool.is_isolated() and pool.active_count() == 0 and after == null,
		"isolated=%s active=%d fire=%s" % [str(pool.is_isolated()), pool.active_count(), str(after)]))


static func _hitstop(results: Array, host: Node) -> void:
	var hit := HitstopManager.new()
	hit.name = "HitstopManager"
	host.add_child(hit)
	Engine.time_scale = 0.4
	hit.request_hitstop(0.2, 0.05)
	hit.add_trauma(0.8)
	hit.isolate_run()
	results.append(_case(
		"hitstop isolate restores timescale and clears trauma",
		is_equal_approx(Engine.time_scale, 1.0) and is_equal_approx(hit.current_trauma(), 0.0) and not hit.is_frozen(),
		"scale=%s trauma=%s frozen=%s" % [str(Engine.time_scale), str(hit.current_trauma()), str(hit.is_frozen())]))
	Engine.time_scale = 1.0


static func _numbers(results: Array, host: Node) -> void:
	var numbers := DamageNumberLayer.new()
	numbers.name = "DamageNumberLayer"
	host.add_child(numbers)
	results.append(_case(
		"damage numbers join the isolator group",
		numbers.is_in_group("damage_number_layer"),
		"groups=%s" % str(numbers.get_groups())))
	numbers.clear_all()
	results.append(_case(
		"clear_all on an empty layer is a no-op",
		numbers.live_count() == 0,
		"live=%d" % numbers.live_count()))


static func _spatial(results: Array, host: Node) -> void:
	var spatial := SpatialVoicePool.new()
	spatial.name = "SpatialVoices"
	host.add_child(spatial)
	spatial.apply_budget(4)
	results.append(_case(
		"spatial apply_budget stores a cap below MAX_VOICES",
		spatial.voice_cap() == 4 and spatial.voice_cap() < SpatialVoicePool.MAX_VOICES,
		"cap=%d max=%d" % [spatial.voice_cap(), SpatialVoicePool.MAX_VOICES]))
	var dummy := Node3D.new()
	dummy.name = "ListenerDummy"
	host.add_child(dummy)
	spatial.set_listener(dummy)
	results.append(_case(
		"spatial listener binds before isolate",
		spatial.has_listener(),
		"listener=%s" % str(spatial.has_listener())))
	spatial.isolate_run()
	results.append(_case(
		"spatial isolate parks the listener and flags the pool",
		spatial.is_isolated() and not spatial.has_listener() and spatial.active_count() == 0,
		"isolated=%s listener=%s active=%d" % [str(spatial.is_isolated()), str(spatial.has_listener()), spatial.active_count()]))


static func _governor_apply(results: Array, host: Node) -> void:
	var mon := PerformanceMonitor.new()
	mon.name = "PerformanceMonitor"
	mon.set_tier(PerformanceMonitor.TIER_LOW)
	host.add_child(mon)
	var pool := host.get_node_or_null("ProjectilePool") as ProjectilePool
	if pool == null:
		results.append(_case("governor apply finds the projectile pool", false, "missing pool"))
		return
	# A fresh isolated pool refuses fire; rebuild a sibling for the budget walk.
	var live := ProjectilePool.new()
	live.name = "BudgetPool"
	live.pool_size = 16
	host.add_child(live)
	var report := PoolGovernor.apply(mon, host)
	results.append(_case(
		"PoolGovernor.apply writes the LOW projectile cap onto live pools",
		int(report.get("projectiles", -1)) == mon.max_projectiles()
		and live.live_cap() == mon.max_projectiles(),
		"report=%s cap=%d want=%d" % [str(report.get("projectiles")), live.live_cap(), mon.max_projectiles()]))
	results.append(_case(
		"PoolGovernor.caps_are_monotonic holds on a live monitor",
		PoolGovernor.caps_are_monotonic(mon),
		"tier=%s" % mon.get_tier_name()))
	results.append(_case(
		"PoolGovernor.caps_are_bounded holds on a live monitor",
		PoolGovernor.caps_are_bounded(mon),
		"tier=%s" % mon.get_tier_name()))


static func _isolator_walk(results: Array, host: Node) -> void:
	var pool := host.get_node_or_null("BudgetPool") as ProjectilePool
	if pool == null:
		results.append(_case("isolator walk has a budget pool", false, "missing"))
		return
	# BudgetPool is not isolated; fire then walk.
	pool.fire(_shot())
	pool.fire(_shot())
	var before := pool.active_count()
	var report := RunIsolation.isolate_from(host)
	results.append(_case(
		"RunIsolation.isolate_from drains the projectile group",
		before > 0 and int(report.get("projectiles", -1)) == 0 and pool.active_count() == 0 and pool.is_isolated(),
		"before=%d report=%s after=%d" % [before, str(report.get("projectiles")), pool.active_count()]))
	results.append(_case(
		"RunIsolation.is_quiet after a drain",
		RunIsolation.is_quiet(report),
		str(report)))
	results.append(_case(
		"isolator does not free the host (GAME_OVER keeps WorldRoot)",
		is_instance_valid(host) and host.is_inside_tree() and host.get_child_count() > 0,
		"children=%d" % host.get_child_count()))
	results.append(_case(
		"known_groups lists every walker target",
		RunIsolation.known_groups().size() == 7
		and RunIsolation.known_groups().has("projectile_pool")
		and RunIsolation.known_groups().has("damage_number_layer"),
		str(RunIsolation.known_groups())))


static func _isolator_null_safe(results: Array) -> void:
	var empty := RunIsolation.isolate_from(null)
	results.append(_case(
		"isolate_from(null) returns the empty report",
		int(empty.get("projectiles", 99)) == -1 and RunIsolation.is_quiet(empty),
		str(empty)))
	var detached := Node3D.new()
	var from_detached := RunIsolation.isolate_from(detached)
	results.append(_case(
		"isolate_from(detached) is a no-op",
		int(from_detached.get("projectiles", 99)) == -1,
		str(from_detached)))
	detached.free()


static func _case(name: String, passed: bool, why: String = "") -> Dictionary:
	return {"name": name, "passed": passed, "why": why}
