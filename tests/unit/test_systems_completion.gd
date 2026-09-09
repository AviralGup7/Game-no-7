extends RefCounted

## Pins the completed lock-on / targeting / analytics / narrator / graphics seams.


static func suite() -> Array:
	var results: Array = []
	_targeting(results)
	_narrator(results)
	_analytics(results)
	_mode(results)
	return results


static func _check(results: Array, name: String, passed: bool, why: String = "") -> void:
	results.append({"name": name, "passed": passed, "why": why})


static func _targeting(results: Array) -> void:
	var t := TargetingComponent.new()
	t.require_line_of_sight = false
	t.aim_assist_strength = 0.6
	t.bind_owner(null)
	_check(results, "targeting without owner returns null", t.pick_best_target([]) == null)
	t.free()


static func _narrator(results: Array) -> void:
	Narrator.reset_run()
	_check(results, "warlord blurb is authored", not Narrator.enemy_blurb(&"warlord").is_empty())
	Narrator.note_enemy_spawned(&"warlord")
	Narrator.note_enemy_spawned(&"warlord")
	_check(results, "first-of-kind is sticky per run", Narrator._seen_archetypes.has(&"warlord"))
	Narrator.reset_run()
	_check(results, "narrator run reset clears seen archetypes", Narrator._seen_archetypes.is_empty())


static func _analytics(results: Array) -> void:
	var script: GDScript = load("res://scripts/core/run_analytics.gd")
	_check(results, "RunAnalytics script loads", script != null)


static func _mode(results: Array) -> void:
	var m := CameraModeController.new()
	m.set_lock_target(null)
	_check(results, "cleared lock is not locked", not m.is_locked())
	_check(results, "shockwave telegraph constant exists",
		BossController.TELEGRAPH_SHOCKWAVE == &"shockwave")
