extends RefCounted

## Deterministic budget table for the Aim 6 pool governor.
##
## No tree, no autoload identifiers: PerformanceMonitor is the only production
## script this suite instantiates. PoolGovernor.apply() walks groups and is
## covered by the NODE suite (test_run_isolation.gd).

static func suite() -> Array:
	var results: Array = []
	var saved_max_fps := Engine.max_fps
	var m := PerformanceMonitor.new()

	results.append(_case(
		"pool_governor suite loads the monitor",
		m != null,
		"PerformanceMonitor.new() returned null"))

	_pin_table(results, m)
	_pin_monotonic(results, m)
	_pin_bounds(results, m)
	_pin_snapshot(results, m)
	_pin_particle_scale_untouched(results, m)

	m.free()
	Engine.max_fps = saved_max_fps
	return results


static func _pin_table(results: Array, m: PerformanceMonitor) -> void:
	var expected := {
		PerformanceMonitor.TIER_ULTRA: {
			"projectiles": 48, "pickups": 24, "vfx_bursts": 10, "vfx_rings": 14,
			"spatial_voices": 16, "damage_numbers": 48, "enemies": 28,
		},
		PerformanceMonitor.TIER_HIGH: {
			"projectiles": 32, "pickups": 18, "vfx_bursts": 8, "vfx_rings": 10,
			"spatial_voices": 12, "damage_numbers": 32, "enemies": 22,
		},
		PerformanceMonitor.TIER_MEDIUM: {
			"projectiles": 20, "pickups": 12, "vfx_bursts": 6, "vfx_rings": 8,
			"spatial_voices": 8, "damage_numbers": 20, "enemies": 16,
		},
		PerformanceMonitor.TIER_LOW: {
			"projectiles": 12, "pickups": 8, "vfx_bursts": 4, "vfx_rings": 5,
			"spatial_voices": 4, "damage_numbers": 10, "enemies": 10,
		},
	}
	for tier in expected.keys():
		m.set_tier(int(tier))
		var got := m.pool_budgets()
		var want: Dictionary = expected[tier]
		var ok := true
		var why := "tier=%d" % int(tier)
		for key in want.keys():
			if int(got.get(key, -1)) != int(want[key]):
				ok = false
				why += " %s got=%s want=%s" % [str(key), str(got.get(key)), str(want[key])]
		results.append(_case("budget table at %s" % m.get_tier_name(), ok, why))
		results.append(_case(
			"accessor agreement at %s" % m.get_tier_name(),
			m.max_projectiles() == int(want["projectiles"])
			and m.max_pickups() == int(want["pickups"])
			and m.max_vfx_bursts() == int(want["vfx_bursts"])
			and m.max_vfx_rings() == int(want["vfx_rings"])
			and m.max_spatial_voices() == int(want["spatial_voices"])
			and m.max_damage_numbers() == int(want["damage_numbers"])
			and m.max_simultaneous_enemies() == int(want["enemies"]),
			"accessors drifted from pool_budgets()"))


static func _pin_monotonic(results: Array, m: PerformanceMonitor) -> void:
	var keys := ["projectiles", "pickups", "vfx_bursts", "vfx_rings", "spatial_voices", "damage_numbers", "enemies"]
	var prev: Dictionary = {}
	for key in keys:
		prev[key] = 1 << 30
	var ok := true
	var why := ""
	for tier in range(PerformanceMonitor.TIER_ULTRA, PerformanceMonitor.TIER_LOW - 1, -1):
		m.set_tier(tier)
		var now := m.pool_budgets()
		for key in keys:
			var value := int(now[key])
			if value < 1 or value > int(prev[key]):
				ok = false
				why = "%s rose or zeroed at tier %d (%d -> %d)" % [key, tier, int(prev[key]), value]
				break
			prev[key] = value
		if not ok:
			break
	results.append(_case("every pool cap is monotone as the tier drops", ok, why))


static func _pin_bounds(results: Array, m: PerformanceMonitor) -> void:
	var ok := true
	var why := ""
	for tier in range(PerformanceMonitor.TIER_LOW, PerformanceMonitor.TIER_ULTRA + 1):
		m.set_tier(tier)
		var b := m.pool_budgets()
		if int(b["projectiles"]) > 48 or int(b["projectiles"]) < 4:
			ok = false
			why = "projectiles out of [4,48] at %s" % m.get_tier_name()
		if int(b["pickups"]) > 24 or int(b["pickups"]) < 4:
			ok = false
			why = "pickups out of [4,24] at %s" % m.get_tier_name()
		if int(b["vfx_bursts"]) > 10 or int(b["vfx_bursts"]) < 2:
			ok = false
			why = "bursts out of [2,10] at %s" % m.get_tier_name()
		if int(b["vfx_rings"]) > 14 or int(b["vfx_rings"]) < 2:
			ok = false
			why = "rings out of [2,14] at %s" % m.get_tier_name()
		if int(b["spatial_voices"]) > 16 or int(b["spatial_voices"]) < 2:
			ok = false
			why = "voices out of [2,16] at %s" % m.get_tier_name()
		if not ok:
			break
	results.append(_case("caps stay inside the physical pool ceilings", ok, why))


static func _pin_snapshot(results: Array, m: PerformanceMonitor) -> void:
	m.set_tier(PerformanceMonitor.TIER_MEDIUM)
	var snap := m.get_debug_snapshot()
	results.append(_case(
		"debug snapshot carries the new pool caps",
		int(snap.get("max_projectiles", -1)) == m.max_projectiles()
		and int(snap.get("max_pickups", -1)) == m.max_pickups()
		and int(snap.get("max_vfx_bursts", -1)) == m.max_vfx_bursts()
		and int(snap.get("max_vfx_rings", -1)) == m.max_vfx_rings()
		and int(snap.get("max_spatial_voices", -1)) == m.max_spatial_voices()
		and int(snap.get("max_damage_numbers", -1)) == m.max_damage_numbers()
		and int(snap.get("max_simultaneous_enemies", -1)) == m.max_simultaneous_enemies(),
		str(snap)))


static func _pin_particle_scale_untouched(results: Array, m: PerformanceMonitor) -> void:
	m.set_tier(PerformanceMonitor.TIER_LOW)
	var low := m.particle_budget_scale()
	m.set_tier(PerformanceMonitor.TIER_ULTRA)
	var ultra := m.particle_budget_scale()
	results.append(_case(
		"particle_budget_scale is unchanged (VFX amount, not pool cap)",
		is_equal_approx(low, 0.25) and is_equal_approx(ultra, 1.0),
		"low=%s ultra=%s" % [str(low), str(ultra)]))


static func _case(name: String, passed: bool, why: String = "") -> Dictionary:
	return {"name": name, "passed": passed, "why": why}
