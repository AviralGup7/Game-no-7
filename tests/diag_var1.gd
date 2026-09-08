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



func _run_enemy_encounter_integration() -> Array:
	var results: Array = []

	# --- State machine registers the full roster of states ------------------
	var probe := _make_enemy(_basic_cfg(), Vector3(0, 0, 0), null)
	var machine := probe.get_node("EnemyStateMachine") as EnemyStateMachine
	var all_states := true
	for state_id in EnemyStateMachine.STATE_IDS:
		if not machine.has_state(state_id):
			all_states = false
	results.append({
		"name": "state machine registers idle/chase/attack/hurt/dead/ranged/dash/fuse",
		"passed": all_states,
		"why": str(EnemyStateMachine.STATE_IDS),
	})
	probe.queue_free()

	# --- Idle -> Chase -> Attack: one hit exactly, then cooldown -> Chase ---
	var target := _FakeTarget.new()
	root.add_child(target)
	target.global_position = Vector3(1.0, 0.0, 0.0)
	var melee := _make_enemy(_basic_cfg(), Vector3.ZERO, target)
	var attack_signals: Array = [0]
	melee.attack_started.connect(func() -> void: attack_signals[0] += 1)
	_step_enemy(melee, 1.0 / 60.0)  # idle -> chase (target visible)
	_step_enemy(melee, 1.0 / 60.0)  # chase -> attack (in range)
	var entered_attack := melee.get_state() == &"attack"
	for i in range(10):
		_step_enemy(melee, 0.05)  # through the 0.2s windup
	var one_hit := target.hits.size() == 1 and is_equal_approx(float(target.hits[0]), 6.0)
	var still_attack := melee.get_state() == &"attack"
	for i in range(14):
		_step_enemy(melee, 0.05)  # through the 0.5s cooldown
	results.append({
		"name": "melee cycle: chase->attack, exactly one hit at windup end, cooldown->chase",
		"passed": entered_attack and one_hit and still_attack
			and melee.get_state() == &"chase" and attack_signals[0] == 1,
		"why": "state=%s hits=%d signals=%d" % [String(melee.get_state()), target.hits.size(), attack_signals[0]],
	})
	melee.queue_free()

	# --- Whiff rule: target escapes mid-windup -> chase, no hit -------------
	var whiff_target := _FakeTarget.new()
	root.add_child(whiff_target)
	whiff_target.global_position = Vector3(1.0, 0.0, 0.0)
	var whiffer := _make_enemy(_basic_cfg(), Vector3.ZERO, whiff_target)
	_step_enemy(whiffer, 1.0 / 60.0)
	_step_enemy(whiffer, 1.0 / 60.0)  # now attacking
	_step_enemy(whiffer, 0.05)
	whiff_target.global_position = Vector3(8.0, 0.0, 0.0)  # slips out mid-windup
	_step_enemy(whiffer, 0.05)
	results.append({
		"name": "whiff: target escaping mid-windup aborts to chase without damage",
		"passed": whiffer.get_state() == &"chase" and whiff_target.hits.is_empty(),
		"why": "state=%s hits=%d" % [String(whiffer.get_state()), whiff_target.hits.size()],
	})
	whiffer.queue_free()

	# --- Poise: guarded windups absorb chip damage until the budget breaks --
	var poise_target := _FakeTarget.new()
	root.add_child(poise_target)
	poise_target.global_position = Vector3(1.0, 0.0, 0.0)
	var poise_cfg := _basic_cfg()
	poise_cfg.poise = 30.0
	poise_cfg.attack_windup = 5.0  # long swing to interrupt-test
	var bruiser := _make_enemy(poise_cfg, Vector3.ZERO, poise_target)
	_step_enemy(bruiser, 1.0 / 60.0)
	_step_enemy(bruiser, 1.0 / 60.0)  # attacking (long windup)
	bruiser.apply_damage(_lethal_payload(null).with_amount(10.0))
	var guarded := bruiser.get_state() == &"attack"
	bruiser.apply_damage(_lethal_payload(null).with_amount(25.0))
	results.append({
		"name": "poise: chip damage does not stagger the windup until the budget breaks",
		"passed": guarded and bruiser.get_state() == &"hurt",
		"why": "guarded=%s after_break=%s" % [str(guarded), String(bruiser.get_state())],
	})
	bruiser.queue_free()

	# --- Hurt interrupts, then recovers back to Chase ------------------------
	var hurt_target := _FakeTarget.new()
	root.add_child(hurt_target)
	hurt_target.global_position = Vector3(4.0, 0.0, 0.0)
	var hurt_cfg := _basic_cfg()
	hurt_cfg.hurt_duration = 0.2
	var hurtling := _make_enemy(hurt_cfg, Vector3.ZERO, hurt_target)
	_step_enemy(hurtling, 1.0 / 60.0)  # -> chase
	hurtling.apply_damage(_lethal_payload(null).with_amount(5.0))
	var staggered := hurtling.get_state() == &"hurt"
	for i in range(6):
		_step_enemy(hurtling, 0.05)
	results.append({
		"name": "hurt: damage staggers, then recovers to chase",
		"passed": staggered and hurtling.get_state() == &"chase",
		"why": "state=%s" % String(hurtling.get_state()),
	})
	hurtling.queue_free()

	# --- Death: exactly once, dead state, corpses ignore damage --------------
	var corpse_target := _FakeTarget.new()
	root.add_child(corpse_target)
	corpse_target.global_position = Vector3(4.0, 0.0, 0.0)
	var corpse := _make_enemy(_basic_cfg(), Vector3.ZERO, corpse_target)
	var died_count: Array = [0]
	corpse.died.connect(func() -> void: died_count[0] += 1)
	corpse.apply_damage(_lethal_payload(corpse))
	var second := corpse.apply_damage(_lethal_payload(corpse))
	results.append({
		"name": "death: exactly-once, dead state, further damage ignored",
		"passed": died_count[0] == 1 and not corpse.is_alive()
			and corpse.get_state() == &"dead" and not second.accepted
			and second.ignored_reason == DamageResult.IGNORE_DEAD,
		"why": "died=%d state=%s" % [died_count[0], String(corpse.get_state())],
	})
	corpse.queue_free()

	# --- Fast skirmisher: retreat phase after the hit ------------------------
	var skirm_target := _FakeTarget.new()
	root.add_child(skirm_target)
	skirm_target.global_position = Vector3(1.0, 0.0, 0.0)
	var skirm_cfg := _basic_cfg()
	skirm_cfg.attack_retreat_time = 0.3
	var skirmisher := _make_enemy(skirm_cfg, Vector3.ZERO, skirm_target)
	_step_enemy(skirmisher, 1.0 / 60.0)
	_step_enemy(skirmisher, 1.0 / 60.0)  # attack
	for i in range(5):
		_step_enemy(skirmisher, 0.05)  # past windup -> retreat
	var away := (skirmisher.global_position - skirm_target.global_position).normalized()
	var retreating := skirmisher.desired_dir.dot(away) > 0.5 and skirmisher.get_state() == &"attack"
	for i in range(10):
		_step_enemy(skirmisher, 0.05)
	results.append({
		"name": "fast skirmisher back-pedals after landing a hit, then re-engages",
		"passed": retreating and skirmisher.get_state() == &"chase",
		"why": "retreat=%s state=%s" % [str(retreating), String(skirmisher.get_state())],
	})
	skirmisher.queue_free()


