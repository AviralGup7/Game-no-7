extends RefCounted

## Headless unit tests for DropTable pity/eligibility, EliteAffix math and
## SpawnPatterns geometry. All pure/deterministic.

static func _pickup(id: String, weight: float, min_wave: int) -> PickupConfig:
	var c := PickupConfig.new()
	c.pickup_id = StringName(id)
	c.drop_weight = weight
	c.min_wave = min_wave
	return c


static func suite() -> Array:
	var results: Array = []

	# --- DropTable: boss always drops, wave gates respected ---
	var table := DropTable.new([_pickup("a", 1.0, 1), _pickup("b", 1.0, 5)])
	var rng := RngService.new(31)
	var boss_drops := table.roll_drops(&"warlord", 10, false, true, 0.0, rng)
	results.append({
		"name": "DropTable boss drops guaranteed",
		"passed": boss_drops.size() == DropTable.BOSS_GUARANTEED_DROPS,
		"why": str(boss_drops),
	})
	var early_ok := true
	for i in range(30):
		for id in table.roll_drops(&"basic", 1, false, false, 0.0, rng):
			if id == &"b":
				early_ok = false
	results.append({"name": "DropTable respects min_wave gates", "passed": early_ok, "why": ""})

	# --- DropTable: pity forces a drop after dry streak ---
	var pity := DropTable.new([_pickup("a", 1.0, 1)])
	var pity_rng := RngService.new(777)
	var saw_drop := false
	for i in range(DropTable.PITY_KILLS_WITHOUT_DROP + 2):
		# luck -1 cannot go below 0 chance... base chance may still hit; pity
		# guarantees at least one drop across the window regardless.
		if not pity.roll_drops(&"basic", 1, false, false, -1.0, pity_rng).is_empty():
			saw_drop = true
	results.append({"name": "DropTable pity guarantees a drop", "passed": saw_drop, "why": ""})

	# --- EliteAffix: deterministic distinct rolls ---
	var aff_a := EliteAffix.roll_affixes(&"basic", 6, 999, 3)
	var aff_b := EliteAffix.roll_affixes(&"basic", 6, 999, 3)
	var distinct := aff_a.size() == 1 or aff_a[0] != aff_a[1]
	results.append({
		"name": "EliteAffix rolls deterministic + distinct",
		"passed": aff_a == aff_b and aff_a.size() >= 1 and aff_a.size() <= 2 and distinct,
		"why": str(aff_a),
	})

	# --- EliteAffix: combine math ---
	var combo := EliteAffix.combine([EliteAffix.BRUISER, EliteAffix.SWIFT])
	results.append({
		"name": "EliteAffix combine multiplies stats, maxes resist",
		"passed": float(combo["hp"]) > 1.0 and float(combo["speed"]) > 1.0
			and is_equal_approx(float(combo["knockback_resist"]), 0.4),
		"why": str(combo),
	})

	# --- EliteAffix: gates + chance curve ---
	var cfg := EnemyConfig.new()
	cfg.elite_eligible = true
	results.append({
		"name": "EliteAffix gated before wave 3, capped at 25%",
		"passed": not EliteAffix.elite_allowed(cfg, 2) and EliteAffix.elite_allowed(cfg, 3)
			and is_equal_approx(EliteAffix.elite_chance(2), 0.0)
			and EliteAffix.elite_chance(40) <= 0.25,
		"why": "",
	})
	cfg.elite_eligible = false
	results.append({"name": "EliteAffix respects elite_eligible=false", "passed": not EliteAffix.elite_allowed(cfg, 9), "why": ""})

	# --- SpawnPatterns: counts, bounds, determinism ---
	var p1 := SpawnPatterns.positions_for(SpawnPatterns.PATTERN_RING, 8, 12.0, Vector3.ZERO, 5, 1)
	var p2 := SpawnPatterns.positions_for(SpawnPatterns.PATTERN_RING, 8, 12.0, Vector3.ZERO, 5, 1)
	var bounded := p1.size() == 8
	for p in p1:
		if absf(p.x) > 12.0 or absf(p.z) > 12.0 or absf(p.y) > 0.001:
			bounded = false
	results.append({
		"name": "SpawnPatterns ring deterministic + in-bounds",
		"passed": bounded and p1 == p2,
		"why": "",
	})

	# --- SpawnPatterns: player safe radius enforced ---
	var player := Vector3(11, 0, 11)
	var pts := SpawnPatterns.positions_for(SpawnPatterns.PATTERN_SCATTER, 12, 12.0, player, 5, 2)
	var safe := true
	for p in pts:
		if Vector2(p.x - player.x, p.z - player.z).length() < SpawnPatterns.PLAYER_SAFE_RADIUS - 0.01:
			safe = false
	results.append({"name": "SpawnPatterns enforces player safe radius", "passed": safe, "why": ""})

	# --- SpawnPatterns: gate is a single far slot ---
	var gate := SpawnPatterns.positions_for(SpawnPatterns.PATTERN_GATE, 1, 12.0, Vector3(10, 0, 10), 1, 1)
	results.append({
		"name": "SpawnPatterns gate spawns far from player",
		"passed": gate.size() == 1 and gate[0].distance_to(Vector3(10, 0, 10)) > 12.0,
		"why": str(gate),
	})

	# --- SpawnPatterns: wave pattern varies without repeating ---
	var prev := SpawnPatterns.PATTERN_RING
	var varied := SpawnPatterns.pattern_for_wave(7, 42, prev)
	results.append({"name": "SpawnPatterns avoids repeating previous", "passed": varied != prev, "why": String(varied)})

	return results
