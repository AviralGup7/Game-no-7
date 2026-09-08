## DIAG variant: compile-check slice of the enemy encounter integration.
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

	var encounter := _run_enemy_encounter_integration()
	_total += encounter.size()
	for c in encounter:
		if not bool(c.get("passed", false)):
			_failures.append("encounter :: %s — %s" % [str(c.get("name", "")), str(c.get("why", ""))])

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



	# --- Dasher: telegraph -> charge -> one contact hit -> recovery ---------
	var dash_target := _FakeTarget.new()
	root.add_child(dash_target)
	dash_target.global_position = Vector3(4.0, 0.0, 0.0)
	var dash_cfg := _basic_cfg()
	dash_cfg.archetype_id = &"probe_dasher"
	dash_cfg.dash_trigger_range = 6.0
	dash_cfg.dash_windup = 0.2
	dash_cfg.dash_speed = 13.0
	dash_cfg.dash_duration = 0.45
	dash_cfg.dash_contact_radius = 1.3
	dash_cfg.dash_recovery = 0.3
	dash_cfg.dash_cooldown = 3.0
	var dasher := _make_enemy(dash_cfg, Vector3.ZERO, dash_target)
	_step_enemy(dasher, 1.0 / 60.0)  # idle -> chase
	_step_enemy(dasher, 1.0 / 60.0)  # chase -> dash (cooldown gate opens)
	var dashing := dasher.get_state() == &"dash"
	for i in range(8):
		_step_enemy(dasher, 0.05)  # windup -> charge (movement override active)
	var charging := dasher.is_move_overridden()
	for i in range(20):
		_step_enemy(dasher, 0.05)  # ride the charge into the target
	var dash_hits := dash_target.hits.size()
	for i in range(10):
		_step_enemy(dasher, 0.05)  # recovery -> chase
	var cooled_down := not dasher.is_dash_ready()
	_step_enemy(dasher, 1.0 / 60.0)  # target still 4m away, dash on cooldown
	results.append({
		"name": "dasher: telegraph -> charge (override) -> exactly one contact hit -> recovery",
		"passed": dashing and charging and dash_hits == 1 and cooled_down
			and dasher.get_state() == &"chase",
		"why": "dash=%s charge=%s hits=%d state=%s" % [str(dashing), str(charging), dash_hits, String(dasher.get_state())],
	})
	dasher.queue_free()

	# --- Exploder: fuse inside fuse_range, detonation through normal death --
	var fuse_target := _FakeTarget.new()
	root.add_child(fuse_target)
	fuse_target.global_position = Vector3(1.5, 0.0, 0.0)
	var fuse_cfg := _basic_cfg()
	fuse_cfg.archetype_id = &"probe_exploder"
	fuse_cfg.fuse_range = 2.0
	fuse_cfg.fuse_time = 0.3
	fuse_cfg.explodes_on_death = true
	var exploder := _make_enemy(fuse_cfg, Vector3.ZERO, fuse_target)
	var exploded: Array = [0]
	exploder.died.connect(func() -> void: exploded[0] += 1)
	_step_enemy(exploder, 1.0 / 60.0)
	_step_enemy(exploder, 1.0 / 60.0)  # -> fuse (inside fuse_range)
	var fused := exploder.get_state() == &"fuse"
	for i in range(9):
		_step_enemy(exploder, 0.05)
	results.append({
		"name": "exploder: plants inside fuse range and detonates via the normal death path",
		"passed": fused and exploded[0] == 1 and not exploder.is_alive()
			and exploder.get_state() == &"dead",
		"why": "fuse=%s died=%d" % [str(fused), exploded[0]],
	})
	exploder.queue_free()

	# --- Fuse counterplay: a hit interrupts the fuse -------------------------
	var fuse_target2 := _FakeTarget.new()
	root.add_child(fuse_target2)
	fuse_target2.global_position = Vector3(1.5, 0.0, 0.0)
	var exploder2 := _make_enemy(fuse_cfg, Vector3.ZERO, fuse_target2)
	_step_enemy(exploder2, 1.0 / 60.0)
	_step_enemy(exploder2, 1.0 / 60.0)  # -> fuse
	exploder2.apply_damage(_lethal_payload(null).with_amount(3.0))
	results.append({
		"name": "exploder: taking a hit interrupts the fuse (counterplay)",
		"passed": exploder2.get_state() == &"hurt" and exploder2.is_alive(),
		"why": "state=%s" % String(exploder2.get_state()),
	})
	exploder2.queue_free()

	# --- Ranged: kites when crowded, closes when out of reach ---------------
	var kite_target := _FakeTarget.new()
	root.add_child(kite_target)
	kite_target.global_position = Vector3(2.0, 0.0, 0.0)
	var ranged_cfg := _basic_cfg()
	ranged_cfg.archetype_id = &"probe_ranged"
	ranged_cfg.ai_behavior = &"ranged"
	ranged_cfg.ranged_range = 14.0
	ranged_cfg.ranged_cooldown = 2.0
	ranged_cfg.ranged_windup = 0.2
	ranged_cfg.preferred_distance = 9.0
	ranged_cfg.strafe_speed = 0.6
	var slinger := _make_enemy(ranged_cfg, Vector3.ZERO, kite_target)
	_step_enemy(slinger, 1.0 / 60.0)  # idle -> ranged
	var in_ranged := slinger.get_state() == &"ranged"
	_step_enemy(slinger, 1.0 / 60.0)  # 2m < 9*0.55 -> kite
	var kiting := slinger.desired_dir.dot((slinger.global_position - kite_target.global_position).normalized()) > 0.5
	kite_target.global_position = Vector3(30.0, 0.0, 0.0)  # far outside weapon reach
	for i in range(4):
		_step_enemy(slinger, 0.05)
	var closing := slinger.desired_dir.dot(Vector3.RIGHT) > 0.5
	results.append({
		"name": "ranged: enters ranged state, kites the crowded player, closes when outmatched",
		"passed": in_ranged and kiting and closing,
		"why": "ranged=%s kite=%s close=%s" % [str(in_ranged), str(kiting), str(closing)],
	})
	slinger.queue_free()

	# --- Elite hooks: vampiric sustain + frenzied cadence --------------------
	var vamp_target := _FakeTarget.new()
	root.add_child(vamp_target)
	vamp_target.global_position = Vector3(1.0, 0.0, 0.0)
	var vamp_cfg := _basic_cfg()
	vamp_cfg.attack_damage = 10.0
	var vampire := _make_enemy(vamp_cfg, Vector3.ZERO, vamp_target)
	vampire.set_elite([EliteAffix.VAMPIRIC])
	vampire.apply_damage(_lethal_payload(null).with_amount(15.0))  # 20 -> 5 hp
	var hp_before := vampire.get_health_fraction()
	_step_enemy(vampire, 1.0 / 60.0)
	_step_enemy(vampire, 1.0 / 60.0)
	for i in range(6):
		_step_enemy(vampire, 0.05)  # land one hit
	var healed := vampire.get_health_fraction() > hp_before
	results.append({
		"name": "vampiric elite heals from the damage it deals",
		"passed": healed and vampire.is_elite()
			and EliteAffix.VAMPIRIC in vampire.get_elite_affixes(),
		"why": "before=%.2f after=%.2f" % [hp_before, vampire.get_health_fraction()],
	})
	vampire.queue_free()

	var frenzied := _make_enemy(_basic_cfg(), Vector3.ZERO, vamp_target)
	frenzied.set_elite([EliteAffix.FRENZIED])
	frenzied.apply_damage(_lethal_payload(null).with_amount(15.0))  # below half health
	var frenzy_cd := frenzied.get_effective_attack_cooldown()
	var baseline := _make_enemy(_basic_cfg(), Vector3(50, 0, 50), vamp_target)
	var normal_cd := baseline.get_effective_attack_cooldown()
	results.append({
		"name": "frenzied elite attacks faster below the health trigger",
		"passed": frenzy_cd < normal_cd and is_equal_approx(normal_cd, 0.5),
		"why": "frenzy=%.2f normal=%.2f" % [frenzy_cd, normal_cd],
	})
	frenzied.queue_free()
	baseline.queue_free()

	# --- Deterministic approach offsets (anti-stacking fan-out) --------------
	var off_a := _make_enemy(_basic_cfg(), Vector3.ZERO, target, 777)
	var off_b := _make_enemy(_basic_cfg(), Vector3.ZERO, target, 777)
	off_a.set_spawn_serial(3)
	off_b.set_spawn_serial(3)
	var off_c := _make_enemy(_basic_cfg(), Vector3.ZERO, target, 777)
	off_c.set_spawn_serial(4)
	results.append({
		"name": "approach offsets deterministic per (seed, serial) and vary between enemies",
		"passed": off_a.get_approach_point(Vector3.ZERO) == off_b.get_approach_point(Vector3.ZERO)
			and off_a.get_approach_point(Vector3.ZERO) != off_c.get_approach_point(Vector3.ZERO),
		"why": "",
	})
	off_a.queue_free()
	off_b.queue_free()
	off_c.queue_free()

	# --- Boss: phase thresholds, stat bumps, enrage, deterministic abilities -
	# --- SpawnManager wave cycle ----------------------------------------------
	return results

