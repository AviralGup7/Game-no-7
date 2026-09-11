extends RefCounted
## Native simulation of the shipped gun configs, independent of rendering clocks.

static func suite() -> Array:
	var results: Array = []
	for id in [&"gladius", &"sentinel_spear", &"stormhammer", &"sunbow", &"twinfangs", &"warreaxe", &"ember_scepter", &"moonlance", &"venom_chain"]:
		var cfg := load("res://data/weapons/%s.tres" % id) as WeaponConfig
		results.append({"name": "valid firearm: " + String(id), "passed": cfg != null and cfg.validate().is_empty() and cfg.is_ranged() and not cfg.is_melee() and cfg.has_ammo()})
		if cfg == null:
			continue
		var weapon := WeaponInstance.new(cfg, 71)
		var shots := 0
		var started_reload := false
		# Fixed 120 Hz simulation: hold fire until the first empty-magazine reload.
		for frame in range(12000):
			weapon.try_start_attack()
			if weapon.is_reloading():
				started_reload = true
				break
			if weapon.tick(1.0 / 120.0):
				shots += 1
		results.append({"name": "magazine resolves exactly once per round: " + String(id), "passed": started_reload and shots == cfg.ammo_per_magazine and weapon.ammo == 0})
		results.append({"name": "reload rejects fire: " + String(id), "passed": weapon.try_start_attack() == 0})
		weapon.tick(cfg.reload_seconds + 0.01)
		results.append({"name": "reload refills and allows continued fire: " + String(id), "passed": weapon.is_ready() and weapon.ammo == cfg.ammo_per_magazine and weapon.try_start_attack() == 1})
		weapon.cancel_attack()
		results.append({"name": "cancel never resolves a delayed round: " + String(id), "passed": not weapon.tick(2.0)})
	var down := Vector3(0, -0.3, -1).normalized()
	var fan := RangedResolver.aimed_directions(down, 3, 20.0)
	results.append({"name": "assisted shot preserves drone elevation", "passed": fan.size() == 3 and fan[1].is_equal_approx(down) and fan[0].y < 0 and fan[2].y < 0})
	results.append({"name": "empty direction has safe forward fallback", "passed": RangedResolver.aimed_directions(Vector3.ZERO, 1, 0)[0] == Vector3.FORWARD})
	return results
