## Runtime-loaded integration stages for the headless runner.
##
## THIS FILE IS LOADED AT RUNTIME by tests/run_tests.gd (never at startup):
## Godot compiles the --script main loop BEFORE project autoloads are registered
## as global identifiers, so the main-loop script must not depend on game
## scripts that reference autoloads (EventBus / GameRoot / AudioManager) at
## compile time. By the time _initialize()/_process() load() this script the
## autoloads exist, and every reference below resolves normally.
##
## Everything here is deterministic: fake-clock time, explicit physics steps,
## fixed seeds. No autoload access is required (EnemyBase null-guards its
## EventBus lookup), matching the runner's hermetic design.
extends RefCounted


## Deterministic combat integration: real HealthComponent damage/invuln/death +
## pure arc target query, using injected fake-clock time. No physics or audio needed.
static func _run_combat_integration(tree: SceneTree) -> Array:
	var results: Array = []

	var clock := FakeClock.new()
	var hp := HealthComponent.new()
	tree.root.add_child(hp)
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
	tree.root.remove_child(hp)
	hp.queue_free()

	# Pure arc query against fake Node3D targets (added to tree first so that
	# global_position reflects their positions).
	var t1 := Node3D.new()
	tree.root.add_child(t1)
	t1.global_position = Vector3(0, 0, -2.0)  # in front, in range
	var t2 := Node3D.new()
	tree.root.add_child(t2)
	t2.global_position = Vector3(0, 0, -8.0)  # too far
	var t3 := Node3D.new()
	tree.root.add_child(t3)
	t3.global_position = Vector3(0, 0, -1.0)
	var arc_hits := CombatQuery.find_targets_in_arc(Vector3.ZERO, Vector3(0, 0, -1), [t1, t2, t3], 3.0, 45.0)
	results.append({
		"name": "arc query keeps in-range targets only",
		"passed": arc_hits.size() == 2 and t1 in arc_hits and t3 in arc_hits and t2 not in arc_hits,
		"why": "hits=%d" % arc_hits.size(),
	})
	for n in [t1, t2, t3]:
		tree.root.remove_child(n)
		n.queue_free()
	return results


## ===========================================================================
## Enemy encounter integration (Agent 2 scope): real EnemyBase nodes driven by
## explicit physics steps — state transitions, melee timing + whiff rule, poise,
## dasher charge, exploder fuse, ranged kite, death exactly-once, elite hooks,
## boss phases + deterministic abilities, and the SpawnManager wave cycle
## (burst, failed-spawn accounting, splitter burst children, no false clears).
## Autoload-free by construction (EventBus/AudioManager lookups null-guard).
## ===========================================================================

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


static func _make_enemy(tree: SceneTree, cfg: EnemyConfig, pos: Vector3, target: Node3D, run_seed: int = 4242) -> EnemyBase:
	var enemy := EnemyBase.new()
	var hp := HealthComponent.new()
	hp.name = "HealthComponent"
	enemy.add_child(hp)
	var machine := EnemyStateMachine.new()
	machine.name = "EnemyStateMachine"
	enemy.add_child(machine)
	tree.root.add_child(enemy)
	enemy.set_physics_process(false)  # tests drive explicit deterministic steps
	enemy.global_position = pos
	enemy.initialize(cfg, target, run_seed)
	return enemy


## Step an enemy until `predicate` holds, up to `max_steps`. Returns true if the
## condition was met. Fixed frame counts are fragile here: taking damage forces
## the enemy through the `hurt` state (hurt_duration, default 0.25s) before it
## can chase or wind up a swing, so a hand-counted budget that ignores the
## stagger silently observes the wrong phase.
static func _step_enemy_until(
	enemy: EnemyBase, dt: float, max_steps: int, predicate: Callable
) -> bool:
	for i in range(max_steps):
		if predicate.call():
			return true
		_step_enemy(enemy, dt)
	return predicate.call()


static func _step_enemy(enemy: EnemyBase, dt: float) -> void:
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


static func _basic_cfg() -> EnemyConfig:
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


static func _lethal_payload(source: Node) -> DamagePayload:
	var payload := DamagePayload.new()
	payload.amount = 10000.0
	payload.source = source
	payload.source_id = &"test"
	return payload


static func _run_enemy_encounter_integration(tree: SceneTree) -> Array:
	var results: Array = []

	# --- State machine registers the full roster of states ------------------
	var probe := _make_enemy(tree, _basic_cfg(), Vector3(0, 0, 0), null)
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
	tree.root.add_child(target)
	target.global_position = Vector3(1.0, 0.0, 0.0)
	var melee := _make_enemy(tree, _basic_cfg(), Vector3.ZERO, target)
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
	tree.root.add_child(react_target)
	react_target.global_position = Vector3(1.0, 0.0, 0.0)
	var react_cfg := _basic_cfg()
	react_cfg.reaction_time = 0.3
	var reactor := _make_enemy(tree, react_cfg, Vector3.ZERO, react_target)
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
	tree.root.add_child(whiff_target)
	whiff_target.global_position = Vector3(1.0, 0.0, 0.0)
	var whiffer := _make_enemy(tree, _basic_cfg(), Vector3.ZERO, whiff_target)
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
	tree.root.add_child(poise_target)
	poise_target.global_position = Vector3(1.0, 0.0, 0.0)
	var poise_cfg := _basic_cfg()
	poise_cfg.poise = 30.0
	poise_cfg.attack_windup = 5.0  # long swing to interrupt-test
	# The chip damage below totals 35, which would kill the 20 hp default and make
	# the enemy report `dead` instead of the `hurt` stagger this asserts. Give it
	# enough health to survive breaking its own poise budget.
	poise_cfg.max_health = 200.0
	var bruiser := _make_enemy(tree, poise_cfg, Vector3.ZERO, poise_target)
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
	tree.root.add_child(hurt_target)
	hurt_target.global_position = Vector3(4.0, 0.0, 0.0)
	var hurt_cfg := _basic_cfg()
	hurt_cfg.hurt_duration = 0.2
	var hurtling := _make_enemy(tree, hurt_cfg, Vector3.ZERO, hurt_target)
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
	tree.root.add_child(corpse_target)
	corpse_target.global_position = Vector3(4.0, 0.0, 0.0)
	var corpse := _make_enemy(tree, _basic_cfg(), Vector3.ZERO, corpse_target)
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
	tree.root.add_child(skirm_target)
	skirm_target.global_position = Vector3(1.0, 0.0, 0.0)
	var skirm_cfg := _basic_cfg()
	skirm_cfg.attack_retreat_time = 0.3
	var skirmisher := _make_enemy(tree, skirm_cfg, Vector3.ZERO, skirm_target)
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
	tree.root.add_child(dash_target)
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
	var dasher := _make_enemy(tree, dash_cfg, Vector3.ZERO, dash_target)
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
	tree.root.add_child(fuse_target)
	fuse_target.global_position = Vector3(1.5, 0.0, 0.0)
	var fuse_cfg := _basic_cfg()
	fuse_cfg.archetype_id = &"probe_exploder"
	fuse_cfg.fuse_range = 2.0
	fuse_cfg.fuse_time = 0.3
	fuse_cfg.explodes_on_death = true
	var exploder := _make_enemy(tree, fuse_cfg, Vector3.ZERO, fuse_target)
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
	tree.root.add_child(fuse_target2)
	fuse_target2.global_position = Vector3(1.5, 0.0, 0.0)
	var exploder2 := _make_enemy(tree, fuse_cfg, Vector3.ZERO, fuse_target2)
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
	tree.root.add_child(kite_target)
	kite_target.global_position = Vector3(2.0, 0.0, 0.0)
	var ranged_cfg := _basic_cfg()
	ranged_cfg.archetype_id = &"probe_ranged"
	ranged_cfg.ai_behavior = &"ranged"
	ranged_cfg.ranged_range = 14.0
	ranged_cfg.ranged_cooldown = 2.0
	ranged_cfg.ranged_windup = 0.2
	ranged_cfg.preferred_distance = 9.0
	ranged_cfg.strafe_speed = 0.6
	var slinger := _make_enemy(tree, ranged_cfg, Vector3.ZERO, kite_target)
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
	tree.root.add_child(vamp_target)
	vamp_target.global_position = Vector3(1.0, 0.0, 0.0)
	var vamp_cfg := _basic_cfg()
	vamp_cfg.attack_damage = 10.0
	var vampire := _make_enemy(tree, vamp_cfg, Vector3.ZERO, vamp_target)
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

	var frenzied := _make_enemy(tree, _basic_cfg(), Vector3.ZERO, vamp_target)
	frenzied.set_elite([EliteAffix.FRENZIED])
	frenzied.apply_damage(_lethal_payload(null).with_amount(15.0))  # below half health
	var frenzy_cd := frenzied.get_effective_attack_cooldown()
	var baseline := _make_enemy(tree, _basic_cfg(), Vector3(50, 0, 50), vamp_target)
	var normal_cd := baseline.get_effective_attack_cooldown()
	results.append({
		"name": "frenzied elite attacks faster below the health trigger",
		"passed": frenzy_cd < normal_cd and is_equal_approx(normal_cd, 0.5),
		"why": "frenzy=%.2f normal=%.2f" % [frenzy_cd, normal_cd],
	})
	frenzied.queue_free()
	baseline.queue_free()

	# --- Deterministic approach offsets (anti-stacking fan-out) --------------
	var off_a := _make_enemy(tree, _basic_cfg(), Vector3.ZERO, target, 777)
	var off_b := _make_enemy(tree, _basic_cfg(), Vector3.ZERO, target, 777)
	off_a.set_spawn_serial(3)
	off_b.set_spawn_serial(3)
	var off_c := _make_enemy(tree, _basic_cfg(), Vector3.ZERO, target, 777)
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
	var boss_results := _run_boss_integration(tree, target)
	results.append_array(boss_results)

	# --- SpawnManager wave cycle ----------------------------------------------
	var spawn_results := _run_spawn_manager_integration(tree)
	results.append_array(spawn_results)

	# --- Authored run definitions reaching a live tree -------------------------
	results.append_array(_run_run_definition_integration(tree))

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


static func _run_boss_integration(tree: SceneTree, target: Node3D = null) -> Array:
	var results: Array = []
	# Standalone invocation (runner wrapper) has no shared target: use a private
	# stand-in so the stage stays individually runnable.
	var owns_target := target == null
	if owns_target:
		target = _FakeTarget.new()
		tree.root.add_child(target)
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
	tree.root.add_child(boss)
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
	var seq_a := _boss_ability_sequence(tree, 777, target)
	var seq_b := _boss_ability_sequence(tree, 777, target)
	var seq_c := _boss_ability_sequence(tree, 778, target)
	var valid_kinds := true
	for kind in seq_a:
		if kind not in [BossController.TELEGRAPH_SLAM, BossController.TELEGRAPH_CHARGE, BossController.TELEGRAPH_SUMMON]:
			valid_kinds = false
	results.append({
		"name": "boss: ability selection is deterministic per seed and uses known telegraphs",
		"passed": seq_a == seq_b and valid_kinds and seq_a.size() == 3,
		"why": "a=%s c=%s" % [str(seq_a), str(seq_c)],
	})
	if owns_target:
		target.queue_free()
	return results


static func _boss_ability_sequence(tree: SceneTree, seed: int, target: Node3D) -> Array:
	var cfg := _basic_cfg()
	cfg.archetype_id = &"probe_boss_ability"
	cfg.max_health = 600.0
	var boss := EnemyBase.new()
	var hp := HealthComponent.new()
	hp.name = "HealthComponent"
	boss.add_child(hp)
	# The boss fixture must carry the full component set (the boss-integration
	# and scene fixtures both do): without the state machine, EnemyBase's
	# required-component check fires on every ability-sequence probe.
	var machine := EnemyStateMachine.new()
	machine.name = "EnemyStateMachine"
	boss.add_child(machine)
	var controller := BossController.new()
	controller.name = "BossController"
	boss.add_child(controller)
	tree.root.add_child(boss)
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
static func _pack_test_enemy_scene() -> PackedScene:
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


static func _spawn_test_cfg(id: StringName, scene: PackedScene, max_health: float = 20.0) -> EnemyConfig:
	var cfg := EnemyConfig.new()
	cfg.archetype_id = id
	cfg.display_name = String(id)
	cfg.scene = scene
	cfg.max_health = max_health
	cfg.move_speed = 2.5
	cfg.attack_damage = 6.0
	return cfg


static func _run_spawn_manager_integration(tree: SceneTree) -> Array:
	var results: Array = []
	var scene := _pack_test_enemy_scene()

	var arena := FakeArena.new()
	tree.root.add_child(arena)
	arena.add_marker(Vector3(8, 0, 8))
	arena.add_marker(Vector3(-8, 0, 8))
	arena.add_marker(Vector3(8, 0, -8))
	arena.add_marker(Vector3(-8, 0, -8))

	var player := _FakeTarget.new()
	tree.root.add_child(player)

	var container := Node3D.new()
	tree.root.add_child(container)

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
	tree.root.add_child(sm)
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

	# --- A wave's folded record reaches the arena: scaling AND the status it carries ----------
	# The static suites prove the fold; this proves the fold arrives. Ember Winds' `burn_tick` was
	# unread for as long as the record was a Dictionary, so there was literally no live path to
	# assert on. The fake player here is not a Damageable, which is also under test: stamping must
	# skip what cannot hold a status instead of calling a method it never declared.
	var ember := WaveModifiers.neutral()
	ember.hp_mult = 1.6
	ember.damage_mult = 1.5
	ember.speed_mult = 0.85
	ember.explode_chance = 1.0
	ember.severity = WaveMutatorConfig.SEVERITY_MAJOR
	ember.status_effect = load("res://data/status/ember_air.tres") as StatusEffectConfig
	ember.status_stacks = 2
	ember.status_targets_enemies = true
	ember.status_targets_player = true
	sm.set_wave_modifiers(ember)
	spawned_nodes.clear()
	var ember_queue: Array[StringName] = [&"basic"]
	sm.queue_wave(ember_queue, 5, 0.2, 8)
	var stamped: EnemyBase = spawned_nodes[0] if not spawned_nodes.is_empty() else null
	var stamped_manager := stamped.get_status_manager() if stamped != null else null
	# Every clause named separately, because a combined boolean reported as `record=false` sends
	# someone reading a CI log back to read the whole file: five sub-checks here and no clue which one
	# moved. The numbers are printed too, so the next failure says what the entity actually is.
	var has_ok := stamped_manager != null and stamped_manager.has_effect(&"ember_air")
	var stack_ok := stamped_manager != null and stamped_manager.stack_count(&"ember_air") == 2
	var full_ok := stamped != null and is_equal_approx(stamped.get_health_fraction(), 1.0)
	var attack_ok := stamped != null \
		and is_equal_approx(stamped.get_effective_attack_damage(), cfg_basic.attack_damage * 1.5)
	var health_component := stamped.get_health_component() if stamped != null else null
	var hp_ok := health_component != null \
		and is_equal_approx(health_component.get_max(), cfg_basic.max_health * 1.6)
	var record_ok := stamped != null and has_ok and stack_ok and full_ok and attack_ok and hp_ok
	# Volatile Mix at 100%: the fold's chance must actually detonate (one explosion, no crash).
	var blast_before := sm.get_active_count()
	if stamped != null:
		stamped.apply_damage(_lethal_payload(stamped))
	var consumed_the_chance := sm.get_active_count() <= blast_before and sm.get_defeated_count() >= 1
	sm.clear()
	sm.set_wave_modifiers(WaveModifiers.neutral())
	results.append({
		"name": "the wave's folded record scales spawns and stamps its status",
		"passed": record_ok and consumed_the_chance,
		# Built as a joined array on purpose: `"a" + "b" % [..]` binds as `"a" + ("b" % [..])`, so the
		# concatenated format string this replaces printed its own placeholders instead of the answer.
		"why": _describe_record(has_ok, stack_ok, full_ok, attack_ok, hp_ok, consumed_the_chance,
				stamped, stamped_manager, health_component, cfg_basic, sm),
	})

	timer.stop()
	sm.clear()
	sm.queue_free()
	arena.queue_free()
	container.queue_free()
	player.queue_free()
	return results


## What the run's authored files actually do inside a live tree. The static suites prove a `.tres`
## parses and that its numbers match the mirror; this proves the *wire* — that a mode's wave row is
## what the announcer emits, that a mode's scripted queue survives the registry hop, and that the
## prestige ladder's rung is the number the scoreboard multiplies with. In a running game these all
## resolve through ContentRegistry, which is a different path than the harness's folder scan.
## The record check's diagnosis in one line: which clause moved, what the entity actually is, and
## whether the spawner still holds the wave that was asked for. `record=false` sent two rounds of
## reading to a one-bit answer, which is not a diagnosis.
static func _describe_record(has_ok: bool, stack_ok: bool, full_ok: bool, attack_ok: bool,
		hp_ok: bool, blasts_ok: bool, stamped: EnemyBase, stamped_manager: StatusManager,
		health_component: HealthComponent, cfg_basic: EnemyConfig, sm: Node) -> String:
	var parts := PackedStringArray()
	parts.append("has=%s" % str(has_ok))
	parts.append("stacks=%s" % str(stack_ok))
	parts.append("full=%s" % str(full_ok))
	parts.append("attack=%s" % str(attack_ok))
	parts.append("hp=%s" % str(hp_ok))
	parts.append("blasts=%s" % str(blasts_ok))
	parts.append("stacks=%d" % (stamped_manager.stack_count(&"ember_air") if stamped_manager != null else -1))
	parts.append("max=%s" % (str(health_component.get_max()) if health_component != null else "none"))
	parts.append("atk=%s" % (str(stamped.get_effective_attack_damage()) if stamped != null else "none"))
	parts.append("want=%s/%s" % [str(cfg_basic.max_health * 1.6), str(cfg_basic.attack_damage * 1.5)])
	parts.append("tree=%s" % (str(stamped.is_inside_tree()) if stamped != null else "none"))
	parts.append("node=%s" % (str(stamped.get_node_or_null("StatusManager")) if stamped != null else "none"))
	parts.append("kids=%s" % (", ".join(PackedStringArray(
			stamped.get_children().map(func(c): return String(c.name)))) if stamped != null else "none"))
	var wave: WaveModifiers = sm.get_wave_modifiers() if sm != null else null
	parts.append("wave_effect=%s" % (str(wave.status_effect) if wave != null else "no-record"))
	parts.append("wave_stacks=%d" % (wave.status_stacks if wave != null else -1))
	parts.append("wave_targets=%s/%s" % [str(wave.status_targets_enemies) if wave != null else "?",
			str(wave.status_targets_player) if wave != null else "?"])
	return ", ".join(parts)


static func _run_run_definition_integration(tree: SceneTree) -> Array:
	var results: Array = []

	# --- the announcer reads the mode's row, not a table of its own -----------------
	var heard: Array = []
	var listener := func(text_key: StringName, text: String, _severity: StringName) -> void:
		heard.append([String(text_key), text])
	EventBus.announcement.connect(listener)
	Narrator.announce_wave(GameMode.MODE_CAMPAIGN, &"frost_hollow", 5)
	Narrator.announce_wave(GameMode.MODE_SURVIVAL, &"ember_crucible", 1)
	Narrator.announce_wave(GameMode.MODE_COLLECT, &"default_arena", 2)
	EventBus.announcement.disconnect(listener)
	# Exactly two announcements from three calls: the third (Relic Hunt, wave 2) has no authored beat
	# and is not a milestone wave, so silence is itself under test — the old code could only reach it
	# by falling through a `match` that knew the mode by name.
	var authored := load("res://data/game_modes/campaign.tres") as GameModeConfig
	var row := authored.plan_for_wave(5) if authored != null else null
	var expected_beat := "%s — %s" % [String(row.beat_title), String(row.beat_line)] if row != null else ""
	var beat_ok := heard.size() == 2 and String(heard[0][0]) == "campaign_beat" \
		and String(heard[0][1]) == expected_beat and not expected_beat.is_empty()
	var survival := load("res://data/game_modes/survival.tres") as GameModeConfig
	var intro_ok := heard.size() == 2 and String(heard[1][0]) == "narrator" \
		and survival != null and String(heard[1][1]) == String(survival.intro_line)
	results.append({
		"name": "announcer emits the mode's authored beat and intro, and nothing else",
		"passed": beat_ok and intro_ok,
		"why": str(heard),
	})

	# --- a mode's scripted queue survives the registry hop -------------------------
	var queue := GameMode.spawn_queue(GameMode.MODE_BOSS_RUSH, 3, 7)
	var queue_ok := queue.size() == 7 and queue[0] == &"warlord" and queue.count(&"heavy") == 1
	results.append({
		"name": "boss rush wave 3 arrives scripted from the registry path",
		"passed": queue_ok,
		"why": str(queue),
	})

	# --- the ladder resolves with no registry at all ---------------------------------
	# This harness boots only EventBus, so `Prestige.ladder()` must find the content folder on its
	# own. Forgetting the cache here is the point: it proves the disk path is a real fallback and not
	# a convenience that only the unit tests exercise. `Prestige.forget_ladder()` exists so a content
	# reload can re-resolve, and the stage reuses it to force a cold lookup.
	Prestige.forget_ladder()
	var ladder := Prestige.ladder()
	var ladder_ok := ladder != null and Prestige.max_rank() == 10 and Prestige.cost_base() == 2000 \
		and is_equal_approx(Prestige.armory_completion_required(), ladder.armory_completion_required)
	var gate_ok := ladder != null \
		and Prestige.can_prestige(0, ladder.cost_base - 1, 1.0) != &"ok" \
		and Prestige.can_prestige(0, ladder.cost_base, ladder.armory_completion_required) == &"ok" \
		and Prestige.can_prestige(0, ladder.cost_base, ladder.armory_completion_required - 0.01) != &"ok" \
		and Prestige.can_prestige(Prestige.max_rank(), 1000000, 1.0) != &"ok"
	results.append({
		"name": "the prestige ladder resolves from the content folder, and its gate is the file's own",
		"passed": ladder_ok and gate_ok,
		"why": "ladder=%s rank=%d" % [str(ladder != null), Prestige.max_rank()],
	})

	# --- and the rung is what the scoreboard pays with ------------------------------
	# `RunScorekeeper` takes the mode and the rank from GameRoot; this harness boots neither, so the
	# run is a standard one at rank 0 and its payout is the kill's own value untouched. That is the
	# first half of the contract: the ladder must not reach into a mode that does not scale with
	# prestige, which is exactly how the old flat per-rank bonus double-counted. The second half is the
	# *selection* — which rung a challenge run at rank 8 gets — asserted against the rows the resource
	# carries rather than against a literal, because a hard-coded "rank 8 means tier 3" here was a
	# guess about data that says 0/2/4/6/8. Numbers written from memory are how this file has failed
	# twice; the file is the source.
	var run := RunState.new()
	var keeper := RunScorekeeper.new()
	keeper.reset_run(run)
	keeper.record_kill(100, 0)
	var want_standard := int(round(101.0 * GameMode.score_multiplier_for(GameMode.MODE_STANDARD, 8)))
	var selected := -1
	if ladder != null:
		selected = ladder.tier_index_for_rank(8)
	var rung: ChallengeTier = ladder.challenge_tiers[selected] if ladder != null and selected >= 0 else null
	# The rung that covers rank 8 is the last one whose unlock it clears, and the next one must still
	# be out of reach; that is the whole ladder contract in two comparisons, with no index to drift.
	var selection_ok := rung != null and rung.unlock_rank <= 8 \
		and (selected + 1 >= ladder.challenge_tiers.size() \
			or ladder.challenge_tiers[selected + 1].unlock_rank > 8)
	var at_eighth := GameMode.score_multiplier_for(GameMode.MODE_CHALLENGE, 8)
	var payout_ok := run.score == want_standard and selection_ok \
		and is_equal_approx(at_eighth, rung.score_mult) \
		and is_equal_approx(GameMode.score_multiplier_for(GameMode.MODE_STANDARD, 8), 1.0)
	results.append({
		"name": "a run's payout is its tier's multiplier and the mode's own, never both",
		"passed": payout_ok,
		"why": "score=%d want=%d rank8=%.3f tier=%d/%d unlock=%d" % [run.score, want_standard,
				at_eighth, selected, ladder.challenge_tiers.size() if ladder != null else -1,
				rung.unlock_rank if rung != null else -1],
	})

	return results
