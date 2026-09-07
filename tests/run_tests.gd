extends SceneTree
## Headless test runner.
##   godot --headless --path . --import          (first run only)
##   godot --headless --path . --script res://tests/run_tests.gd
## Returns exit code 0 only when every unit + combat integration test passes.

const UNIT_SUITES := [
	"res://tests/unit/test_save.gd",
	"res://tests/unit/test_combat.gd",
	"res://tests/unit/test_configs.gd",
	"res://tests/unit/test_scoring.gd",
]


func _initialize() -> void:
	var failures: Array[String] = []
	var total := 0
	var failed := 0

	for path in UNIT_SUITES:
		var script: GDScript = load(path)
		if script == null:
			failed += 1
			failures.append("Could not load suite: %s" % path)
			continue
		var cases: Array = script.call("suite")
		for c in cases:
			total += 1
			if not bool(c.get("passed", false)):
				failed += 1
				failures.append("%s :: %s — %s" % [path.get_file(), str(c.get("name", "")), str(c.get("why", ""))])

	var combat := _run_combat_integration()
	total += combat.size()
	for c in combat:
		if not bool(c.get("passed", false)):
			failed += 1
			failures.append("combat :: %s — %s" % [str(c.get("name", "")), str(c.get("why", ""))])

	print("========================================")
	print("GDScript tests: %d total, %d failed" % [total, failed])
	for f in failures:
		print("  FAIL  " + f)
	print("========================================")
	if failed == 0 and failures.is_empty():
		quit(0)
	else:
		quit(1)


## Deterministic combat integration: real HealthComponent damage/invuln/death +
## pure arc target query, using injected fake-clock time. No physics or audio needed.
func _run_combat_integration() -> Array:
	var results: Array = []
	var HealthScript := load("res://scripts/player/health_component.gd")
	var Payload := load("res://scripts/combat/damage_payload.gd")
	var Query := load("res://scripts/combat/combat_query.gd")
	var FakeClock := load("res://tests/doubles/fake_clock.gd")

	var clock = FakeClock.new()
	var hp = HealthScript.new()
	root.add_child(hp)
	hp.set_time_source(clock.now)
	hp.reset(100.0)

	# Damage applies and reduces health.
	var dmg := Payload.new()
	dmg.amount = 30.0
	var r1 = hp.take_damage(dmg)
	results.append({
		"name": "damage applies 30/100 -> 70",
		"passed": r1.accepted and is_equal_approx(hp.current_health, 70.0) and not r1.target_died,
		"why": "current=%f accepted=%s" % [hp.current_health, str(r1.accepted)],
	})

	# Invalid payloads rejected safely.
	var bad := Payload.new()
	bad.amount = -5.0
	var rb = hp.take_damage(bad)
	results.append({
		"name": "negative damage rejected (invalid_payload)",
		"passed": not rb.accepted and rb.ignored_reason == DamageResult.IGNORE_INVALID_PAYLOAD,
		"why": "",
	})

	# Invulnerability window ignores damage.
	hp.set_invulnerable(1.0)
	var inv = hp.take_damage(dmg)
	results.append({
		"name": "invulnerable damage ignored",
		"passed": not inv.accepted and inv.ignored_reason == DamageResult.IGNORE_INVULNERABLE,
		"why": "",
	})

	# Healing caps at max.
	hp.heal(500.0)
	results.append({
		"name": "heal caps at max health",
		"passed": is_equal_approx(hp.current_health, 100.0),
		"why": "",
	})

	# Lethal damage -> death exactly once.
	var lethal := Payload.new()
	lethal.amount = 1000.0
	var death_events := 0
	hp.died.connect(func() -> void: death_events += 1)
	var rl = hp.take_damage(lethal)
	hp.take_damage(lethal)  # duplicate damage on a corpse
	results.append({
		"name": "lethal damage dies once, duplicate ignored",
		"passed": rl.target_died and death_events == 1 and hp.is_dead(),
		"why": "died=%d" % death_events,
	})
	root.remove_child(hp)
	hp.queue_free()

	# Pure arc query against fake Node3D targets.
	var t1 := Node3D.new(); t1.global_position = Vector3(0, 0, -2.0); root.add_child(t1)  # in front, in range
	var t2 := Node3D.new(); t2.global_position = Vector3(0, 0, -8.0); root.add_child(t2)  # too far
	var t3 := Node3D.new(); t3.global_position = Vector3(0, 0, -1.0); root.add_child(t3)
	var arc_hits: Array = Query.find_targets_in_arc(Vector3.ZERO, Vector3(0, 0, -1), [t1, t2, t3], 3.0, 45.0)
	results.append({
		"name": "arc query keeps in-range targets only",
		"passed": arc_hits.size() == 2 and t1 in arc_hits and t3 in arc_hits and t2 not in arc_hits,
		"why": "hits=%d" % arc_hits.size(),
	})
	for n in [t1, t2, t3]:
		root.remove_child(n)
		n.queue_free()
	return results
