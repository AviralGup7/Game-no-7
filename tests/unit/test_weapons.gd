extends RefCounted

## Headless unit tests for WeaponConfig validation, WeaponInstance timing,
## MeleeResolver arc selection and RangedResolver math.
##
## The MeleeResolver fixtures are Node3D and MUST be inside the scene tree:
## get_global_transform() falls back to identity outside it, so parentless dummies
## all report global_position == ORIGIN and the arc/range filtering degenerates
## (every target sits on the swing origin and passes). MeleeResolver reads
## .global_position. Registered in run_tests.gd's NODE_SUITES for a live frame.

class DummyTarget extends Damageable:
	var hp := 100.0
	var hit_radius := 0.0
	func is_alive() -> bool:
		return hp > 0.0
	func get_hit_radius() -> float:
		return hit_radius
	func apply_damage(payload: DamagePayload) -> DamageResult:
		var r := DamageResult.new()
		hp -= payload.amount
		r.accepted = true
		r.final_amount = payload.amount
		r.was_critical = payload.was_critical
		return r


static func _sword() -> WeaponConfig:
	var w := WeaponConfig.new()
	w.weapon_id = &"test_sword"
	w.kind = WeaponConfig.KIND_MELEE
	w.base_damage = 10.0
	w.swing_cooldown = 0.5
	w.windup = 0.1
	w.attack_range = 3.0
	w.arc_degrees = 90.0
	w.combo_damage_steps = PackedFloat32Array([1.0, 1.5])
	w.combo_window = 0.4
	w.crit_chance = 0.0
	w.crit_multiplier = 2.0
	return w


## Attach first, then position: global_position is only meaningful in-tree.
static func _melee_dummy(pos: Vector3) -> DummyTarget:
	var d := DummyTarget.new()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(d)
	d.global_position = pos
	return d


static func suite() -> Array:
	var results: Array = []

	# --- WeaponConfig validation ---
	var good := _sword()
	results.append({"name": "WeaponConfig valid passes", "passed": good.validate().is_empty(), "why": str(good.validate())})
	var bad := WeaponConfig.new()
	bad.kind = &"nope"
	bad.swing_cooldown = 0.0
	bad.crit_chance = 2.0
	results.append({"name": "WeaponConfig flags bad kind/cooldown/crit", "passed": bad.validate().size() >= 3, "why": ""})
	results.append({
		"name": "WeaponConfig step helpers + paper dps",
		"passed": good.step_count() == 2 and is_equal_approx(good.step_multiplier(2), 1.5)
			and is_equal_approx(good.step_multiplier(99), 1.5) and good.paper_dps() > 0.0,
		"why": "",
	})

	# --- WeaponInstance: windup -> recovery -> ready ---
	var inst := WeaponInstance.new(good, 4242)
	var step := inst.try_start_attack()
	var resolved := inst.tick(0.1)
	results.append({
		"name": "WeaponInstance swing resolves after windup",
		"passed": step == 1 and resolved and inst.phase == WeaponInstance.PHASE_RECOVERY,
		"why": "step=%d phase=%s" % [step, String(inst.phase)],
	})

	# --- WeaponInstance: chain window ---
	var chained := inst.try_start_attack()
	results.append({
		"name": "WeaponInstance chains combo step 2 in window",
		"passed": chained == 2 and inst.phase == WeaponInstance.PHASE_WINDUP,
		"why": "step=%d" % chained,
	})
	inst.tick(0.1)
	var capped := inst.try_start_attack()  # at max steps: refused
	results.append({"name": "WeaponInstance capped at max combo steps", "passed": capped == 0, "why": ""})
	inst.tick(1.0)
	results.append({
		"name": "WeaponInstance returns to READY and resets combo",
		"passed": inst.is_ready() and inst.combo_step == 0,
		"why": "",
	})

	# --- WeaponInstance: ammo + reload ---
	var bow := WeaponConfig.new()
	bow.weapon_id = &"test_bow"
	bow.kind = WeaponConfig.KIND_RANGED
	bow.ammo_per_magazine = 2
	bow.reload_seconds = 0.5
	bow.projectile_speed = 10.0
	bow.projectile_lifetime = 1.0
	var gun := WeaponInstance.new(bow, 7)
	gun.try_start_attack()
	gun.tick(0.01)
	gun.tick(1.0)
	gun.try_start_attack()
	gun.tick(0.01)
	gun.tick(1.0)
	var dry := gun.try_start_attack()  # magazine empty -> auto reload, no shot
	results.append({
		"name": "WeaponInstance auto-reloads on empty magazine",
		"passed": dry == 0 and gun.is_reloading(),
		"why": "",
	})
	gun.tick(0.6)
	results.append({
		"name": "WeaponInstance reload refills and readies",
		"passed": gun.is_ready() and gun.ammo == 2,
		"why": "ammo=%d" % gun.ammo,
	})

	# --- MeleeResolver: arc selection nearest-first ---
	var front := _melee_dummy(Vector3(0, 0, -2))
	# Clearly inside the 90-degree arc (~43 deg off-axis). The old (1.5, 0, -1.5)
	# sat at exactly 45.0 deg — the arc boundary — so whether it counted came down
	# to float rounding in angle_to() rather than the behaviour under test.
	var near_side := _melee_dummy(Vector3(1.4, 0, -1.5))
	var behind := _melee_dummy(Vector3(0, 0, 2))
	var far := _melee_dummy(Vector3(0, 0, -9))
	var swing := WeaponInstance.new(good, 1)
	var hits := MeleeResolver.select_targets(Vector3.ZERO, Vector3(0, 0, -1), [front, near_side, behind, far], swing)
	results.append({
		"name": "MeleeResolver keeps in-arc targets nearest-first",
		"passed": hits.size() == 2 and hits[0] == front and hits[1] == near_side,
		"why": "hits=%d" % hits.size(),
	})

	# --- MeleeResolver: resolve_and_apply damages + crit flag ---
	swing.try_start_attack()
	var applied := MeleeResolver.resolve_and_apply(Vector3.ZERO, Vector3(0, 0, -1), [front], swing, null, true)
	results.append({
		"name": "MeleeResolver crit swing deals multiplied damage",
		"passed": applied.size() == 1 and is_equal_approx(front.hp, 100.0 - 10.0 * 2.0),
		"why": "hp=%f" % front.hp,
	})

	# --- RangedResolver: spread symmetry + muzzle + lead ---
	var dirs := RangedResolver.spread_directions(Vector3(0, 0, -1), 3, 30.0)
	var symmetric := dirs.size() == 3 and dirs[1].distance_to(Vector3(0, 0, -1)) < 0.001
	var muzzle := RangedResolver.muzzle_position(Vector3.ZERO, Vector3(0, 0, -1))
	var lead := RangedResolver.lead_direction(Vector3.ZERO, Vector3(0, 0, -10), Vector3(5, 0, 0), 10.0)
	results.append({
		"name": "RangedResolver spread symmetric, muzzle ahead, lead aims off-axis",
		"passed": symmetric and muzzle.z < -0.4 and lead.x > 0.1,
		"why": "lead=%s" % str(lead),
	})

	# --- CriticalSystem: pity + expected factor ---
	var rng := RngService.new(99)
	var r1 := CriticalSystem.roll(0.0, 0.0, 3, rng)
	results.append({
		"name": "CriticalSystem zero chance never crits, pity grows",
		"passed": not bool(r1["crit"]) and int(r1["new_pity"]) == 4,
		"why": "",
	})
	results.append({
		"name": "CriticalSystem expected factor + overkill math",
		"passed": is_equal_approx(CriticalSystem.expected_factor(0.5, 2.0), 1.5)
			and CriticalSystem.overkill_bonus(100.0, 10.0) == 45
			and CriticalSystem.overkill_bonus(5.0, 10.0) == 0,
		"why": "",
	})

	# --- WeaponInstance: authored pity actually fires on player swings ---
	var pity_cfg := _sword()
	pity_cfg.crit_chance = 0.0
	var pity_inst := WeaponInstance.new(pity_cfg, 11)
	var pity_critted := false
	for i in range(8):
		if pity_inst.roll_crit():
			pity_critted = true
	results.append({
		"name": "WeaponInstance zero-chance never crits but pity accrues",
		"passed": not pity_critted and int(pity_inst.get_debug_snapshot().get("crit_pity", -1)) == 8,
		"why": "pity=%s" % str(pity_inst.get_debug_snapshot().get("crit_pity", -1)),
	})
	pity_cfg.crit_chance = 1.0
	var forced_crit := pity_inst.roll_crit()
	results.append({
		"name": "WeaponInstance pity resets after a crit",
		"passed": forced_crit and int(pity_inst.get_debug_snapshot().get("crit_pity", -1)) == 0,
		"why": "",
	})
	pity_inst.reset()
	results.append({
		"name": "WeaponInstance reset clears pity",
		"passed": int(pity_inst.get_debug_snapshot().get("crit_pity", -1)) == 0,
		"why": "",
	})

	# --- MeleeResolver: Damageable.get_hit_radius pads reach ---
	var bulky := _melee_dummy(Vector3(0, 0, -4.5))
	bulky.hit_radius = 2.0
	var bulky_hits := MeleeResolver.select_targets(Vector3.ZERO, Vector3(0, 0, -1), [bulky], swing)
	var too_far := _melee_dummy(Vector3(0, 0, -6.0))
	too_far.hit_radius = 2.0
	var too_far_hits := MeleeResolver.select_targets(Vector3.ZERO, Vector3(0, 0, -1), [too_far], swing)
	results.append({
		"name": "MeleeResolver uses Damageable.get_hit_radius for reach",
		"passed": bulky_hits == [bulky] and too_far_hits.is_empty(),
		"why": "bulky=%d far=%d" % [bulky_hits.size(), too_far_hits.size()],
	})

	# --- Hitscan: same radius seam ---
	var beam_target := _melee_dummy(Vector3(0.7, 0, -5.0))
	beam_target.hit_radius = 0.5
	var beam_hits := RangedResolver.hitscan(Vector3.ZERO, Vector3(0, 0, -1), [beam_target], 10.0, 0.4)
	results.append({
		"name": "RangedResolver hitscan includes get_hit_radius",
		"passed": beam_hits.size() == 1 and beam_hits[0]["target"] == beam_target,
		"why": "hits=%d" % beam_hits.size(),
	})

	for d in [front, near_side, behind, far, bulky, too_far, beam_target]:
		d.get_parent().remove_child(d)
		d.free()
	return results
