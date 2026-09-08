## DIAG variant 3: boss integration: compile-check slice of the enemy encounter integration.

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
	"res://tests/unit/test_model_visual.gd",
	"res://tests/unit/test_save.gd",
	"res://tests/unit/test_combat.gd",
	"res://tests/unit/test_configs.gd",
	"res://tests/unit/test_scoring.gd",
	"res://tests/unit/test_waves.gd",
	"res://tests/unit/test_combo.gd",
	"res://tests/unit/test_upgrades.gd",
	"res://tests/unit/test_upgrade_selection.gd",
	"res://tests/unit/test_progression.gd",
	"res://tests/unit/test_rng_tables.gd",
	"res://tests/unit/test_weapons.gd",
	"res://tests/unit/test_status_skills.gd",
	"res://tests/unit/test_area_combat.gd",
	"res://tests/unit/test_drops_elites.gd",
	"res://tests/unit/test_director_mutators.gd",
	"res://tests/unit/test_meta_misc.gd",
	"res://tests/unit/test_planner_extended.gd",
	"res://tests/unit/test_extracted_modules.gd",
	"res://tests/unit/test_procedural_sfx.gd",
	"res://tests/unit/test_enemy_behaviors.gd",
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
			print("::error title=Suite load failure::%s did not compile/load" % path)
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

	var target := _FakeTarget.new()
	root.add_child(target)
	var encounter := _run_boss_integration(target)
	_total += encounter.size()
	for c in encounter:
		if not bool(c.get("passed", false)):
			_failures.append("boss :: %s — %s" % [str(c.get("name", "")), str(c.get("why", ""))])
	target.queue_free()

	print("========================================")
	print("GDScript tests: %d total, %d failed" % [_total, _failures.size()])
	for f in _failures:
		print("  FAIL  " + f)
		print("::error title=GDScript test failure::%s" % f)
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


## ===========================================================================
## Enemy encounter integration (Agent 2 scope): real EnemyBase nodes driven by
## explicit physics steps — state transitions, melee timing + whiff rule, poise,
## dasher charge, exploder fuse, ranged kite, death exactly-once, elite hooks,
## boss phases + deterministic abilities, and the SpawnManager wave cycle
## (burst, failed-spawn accounting, splitter burst children, no false clears).
## Autoload-free by construction (EventBus/AudioManager lookups null-guard).
## ===========================================================================

class _FakeTarget extends Node3D:
	## Damage-recording stand-in for the player.
	var hits: Array = []
	var alive := true

	func apply_damage(payload: DamagePayload) -> DamageResult:
		var result := DamageResult.new()
		if payload == null or not payload.is_valid() or not alive:
			result.ignored_reason = DamageResult.IGNORE_INVALID_PAYLOAD
			return result
		result.accepted = true
		result.final_amount = payload.amount
		hits.append(payload.amount)
		return result

	func is_alive() -> bool:
		return alive



func _make_enemy(cfg: EnemyConfig, pos: Vector3, target: Node3D, run_seed: int = 4242) -> EnemyBase:
	var enemy := EnemyBase.new()
	var hp := HealthComponent.new()
	hp.name = "HealthComponent"
	enemy.add_child(hp)
	var machine := EnemyStateMachine.new()
	machine.name = "EnemyStateMachine"
	enemy.add_child(machine)
	root.add_child(enemy)
	enemy.set_physics_process(false)  # tests drive explicit deterministic steps
	enemy.global_position = pos
	enemy.initialize(cfg, target, run_seed)
	return enemy


func _step_enemy(enemy: EnemyBase, dt: float) -> void:
	enemy._physics_process(dt)
	# Keep the arena flat: no gravity drift in headless tests.
	var p := enemy.global_position
	enemy.global_position = Vector3(p.x, 0.0, p.z)
	enemy.velocity.y = 0.0


func _basic_cfg() -> EnemyConfig:
	var cfg := EnemyConfig.new()
	cfg.archetype_id = &"probe_basic"
	cfg.max_health = 20.0
	cfg.move_speed = 2.5
	cfg.acceleration = 8.0
	cfg.attack_damage = 6.0
	cfg.attack_range = 1.5
	cfg.attack_cooldown = 0.5
	cfg.attack_windup = 0.2
	return cfg


func _lethal_payload(source: Node) -> DamagePayload:
	var payload := DamagePayload.new()
	payload.amount = 10000.0
	payload.source = source
	payload.source_id = &"test"
	return payload



func _run_boss_integration(target: Node3D) -> Array:
	var results: Array = []
	var boss_cfg := _basic_cfg()
	boss_cfg.archetype_id = &"probe_boss"
	boss_cfg.max_health = 600.0
	boss_cfg.attack_damage = 18.0

	var boss := EnemyBase.new()
	var boss_hp := HealthComponent.new()
	boss_hp.name = "HealthComponent"
	boss.add_child(boss_hp)
	var boss_machine := EnemyStateMachine.new()
	boss_machine.name = "EnemyStateMachine"
	boss.add_child(boss_machine)
	var controller := BossController.new()
	controller.name = "BossController"
	boss.add_child(controller)
	root.add_child(boss)
	boss.set_physics_process(false)
	controller.set_physics_process(false)
	boss.global_position = Vector3.ZERO
	boss.initialize(boss_cfg, target, 4242)
	controller.begin_fight(4242)

	var phases_seen: Array = []
	controller.phase_advanced.connect(func(phase: int, max_phases: int) -> void: phases_seen.append([phase, max_phases]))
	results.append({
		"name": "boss: controller adopts the default three-phase plan and joins the boss group",
		"passed": controller.max_phases() == 3 and boss.is_in_group("boss"),
		"why": "phases=%d" % controller.max_phases(),
	})

	# Cross the 0.66 threshold -> phase 1 (Fury).
	boss.apply_damage(_lethal_payload(null).with_amount(210.0))  # 600 -> 390 (0.65)
	var p1 := controller.current_phase() == 1 and controller.phase_name() == "Fury"
	var fury_damage := is_equal_approx(boss.get_effective_attack_damage(), 18.0 * 1.25)
	# Cross the 0.33 threshold -> phase 2 (Enrage).
	boss.apply_damage(_lethal_payload(null).with_amount(200.0))  # 390 -> 190 (0.317)
	var p2 := controller.current_phase() == 2 and controller.is_enraged()
	var enrage_damage := is_equal_approx(boss.get_effective_attack_damage(), 18.0 * 1.25 * 1.5)
	results.append({
		"name": "boss: phases advance on health thresholds with stacking stat bumps",
		"passed": p1 and p2 and fury_damage and enrage_damage
			and phases_seen.size() == 2 and phases_seen[0] == [1, 3] and phases_seen[1] == [2, 3],
		"why": "phase=%d dmg=%.2f seen=%s" % [controller.current_phase(), boss.get_effective_attack_damage(), str(phases_seen)],
	})

	# Boss death clears telegraphs and does not double-fire phase events.
	boss.apply_damage(_lethal_payload(boss))
	var phases_after_death := phases_seen.size()
	results.append({
		"name": "boss: death after enrage fires no extra phase events",
		"passed": not boss.is_alive() and phases_after_death == 2,
		"why": "seen=%d" % phases_after_death,
	})
	boss.queue_free()

	# Deterministic ability selection from the run seed.
	var seq_a := _boss_ability_sequence(777, target)
	var seq_b := _boss_ability_sequence(777, target)
	var seq_c := _boss_ability_sequence(778, target)
	var valid_kinds := true
	for kind in seq_a:
		if kind not in [BossController.TELEGRAPH_SLAM, BossController.TELEGRAPH_CHARGE, BossController.TELEGRAPH_SUMMON]:
			valid_kinds = false
	results.append({
		"name": "boss: ability selection is deterministic per seed and uses known telegraphs",
		"passed": seq_a == seq_b and valid_kinds and seq_a.size() == 3,
		"why": "a=%s c=%s" % [str(seq_a), str(seq_c)],
	})
	return results


func _boss_ability_sequence(seed: int, target: Node3D) -> Array:
	var cfg := _basic_cfg()
	cfg.archetype_id = &"probe_boss_ability"
	cfg.max_health = 600.0
	var boss := EnemyBase.new()
	var hp := HealthComponent.new()
	hp.name = "HealthComponent"
	boss.add_child(hp)
	var controller := BossController.new()
	boss.add_child(controller)
	root.add_child(boss)
	boss.set_physics_process(false)
	controller.set_physics_process(false)
	boss.initialize(cfg, target, seed)
	controller.configure_phases([{
		"threshold": 1.0, "name": "Lab", "damage_mult": 1.0, "speed_mult": 1.0,
		"abilities": [&"slam", &"charge", &"summon"], "interval": 0.3,
	}])
	controller.begin_fight(seed)
	var kinds: Array = []
	controller.telegraph_started.connect(func(kind: StringName, _duration: float) -> void:
		if kind != BossController.TELEGRAPH_RECOVER:
			kinds.append(kind))
	var guard := 0
	while kinds.size() < 3 and guard < 800:
		guard += 1
		controller._physics_process(0.05)
	boss.queue_free()
	return kinds


## Minimal EnemyBase PackedScene built in code so SpawnManager configs can carry a
## scene without touching the real (model-heavy) archetype scenes.

