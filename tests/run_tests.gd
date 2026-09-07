extends SceneTree
## Headless test runner.
##   godot --headless --path . --import          (first run only)
##   godot --headless --path . --script res://tests/run_tests.gd
## Returns exit code 0 only when every unit + combat integration test passes.
##
## Pure unit suites run synchronously in _initialize(). Node-based integration tests
## are deferred to _process() because nodes added during _initialize() are not yet
## inside the live tree (global transforms return identity there), which would make
## positional/spatial assertions invalid.

const UNIT_SUITES := [
	"res://tests/unit/test_save.gd",
	"res://tests/unit/test_combat.gd",
	"res://tests/unit/test_configs.gd",
	"res://tests/unit/test_scoring.gd",
	"res://tests/unit/test_waves.gd",
	"res://tests/unit/test_combo.gd",
	"res://tests/unit/test_upgrades.gd",
	"res://tests/unit/test_upgrade_selection.gd",
	"res://tests/unit/test_progression.gd",
]

var _failures: Array[String] = []
var _total := 0
var _integration_run := false


func _initialize() -> void:
	# Unit suites are pure (no nodes) -> safe to run immediately.
	for path in UNIT_SUITES:
		var script: GDScript = load(path)
		if script == null:
			_failures.append("Could not load suite: %s" % path)
			_total += 1
			continue
		var cases: Array = script.call("suite")
		for c in cases:
			_total += 1
			if not bool(c.get("passed", false)):
				_failures.append("%s :: %s — %s" % [path.get_file(), str(c.get("name", "")), str(c.get("why", ""))])


func _process(_delta: float) -> bool:
	if _integration_run:
		return false
	_integration_run = true
	# Deferred to the first live frame so Node3D children are truly inside the tree.
	var combat := _run_combat_integration()
	_total += combat.size()
	for c in combat:
		if not bool(c.get("passed", false)):
			_failures.append("combat :: %s — %s" % [str(c.get("name", "")), str(c.get("why", ""))])

	var combos := _run_attack_combo_integration()
	_total += combos.size()
	for c in combos:
		if not bool(c.get("passed", false)):
			_failures.append("attack :: %s — %s" % [str(c.get("name", "")), str(c.get("why", ""))])

	print("========================================")
	print("GDScript tests: %d total, %d failed" % [_total, _failures.size()])
	for f in _failures:
		print("  FAIL  " + f)
	print("========================================")
	quit(0 if _failures.is_empty() else 1)
	return false


## Deterministic combat integration: real HealthComponent damage/invuln/death +
## pure arc target query, using injected fake-clock time. No physics or audio needed.
func _run_combat_integration() -> Array:
	var results: Array = []

	var clock := FakeClock.new()
	var hp := HealthComponent.new()
	root.add_child(hp)
	hp.set_time_source(clock.now)
	hp.reset(100.0)

	# Damage applies and reduces health.
	var dmg := DamagePayload.new()
	dmg.amount = 30.0
	var r1 := hp.take_damage(dmg)
	results.append({
		"name": "damage applies 30/100 -> 70",
		"passed": r1.accepted and is_equal_approx(hp.current_health, 70.0) and not r1.target_died,
		"why": "current=%f accepted=%s" % [hp.current_health, str(r1.accepted)],
	})

	# Invalid payloads rejected safely.
	var bad := DamagePayload.new()
	bad.amount = -5.0
	var rb := hp.take_damage(bad)
	results.append({
		"name": "negative damage rejected (invalid_payload)",
		"passed": not rb.accepted and rb.ignored_reason == DamageResult.IGNORE_INVALID_PAYLOAD,
		"why": "",
	})

	# Invulnerability window ignores damage.
	hp.set_invulnerable(1.0)
	var inv := hp.take_damage(dmg)
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

	# Advance past the 1s invulnerability window so the next hit can land.
	clock.advance(2.0)

	# Lethal damage -> death exactly once.
	# Note: GDScript lambdas capture outer locals by value, so a mutable Array is
	# used as the counter instead of an int.
	var lethal := DamagePayload.new()
	lethal.amount = 1000.0
	var death_count: Array[int] = [0]
	hp.died.connect(func() -> void: death_count[0] += 1)
	var rl := hp.take_damage(lethal)
	hp.take_damage(lethal)  # duplicate damage on a corpse
	results.append({
		"name": "lethal damage dies once, duplicate ignored",
		"passed": rl.target_died and death_count[0] == 1 and hp.is_dead(),
		"why": "died=%d" % death_count[0],
	})
	root.remove_child(hp)
	hp.queue_free()

	# Pure arc query against fake Node3D targets (added to tree first so that
	# global_position reflects their positions).
	var t1 := Node3D.new()
	root.add_child(t1)
	t1.global_position = Vector3(0, 0, -2.0)  # in front, in range
	var t2 := Node3D.new()
	root.add_child(t2)
	t2.global_position = Vector3(0, 0, -8.0)  # too far
	var t3 := Node3D.new()
	root.add_child(t3)
	t3.global_position = Vector3(0, 0, -1.0)
	var arc_hits := CombatQuery.find_targets_in_arc(Vector3.ZERO, Vector3(0, 0, -1), [t1, t2, t3], 3.0, 45.0)
	results.append({
		"name": "arc query keeps in-range targets only",
		"passed": arc_hits.size() == 2 and t1 in arc_hits and t3 in arc_hits and t2 not in arc_hits,
		"why": "hits=%d" % arc_hits.size(),
	})
	for n in [t1, t2, t3]:
		root.remove_child(n)
		n.queue_free()
	return results


## Deterministic light-melee combo integration: a real AttackController (a plain child
## node with no autoload deps) driven by explicit advance() steps and request_attack()
## presses. No physics frames, no timers, no audio. Verifies chain escalation, the
## timing window, the max-step cap, and full reset.

func _run_attack_combo_integration() -> Array:
	var results: Array = []
	var body := CharacterBody3D.new()
	root.add_child(body)
	var atk := AttackController.new()
	body.add_child(atk)  # _ready caches the CharacterBody3D owner
	atk.can_crit = false
	atk.combo_steps = 3
	atk.attack_windup = 0.1
	atk.attack_cooldown = 0.6
	atk.combo_chain_window = 0.35

	var ok_step1 := (
		atk.get_phase() == atk.PHASE_READY
		and atk.request_attack()
		and atk.get_phase() == atk.PHASE_WINDUP
		and atk.get_combo_step() == 1
	)
	results.append({
		"name": "fresh READY accepts first swing at combo step 1",
		"passed": ok_step1,
		"why": "phase=%s step=%d" % [str(atk.get_phase()), atk.get_combo_step()],
	})

	results.append({
		"name": "request during WINDUP rejected (no mid-windup chain)",
		"passed": not atk.request_attack(),
		"why": "",
	})

	atk.advance(atk.attack_windup)
	var hit_opens := (
		atk.get_phase() == atk.PHASE_RECOVERY
		and atk.is_chain_ready()
		and atk.get_combo_step() == 1
	)
	results.append({
		"name": "swing resolves into RECOVERY with chain window open",
		"passed": hit_opens,
		"why": "phase=%s" % str(atk.get_phase()),
	})

	var chained_step2 := (
		atk.request_attack()
		and atk.get_phase() == atk.PHASE_WINDUP
		and atk.get_combo_step() == 2
	)
	results.append({
		"name": "chain within window advances to step 2 without waiting the cooldown",
		"passed": chained_step2,
		"why": "step=%d" % atk.get_combo_step(),
	})

	atk.advance(atk.attack_windup)
	var step2_opens := (
		atk.get_phase() == atk.PHASE_RECOVERY
		and atk.get_combo_step() == 2
		and atk.is_chain_ready()
	)
	results.append({
		"name": "step 2 hit reopens the chain window",
		"passed": step2_opens,
		"why": "phase=%s" % str(atk.get_phase()),
	})

	var chained_step3 := (
		atk.request_attack()
		and atk.get_combo_step() == 3
		and atk.get_phase() == atk.PHASE_WINDUP
	)
	results.append({
		"name": "chain again reaches final step 3",
		"passed": chained_step3,
		"why": "step=%d" % atk.get_combo_step(),
	})

	var capped_windup := (
		not atk.request_attack()
		and atk.get_combo_step() == 3
		and atk.get_phase() == atk.PHASE_WINDUP
	)
	results.append({
		"name": "no chain at max steps while still winding up",
		"passed": capped_windup,
		"why": "step=%d" % atk.get_combo_step(),
	})

	atk.advance(atk.attack_windup)
	var capped := (
		atk.get_phase() == atk.PHASE_RECOVERY
		and atk.get_combo_step() == 3
		and not atk.request_attack()
	)
	results.append({
		"name": "step 3 resolves, then capped (cannot chain at max)",
		"passed": capped,
		"why": "step=%d" % atk.get_combo_step(),
	})

	atk.advance(atk.attack_cooldown)
	var reset_after_chain := (
		atk.get_phase() == atk.PHASE_READY
		and atk.get_combo_step() == 0
		and atk.is_attack_ready()
	)
	results.append({
		"name": "combo resets to READY / step 0 once the chain ends",
		"passed": reset_after_chain,
		"why": "step=%d" % atk.get_combo_step(),
	})

	# Timing-window lapse: a late press cannot chain, and after the cooldown the combo
	# resets so the next swing is a fresh step 1.
	atk.request_attack()
	atk.advance(atk.attack_windup)  # step-1 recovery, window open
	atk.advance(atk.combo_chain_window + 0.05)  # window lapses while still in recovery
	var late_press_blocked := (
		not atk.is_chain_ready()
		and not atk.request_attack()
		and atk.get_combo_step() == 1
	)
	results.append({
		"name": "late press after the window lapses cannot chain",
		"passed": late_press_blocked,
		"why": "step=%d" % atk.get_combo_step(),
	})

	atk.advance(atk.attack_cooldown)
	var reset_after_lapse := (
		atk.get_phase() == atk.PHASE_READY
		and atk.get_combo_step() == 0
	)
	results.append({
		"name": "after lapse + cooldown returns to READY and resets step",
		"passed": reset_after_lapse,
		"why": "step=%d" % atk.get_combo_step(),
	})

	# Disabling the controller must clear any in-progress combo.
	atk.request_attack()
	atk.set_attacks_enabled(false)
	var disable_resets := (
		atk.get_phase() == atk.PHASE_READY
		and atk.get_combo_step() == 0
	)
	results.append({
		"name": "set_attacks_enabled(false) resets phase + combo",
		"passed": disable_resets,
		"why": "step=%d" % atk.get_combo_step(),
	})

	root.remove_child(body)
	body.queue_free()
	return results
