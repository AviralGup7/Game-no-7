extends RefCounted

## Headless unit tests for AreaDamage shapes (radial/line/ring/chain) and the
## CombatLog ring buffer.
##
## Dummies MUST be inside the scene tree. Node3D.get_global_transform() fails to
## the identity transform for a node outside the tree, so a parentless dummy
## reports global_position == ORIGIN no matter what .position was set to — every
## target then collapses onto the blast centre and the shape assertions are
## meaningless. AreaDamage reads .global_position, so we attach each dummy to the
## live tree root and free them at the end of the suite. This suite is registered
## in run_tests.gd's NODE_SUITES so it runs on a live frame.

class DummyTarget extends Node3D:
	var hp := 100.0
	func is_alive() -> bool:
		return hp > 0.0
	func apply_damage(payload: DamagePayload) -> DamageResult:
		var r := DamageResult.new()
		hp -= payload.amount
		r.accepted = true
		r.final_amount = payload.amount
		return r


static func _dummy(x: float, z: float) -> DummyTarget:
	var d := DummyTarget.new()
	# Attach first, then position: global_position is only meaningful in-tree.
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(d)
	d.global_position = Vector3(x, 0, z)
	return d


static func suite() -> Array:
	var results: Array = []

	# --- Radial: inside damaged with linear falloff, outside untouched ---
	var center := _dummy(0, 0)
	var edge := _dummy(4, 0)
	var out := _dummy(9, 0)
	var victims := AreaDamage.apply_radial([center, edge, out], Vector3.ZERO, 5.0, 20.0, null, &"test")
	results.append({
		"name": "AreaDamage radial hits inside only, center hardest",
		"passed": victims.size() == 2 and center.hp < edge.hp and is_equal_approx(out.hp, 100.0),
		"why": "c=%.1f e=%.1f o=%.1f" % [center.hp, edge.hp, out.hp],
	})

	# --- Radial: FALLOFF_NONE is uniform ---
	var n1 := _dummy(0, 0)
	var n2 := _dummy(4.9, 0)
	AreaDamage.apply_radial([n1, n2], Vector3.ZERO, 5.0, 20.0, null, &"test", 0.0, false, AreaDamage.FALLOFF_NONE)
	results.append({
		"name": "AreaDamage FALLOFF_NONE deals uniform damage",
		"passed": is_equal_approx(n1.hp, n2.hp),
		"why": "",
	})

	# --- Radial: dead/excluded skipped ---
	var corpse := _dummy(0, 0)
	corpse.hp = 0.0
	var v2 := AreaDamage.apply_radial([corpse, n1], Vector3.ZERO, 5.0, 20.0, null, &"test", 0.0, false, AreaDamage.FALLOFF_NONE, [n1])
	results.append({"name": "AreaDamage skips dead + excluded", "passed": v2.is_empty(), "why": ""})

	# --- Line: corridor only ---
	var l_mid := _dummy(0, -4)
	var l_side := _dummy(3, -4)
	var l_behind := _dummy(0, 2)
	var v3 := AreaDamage.apply_line([l_mid, l_side, l_behind], Vector3.ZERO, Vector3(0, 0, -1), 6.0, 1.0, 10.0, null, &"test")
	results.append({
		"name": "AreaDamage line hits corridor, not flankers/behind",
		"passed": v3 == [l_mid],
		"why": "hits=%d" % v3.size(),
	})

	# --- Ring: band only ---
	var r_in := _dummy(1, 0)
	var r_band := _dummy(4, 0)
	var r_out := _dummy(9, 0)
	var v4 := AreaDamage.apply_ring([r_in, r_band, r_out], Vector3.ZERO, 2.0, 6.0, 10.0, null, &"test")
	results.append({"name": "AreaDamage ring hits band only", "passed": v4 == [r_band], "why": ""})

	# --- Chain: nearest-first with decay ---
	var c1 := _dummy(2, 0)
	var c2 := _dummy(4, 0)
	var c3 := _dummy(6, 0)
	var v5 := AreaDamage.apply_chain([c3, c1, c2], Vector3.ZERO, 10.0, 10.0, 2, 30.0, 0.5, null, &"test")
	results.append({
		"name": "AreaDamage chain jumps nearest-first with decay",
		"passed": v5 == [c1, c2] and is_equal_approx(c1.hp, 70.0) and is_equal_approx(c2.hp, 85.0) and is_equal_approx(c3.hp, 100.0),
		"why": "",
	})

	# --- CombatLog: ring cap + filters ---
	# CombatLog._init enforces a floor of 8 (maxi(capacity, 8)), so asking for 4
	# silently yields 8. Drive the eviction with the real capacity instead of a
	# value the class refuses to honour: 10 damage entries + 1 kill = 11 records
	# into an 8-slot ring, so the 3 oldest damage entries are dropped and 7 of the
	# original damage entries survive (7 * 10.0 == 70.0).
	var cap := 8
	var log := CombatLog.new(cap)
	for i in range(10):
		log.log_damage(&"sword", "grunt", 10.0, false, false)
	log.log_kill(&"grunt", 10)
	results.append({
		"name": "CombatLog caps at capacity, newest-first recent()",
		"passed": log.size() == cap and log.capacity() == cap
			and (log.recent(1)[0] as Dictionary)["kind"] == CombatLog.KIND_KILL,
		"why": "size=%d cap=%d" % [log.size(), log.capacity()],
	})
	results.append({
		"name": "CombatLog damage_by_source aggregates",
		"passed": absf(float(log.damage_by_source().get("sword", 0.0)) - 70.0) < 0.01,
		"why": str(log.damage_by_source()),
	})

	for d in [center, edge, out, n1, n2, corpse, l_mid, l_side, l_behind, r_in, r_band, r_out, c1, c2, c3]:
		d.get_parent().remove_child(d)
		d.free()
	return results
