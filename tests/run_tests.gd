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

## Pure suites: no Node3D, no tree access. Safe to run synchronously.
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
	"res://tests/unit/test_rng_tables.gd",
	"res://tests/unit/test_status_skills.gd",
	"res://tests/unit/test_drops_elites.gd",
	"res://tests/unit/test_director_mutators.gd",
	"res://tests/unit/test_meta_misc.gd",
	"res://tests/unit/test_planner_extended.gd",
	"res://tests/unit/test_extracted_modules.gd",
	"res://tests/unit/test_procedural_sfx.gd",
	"res://tests/unit/test_enemy_behaviors.gd",
	"res://tests/unit/test_nav_grid.gd",
	"res://tests/unit/test_enemy_brain.gd",
	"res://tests/unit/test_content_progression.gd",
	"res://tests/unit/test_presentation_scripts.gd",
	"res://tests/unit/test_game_modes.gd",
]

## Node3D-based suites: these build Node3D fixtures and assert on positions.
## They MUST run in the deferred phase. Nodes created during _initialize() are not
## inside the live tree yet, so global_position returns identity — the fixtures set
## .position but production code (AreaDamage, MeleeResolver, ...) reads
## .global_position, so every target collapses onto the origin and spatial
## assertions fail for reasons that have nothing to do with the code under test.
const NODE_SUITES := [
	"res://tests/unit/test_model_visual.gd",
	"res://tests/unit/test_weapons.gd",
	"res://tests/unit/test_area_combat.gd",
	"res://tests/unit/test_character_visuals.gd",
	"res://tests/unit/test_hero_rig.gd",
	"res://tests/unit/test_arena_obstacles_node.gd",
	"res://tests/unit/test_enemy_scene_inheritance.gd",
]

var _failures: Array[String] = []
var _total := 0
var _integration_run := false


func _initialize() -> void:
	# Unit suites are pure (no nodes) -> safe to run immediately.
	_run_suites(UNIT_SUITES)


## Load each suite and fold its cases into the totals/failures.
func _run_suites(paths: Array) -> void:
	for path in paths:
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
	# Node3D-based unit suites must run here for the same reason as the integration
	# stages below: global_position is only meaningful once the tree is live.
	_run_suites(NODE_SUITES)
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
	# GitHub caps ::error annotations at 10 per step, which silently hides the
	# tail of a long failure list and makes it look like fixes "revealed" new
	# breakage. Emit the full list as ONE annotation (newlines escaped per the
	# workflow-command spec) so every failure is always visible.
	if not _failures.is_empty():
		var joined := "\n".join(_failures).replace("\n", "%0A")
		print("::error title=GDScript test failures (%d)::%s" % [_failures.size(), joined])
	print("========================================")
	# Also write the full report to a file: CI uploads *.log artifacts, so the
	# complete failure list is retrievable even when step output is truncated.
	var report := FileAccess.open("res://godot-test-report.log", FileAccess.WRITE)
	if report != null:
		report.store_string("GDScript tests: %d total, %d failed\n" % [_total, _failures.size()])
		for x in _failures:
			report.store_string("FAIL  " + x + "\n")
		report.close()
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
	# Chains only open on a LANDED hit (deep-bug-hunt batch 5), so the swing needs
	# a real target: a Damageable dummy in the "enemies" group, in range of the
	# body at the origin. Without it every chain assertion below would whiff.
	var dummy := _ComboDummy.new()
	root.add_child(dummy)
	dummy.add_to_group("enemies")
	dummy.global_position = Vector3(0, 0, -1.0)

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

	# Whiffs must never escalate the combo (batch-5 semantics): with the dummy
	# gone, a resolved swing leaves the chain window closed.
	root.remove_child(dummy)
	dummy.free()
	atk.set_attacks_enabled(true)
	atk.request_attack()
	atk.advance(atk.attack_windup)
	results.append({
		"name": "whiff (no target) does not open the chain window",
		"passed": atk.get_phase() == atk.PHASE_RECOVERY and not atk.is_chain_ready(),
		"why": "phase=%s chain=%s" % [str(atk.get_phase()), str(atk.is_chain_ready())],
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

## Melee-combo stand-in: a Damageable in the "enemies" group that accepts every
## hit and never dies, so chained swings always land.
class _ComboDummy extends Damageable:
	func apply_damage(_payload: DamagePayload) -> DamageResult:
		var result := DamageResult.new()
		result.accepted = true
		result.final_amount = _payload.amount
		return result


class _FakeTarget extends Damageable:
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


## Step an enemy until `predicate` holds, up to `max_steps`. Returns true if the
## condition was met. Fixed frame counts are fragile here: taking damage forces
## the enemy through the `hurt` state (hurt_duration, default 0.25s) before it
## can chase or wind up a swing, so a hand-counted budget that ignores the
## stagger silently observes the wrong phase.
func _step_enemy_until(
	enemy: EnemyBase, dt: float, max_steps: int, predicate: Callable
) -> bool:
	for i in range(max_steps):
		if predicate.call():
			return true
		_step_enemy(enemy, dt)
	return predicate.call()


func _step_enemy(enemy: EnemyBase, dt: float) -> void:
	var before := enemy.global_position
	enemy._physics_process(dt)
	# move_and_slide() integrates against the ENGINE's physics tick, not the dt we
	# pass in, and these enemies have set_physics_process(false) with no real
	# physics frames running — so the body barely advances and any assertion about
	# closing distance (dash contact, kiting) silently observes a stationary enemy.
	# Advance the body ourselves from the velocity the AI just produced, honouring
	# the test's dt, and only when the state machine has not teleported the node.
	if enemy.global_position.is_equal_approx(before):
		enemy.global_position = before + Vector3(enemy.velocity.x, 0.0, enemy.velocity.z) * dt
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
	# These step-counted assertions were written for the instant-engage loop;
	# the production default now includes a human reaction beat (0.2 s). Zero
	# keeps the exact frame budgets below valid. The reaction beat itself is
	# covered by the dedicated "reaction beat" integration check and by
	# tests/unit/test_enemy_brain.gd.
	cfg.reaction_time = 0.0
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
	# Step only until the cooldown releases back to chase. The target never leaves
	# range, so chase immediately re-enters attack and swings again — running a
	# fixed 14 extra frames would observe that *second* swing and wrongly report
	# hits=2/signals=2. Stop on the first frame the cooldown hands control back.
	for i in range(20):
		_step_enemy(melee, 0.05)  # through the 0.5s cooldown
		if melee.get_state() != &"attack":
			break
	results.append({
		"name": "melee cycle: chase->attack, exactly one hit at windup end, cooldown->chase",
		"passed": entered_attack and one_hit and still_attack
			and melee.get_state() == &"chase" and attack_signals[0] == 1,
		"why": "state=%s hits=%d signals=%d" % [String(melee.get_state()), target.hits.size(), attack_signals[0]],
	})
	melee.queue_free()

	# --- Reaction beat: the default config no longer engages on the first
	# frame — the stimulus needs the (short) reaction time before pursuit.
	var react_target := _FakeTarget.new()
	root.add_child(react_target)
	react_target.global_position = Vector3(1.0, 0.0, 0.0)
	var react_cfg := _basic_cfg()
	react_cfg.reaction_time = 0.3
	var reactor := _make_enemy(react_cfg, Vector3.ZERO, react_target)
	_step_enemy(reactor, 1.0 / 60.0)
	_step_enemy(reactor, 1.0 / 60.0)
	var still_wary := reactor.get_state() == &"idle"
	var engaged := _step_enemy_until(
		reactor, 0.05, 25, func() -> bool: return reactor.get_state() != &"idle"
	)
	results.append({
		"name": "reaction beat: a perceived stimulus delays engagement by the reaction time",
		"passed": still_wary and engaged,
		"why": "wary_after_2_frames=%s engaged_sooner_or_by_budget=%s state=%s" \
				% [str(still_wary), str(engaged), String(reactor.get_state())],
	})
	reactor.queue_free()

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
	# The chip damage below totals 35, which would kill the 20 hp default and make
	# the enemy report `dead` instead of the `hurt` stagger this asserts. Give it
	# enough health to survive breaking its own poise budget.
	poise_cfg.max_health = 200.0
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
	# Stop the moment the retreat hands control back to chase. The target is still
	# inside attack_range, so chase re-enters attack on the very next step and a
	# fixed 10-step budget would observe that second swing instead of the re-engage.
	_step_enemy_until(
		skirmisher, 0.05, 20, func() -> bool: return skirmisher.get_state() == &"chase"
	)
	results.append({
		"name": "fast skirmisher back-pedals after landing a hit, then re-engages",
		"passed": retreating and skirmisher.get_state() == &"chase",
		"why": "retreat=%s state=%s" % [str(retreating), String(skirmisher.get_state())],
	})
	skirmisher.queue_free()

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
	# A charge is an explosive lunge: with the 8 m/s^2 default the body only
	# reaches ~3.6 m/s and covers 0.9m of the 2.7m gap before dash_duration
	# expires, so it can never make contact. Accelerate like a real dasher.
	dash_cfg.acceleration = 60.0
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
	# Ride out the recovery and stop the instant it releases to chase. The charge
	# ends right next to the target, so chase can convert straight into an attack
	# on the following step and a fixed budget would observe `attack` instead of
	# the recovery -> chase transition under test.
	_step_enemy_until(
		dasher, 0.05, 20, func() -> bool: return dasher.get_state() == &"chase"
	)
	var cooled_down := not dasher.is_dash_ready()
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
	# apply_damage above forced the vampire into `hurt`; it must clear that stagger
	# (0.25s) and then complete a 0.2s windup before any hit — and therefore any
	# lifesteal — can happen. Step until it actually heals rather than guessing.
	var healed := _step_enemy_until(
		vampire, 0.05, 40, func() -> bool: return vampire.get_health_fraction() > hp_before
	)
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
	var boss_results := _run_boss_integration(target)
	results.append_array(boss_results)

	# --- SpawnManager wave cycle ----------------------------------------------
	var spawn_results := _run_spawn_manager_integration()
	results.append_array(spawn_results)

	target.queue_free()
	whiff_target.queue_free()
	poise_target.queue_free()
	hurt_target.queue_free()
	corpse_target.queue_free()
	skirm_target.queue_free()
	dash_target.queue_free()
	fuse_target.queue_free()
	fuse_target2.queue_free()
	kite_target.queue_free()
	vamp_target.queue_free()
	return results


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
	# The boss must still be in the intro phase before any damage: a spurious
	# early transition is one-way and would leave it permanently enraged.
	var phase_at_start := controller.current_phase()
	boss.apply_damage(_lethal_payload(null).with_amount(210.0))  # 600 -> 390 (0.65)
	var frac_after_first := boss.get_health_fraction()
	var p1 := controller.current_phase() == 1 and controller.phase_name() == "Fury"
	var fury_damage := is_equal_approx(boss.get_effective_attack_damage(), 18.0 * 1.25)
	# Cross the 0.33 threshold -> phase 2 (Enrage).
	boss.apply_damage(_lethal_payload(null).with_amount(200.0))  # 390 -> 190 (0.317)
	var p2 := controller.current_phase() == 2 and controller.is_enraged()
	var enrage_damage := is_equal_approx(boss.get_effective_attack_damage(), 18.0 * 1.25 * 1.5)
	results.append({
		"name": "boss: phases advance on health thresholds with stacking stat bumps",
		"passed": phase_at_start == 0 and p1 and p2 and fury_damage and enrage_damage
			and phases_seen.size() == 2 and phases_seen[0] == [1, 3] and phases_seen[1] == [2, 3],
		"why": "phase=%d dmg=%.2f seen=%s frac1=%.3f p0=%d" % [
			controller.current_phase(), boss.get_effective_attack_damage(),
			str(phases_seen), frac_after_first, phase_at_start],
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
func _pack_test_enemy_scene() -> PackedScene:
	var proto := EnemyBase.new()
	proto.name = "EnemyBase"
	var hp := HealthComponent.new()
	hp.name = "HealthComponent"
	proto.add_child(hp)
	var machine := EnemyStateMachine.new()
	machine.name = "EnemyStateMachine"
	proto.add_child(machine)
	# PackedScene.pack() only serializes children whose owner is the packed root.
	# Without this the scene contains a bare EnemyBase: spawned enemies have no
	# HealthComponent, so apply_damage is rejected with no_health_component, they
	# never die, and every defeat/clear assertion in this stage silently fails.
	hp.owner = proto
	machine.owner = proto
	var ps := PackedScene.new()
	ps.pack(proto)
	proto.free()
	return ps


func _spawn_test_cfg(id: StringName, scene: PackedScene, max_health: float = 20.0) -> EnemyConfig:
	var cfg := EnemyConfig.new()
	cfg.archetype_id = id
	cfg.display_name = String(id)
	cfg.scene = scene
	cfg.max_health = max_health
	cfg.move_speed = 2.5
	cfg.attack_damage = 6.0
	return cfg


func _run_spawn_manager_integration() -> Array:
	var results: Array = []
	var scene := _pack_test_enemy_scene()

	var arena := FakeArena.new()
	root.add_child(arena)
	arena.add_marker(Vector3(8, 0, 8))
	arena.add_marker(Vector3(-8, 0, 8))
	arena.add_marker(Vector3(8, 0, -8))
	arena.add_marker(Vector3(-8, 0, -8))

	var player := _FakeTarget.new()
	root.add_child(player)

	var container := Node3D.new()
	root.add_child(container)

	var cfg_basic := _spawn_test_cfg(&"basic", scene)
	var cfg_mite := _spawn_test_cfg(&"mite", scene, 8.0)
	var cfg_splitter := _spawn_test_cfg(&"splitter", scene, 30.0)
	cfg_splitter.splits_into = &"mite"
	cfg_splitter.split_count = 2
	cfg_splitter.split_burst = true
	var configs := {&"basic": cfg_basic, &"mite": cfg_mite, &"splitter": cfg_splitter}

	var sm := SpawnManager.new()
	var timer := Timer.new()
	timer.name = "SpawnTimer"
	sm.add_child(timer)
	root.add_child(sm)
	sm.configure(arena, player, container, 4242)
	sm.set_content_provider(func(id: StringName): return configs.get(id))

	# --- Wave cycle: opening burst, full clear, exactly-once defeats --------
	var cleared: Array = [0]
	sm.all_cleared.connect(func() -> void: cleared[0] += 1)
	var spawned_nodes: Array = []
	sm.enemy_spawned.connect(func(enemy: Node, _archetype: StringName) -> void: spawned_nodes.append(enemy))
	var queue: Array[StringName] = [&"basic", &"basic", &"basic", &"basic"]
	sm.queue_wave(queue, 1, 0.2, 8)
	var burst_ok := sm.get_active_count() == 3 and sm.get_spawned_count() == 3 and sm.get_pending_count() == 1
	sm.force_spawn_one()
	var full_wave := sm.get_active_count() == 4 and sm.get_pending_count() == 0
	for enemy in spawned_nodes:
		(enemy as EnemyBase).apply_damage(_lethal_payload(enemy))
	var wave1_done: bool = sm.get_defeated_count() == 4 and sm.get_active_count() == 0 and cleared[0] == 1
	results.append({
		"name": "spawn manager: opening burst, full wave clear, exactly-once defeat accounting",
		"passed": burst_ok and full_wave and wave1_done and spawned_nodes.size() == 4,
		"why": "burst=%s full=%s done=%s" % [str(burst_ok), str(full_wave), str(wave1_done)],
	})

	# --- Failed spawns stay distinct from defeats; wave still resolves ------
	spawned_nodes.clear()
	var failed_signals: Array = [0]
	sm.enemy_spawn_failed.connect(func(_archetype: StringName, _reason: StringName) -> void: failed_signals[0] += 1)
	var ghost_queue: Array[StringName] = [&"ghost", &"basic"]
	sm.queue_wave(ghost_queue, 2, 0.2, 8)
	var guard := 0
	while sm.get_pending_count() > 0 and guard < 32:
		guard += 1
		if not sm.force_spawn_one():
			continue
	var failed_ok := sm.get_failed_count() == 1 and sm.get_defeated_count() == 0
	# Kill the surviving basic so the wave can clear.
	for enemy in spawned_nodes:
		if enemy is EnemyBase and (enemy as EnemyBase).is_alive():
			(enemy as EnemyBase).apply_damage(_lethal_payload(enemy))
	results.append({
		"name": "failed spawns are bounded, distinct from defeats, and cannot stall the wave",
		"passed": failed_ok and sm.get_defeated_count() == 1 and sm.get_pending_count() == 0
			and failed_signals[0] >= SpawnLedger.MAX_FAILED_ATTEMPTS,
		"why": "failed=%d defeated=%d pending=%d signals=%d" % [
			sm.get_failed_count(), sm.get_defeated_count(), sm.get_pending_count(), failed_signals[0]],
	})

	# --- Splitter burst: children at the death site, plan extended ----------
	spawned_nodes.clear()
	var split_queue: Array[StringName] = [&"splitter"]
	sm.queue_wave(split_queue, 3, 0.2, 8)
	var parent: EnemyBase = spawned_nodes[0] if not spawned_nodes.is_empty() else null
	var death_pos := Vector3(2.0, 0.0, -1.0)
	parent.global_position = death_pos
	parent.apply_damage(_lethal_payload(parent))
	var planned_ok := sm.get_planned_count() == 3 and sm.get_spawned_count() == 3
	var children := sm.get_active_count()
	var near_parent := true
	for enemy in spawned_nodes:
		if enemy is EnemyBase and (enemy as EnemyBase).is_alive():
			if (enemy as EnemyBase).global_position.distance_to(death_pos) > 1.5:
				near_parent = false
	for enemy in spawned_nodes:
		if enemy is EnemyBase and (enemy as EnemyBase).is_alive():
			(enemy as EnemyBase).apply_damage(_lethal_payload(enemy))
	var cleared_again: bool = sm.get_defeated_count() == 3 and sm.get_active_count() == 0 and cleared[0] == 3
	results.append({
		"name": "splitter burst: children spawn at the death site, extend the plan, no false clear",
		"passed": planned_ok and children == 2 and near_parent and cleared_again,
		"why": "planned=%d children=%d near=%s cleared=%s" % [
			sm.get_planned_count(), children, str(near_parent), str(cleared_again)],
	})

	# --- Shared configs are never mutated by spawning/scaling ----------------
	sm.set_difficulty_scalars({"hp": 2.0, "damage": 1.5, "speed": 1.0})
	spawned_nodes.clear()
	var scale_queue: Array[StringName] = [&"basic"]
	sm.queue_wave(scale_queue, 4, 0.2, 8)
	var scaled: EnemyBase = spawned_nodes[0] if not spawned_nodes.is_empty() else null
	var scaled_ok := scaled != null \
		and is_equal_approx(scaled.get_effective_attack_damage(), cfg_basic.attack_damage * 1.5) \
		and is_equal_approx(scaled.get_health_fraction(), 1.0)
	var cfg_pristine := is_equal_approx(cfg_basic.max_health, 20.0) \
		and is_equal_approx(cfg_basic.attack_damage, 6.0) \
		and is_equal_approx(cfg_mite.max_health, 8.0)
	if scaled != null:
		scaled.apply_damage(_lethal_payload(scaled))
	results.append({
		"name": "difficulty scaling is per-instance; shared configs stay pristine",
		"passed": scaled_ok and cfg_pristine,
		"why": "scaled=%s pristine=%s" % [str(scaled_ok), str(cfg_pristine)],
	})

	timer.stop()
	sm.clear()
	sm.queue_free()
	arena.queue_free()
	container.queue_free()
	player.queue_free()
	return results
