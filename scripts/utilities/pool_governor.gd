class_name PoolGovernor
extends RefCounted

## Pushes the PerformanceMonitor's per-tier live caps onto the run pools.
##
## WaveManager already mins the authored simultaneous-enemy cap against
## `max_simultaneous_enemies()`. This does the same for projectiles, pickups,
## VFX bursts/rings, floating combat text and spatial voices so a LOW phone
## cannot keep a HIGH-tier volley in the air. Combat damage/pierce/speed are
## not scaled here.
##
## Audio is reached through the SpatialVoices child so this file never names
## the AudioManager autoload identifier.

static func apply(monitor: PerformanceMonitor, from: Node) -> Dictionary:
	var report := empty_report()
	if monitor == null or from == null or not is_instance_valid(from) or not from.is_inside_tree():
		return report
	var tree := from.get_tree()
	if tree == null:
		return report
	var budgets := monitor.pool_budgets()
	var proj_cap := int(budgets.get("projectiles", 1))
	var pickup_cap := int(budgets.get("pickups", 1))
	var burst_cap := int(budgets.get("vfx_bursts", 1))
	var ring_cap := int(budgets.get("vfx_rings", 1))
	var voice_cap := int(budgets.get("spatial_voices", 1))
	var number_cap := int(budgets.get("damage_numbers", 1))
	_apply_projectiles(tree, proj_cap, report)
	_apply_pickups(tree, pickup_cap, report)
	_apply_effects(tree, burst_cap, ring_cap, report)
	_apply_numbers(tree, number_cap, report)
	_apply_spatial(tree, voice_cap, report)
	return report


static func empty_report() -> Dictionary:
	return {
		"projectiles": -1,
		"pickups": -1,
		"bursts": -1,
		"rings": -1,
		"voices": -1,
		"numbers": -1,
	}


static func _apply_projectiles(tree: SceneTree, cap: int, report: Dictionary) -> void:
	for n in tree.get_nodes_in_group(String(RunIsolation.GROUP_PROJECTILES)):
		var pool := n as ProjectilePool
		if pool == null:
			continue
		pool.apply_budget(cap)
		report["projectiles"] = cap


static func _apply_pickups(tree: SceneTree, cap: int, report: Dictionary) -> void:
	for n in tree.get_nodes_in_group(String(RunIsolation.GROUP_PICKUPS)):
		var pickups := n as PickupManager
		if pickups == null:
			continue
		pickups.apply_budget(cap)
		report["pickups"] = cap


static func _apply_effects(tree: SceneTree, burst_cap: int, ring_cap: int, report: Dictionary) -> void:
	for n in tree.get_nodes_in_group(String(RunIsolation.GROUP_EFFECTS)):
		var fx := n as EffectDirector
		if fx == null:
			continue
		fx.apply_budget(burst_cap, ring_cap)
		report["bursts"] = burst_cap
		report["rings"] = ring_cap


static func _apply_numbers(tree: SceneTree, cap: int, report: Dictionary) -> void:
	for n in tree.get_nodes_in_group(String(RunIsolation.GROUP_NUMBERS)):
		var numbers := n as DamageNumberLayer
		if numbers == null:
			continue
		numbers.set_max_live(cap)
		report["numbers"] = cap


static func _apply_spatial(tree: SceneTree, voice_cap: int, report: Dictionary) -> void:
	if tree == null or tree.root == null:
		return
	var audio_node := tree.root.get_node_or_null(RunIsolation.AUDIO_PATH)
	if audio_node == null:
		return
	var spatial := audio_node.get_node_or_null(RunIsolation.SPATIAL_CHILD) as SpatialVoicePool
	if spatial == null:
		return
	spatial.apply_budget(voice_cap)
	report["voices"] = voice_cap


## Caps must never grow as the tier drops. Used by the headless suite.
static func caps_are_monotonic(monitor: PerformanceMonitor) -> bool:
	if monitor == null:
		return false
	var saved := monitor.get_tier()
	var prev := {
		"projectiles": 1 << 30,
		"pickups": 1 << 30,
		"vfx_bursts": 1 << 30,
		"vfx_rings": 1 << 30,
		"spatial_voices": 1 << 30,
		"damage_numbers": 1 << 30,
		"enemies": 1 << 30,
	}
	var ok := true
	for tier in range(PerformanceMonitor.TIER_ULTRA, PerformanceMonitor.TIER_LOW - 1, -1):
		monitor.set_tier(tier)
		var now := monitor.pool_budgets()
		for key in prev.keys():
			var value := int(now.get(key, 0))
			if value < 1 or value > int(prev[key]):
				ok = false
				break
			prev[key] = value
		if not ok:
			break
	monitor.set_tier(saved)
	return ok


## Floor/ceiling pins so a typo cannot publish a 0-cap or a cap above the
## pool's physical size. Independent of the current tier.
static func caps_are_bounded(monitor: PerformanceMonitor) -> bool:
	if monitor == null:
		return false
	var saved := monitor.get_tier()
	var ok := true
	for tier in range(PerformanceMonitor.TIER_LOW, PerformanceMonitor.TIER_ULTRA + 1):
		monitor.set_tier(tier)
		var b := monitor.pool_budgets()
		if int(b["projectiles"]) > 48 or int(b["projectiles"]) < 4:
			ok = false
		if int(b["pickups"]) > 24 or int(b["pickups"]) < 4:
			ok = false
		# Physical ceilings (bursts 10, rings 14, voices 16); literals here
		# keep this file from pulling those scripts into the unit harness.
		if int(b["vfx_bursts"]) > 10 or int(b["vfx_bursts"]) < 2:
			ok = false
		if int(b["vfx_rings"]) > 14 or int(b["vfx_rings"]) < 2:
			ok = false
		if int(b["spatial_voices"]) > 16 or int(b["spatial_voices"]) < 2:
			ok = false
		if int(b["damage_numbers"]) > 48 or int(b["damage_numbers"]) < 4:
			ok = false
		if int(b["enemies"]) > 32 or int(b["enemies"]) < 4:
			ok = false
		if not ok:
			break
	monitor.set_tier(saved)
	return ok
