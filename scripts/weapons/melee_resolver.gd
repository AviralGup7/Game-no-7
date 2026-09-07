class_name MeleeResolver
extends RefCounted

## Pure melee-sweep hit resolution.
## Given a wielder transform, a WeaponInstance and candidate targets, it selects
## victims inside range + arc (nearest-first, honouring max_targets) and builds
## per-target DamagePayloads with directional knockback. No tree access, no
## autoloads: fully deterministic and headless-testable. The caller (usually
## AttackController/WeaponManager) applies the payloads via `apply_damage`.

const MAX_ARC_TARGETS_HARD_CAP := 32


## Ranked candidate list: everyone inside range+arc, nearest first.
static func select_targets(origin: Vector3, facing: Vector3, candidates: Array, weapon: WeaponInstance) -> Array:
	var out: Array = []
	if weapon == null or weapon.config == null:
		return out
	var flat_facing := Vector3(facing.x, 0.0, facing.z)
	if flat_facing.length_squared() < 0.0001:
		flat_facing = Vector3.FORWARD
	flat_facing = flat_facing.normalized()
	var weapon_range := weapon.effective_range()
	var half_angle := deg_to_rad(weapon.config.arc_degrees * 0.5)
	var scored: Array = []
	for c in candidates:
		if not _is_valid_target(c):
			continue
		var target := c as Node3D
		var offset := target.global_position - origin
		offset.y = 0.0
		var dist := offset.length()
		if dist > weapon_range + _target_radius(c):
			continue
		if dist > 0.001 and half_angle < PI - 0.001:
			var dir := offset / dist
			var angle := flat_facing.angle_to(dir)
			if angle > half_angle:
				continue
		scored.append({"node": c, "dist": dist})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	var limit := weapon.config.max_targets
	if limit <= 0:
		limit = MAX_ARC_TARGETS_HARD_CAP
	limit = mini(limit, MAX_ARC_TARGETS_HARD_CAP)
	for s in scored:
		if out.size() >= limit:
			break
		out.append(s["node"])
	return out


static func _is_valid_target(c: Variant) -> bool:
	if c == null or not is_instance_valid(c):
		return false
	if not (c is Node3D):
		return false
	if not c.has_method("apply_damage"):
		return false
	if c.has_method("is_alive") and not bool(c.call("is_alive")):
		return false
	return true


## Extra reach granted by bulky targets (reads EnemyConfig.bounds_radius when
## available; 0 otherwise).
static func _target_radius(c: Variant) -> float:
	if c != null and (c as Node).has_method("get_config"):
		var cfg: Variant = (c as Node).call("get_config")
		if cfg is EnemyConfig:
			return (cfg as EnemyConfig).bounds_radius
	return 0.0


## Build the knockback vector for one victim: away from the wielder plus a small
## upward pop for game feel (Y is stripped by most movers; harmless elsewhere).
static func knockback_for(origin: Vector3, target_pos: Vector3, strength: float) -> Vector3:
	var offset := target_pos - origin
	offset.y = 0.0
	if offset.length_squared() < 0.0001:
		offset = Vector3.FORWARD
	var dir := offset.normalized()
	return Vector3(dir.x * strength, 0.0, dir.z * strength)


## Resolve one swing: select victims and build their payloads. `was_crit` is
## rolled once per swing by the caller (WeaponInstance.roll_crit) so every
## victim in a cleave shares the crit outcome — readable and fair.
static func resolve_swing(origin: Vector3, facing: Vector3, candidates: Array, weapon: WeaponInstance, source: Node, was_crit: bool) -> Array:
	var out: Array = []
	var victims := select_targets(origin, facing, candidates, weapon)
	if victims.is_empty():
		return out
	var base_damage := weapon.effective_damage()
	var knockback := weapon.effective_knockback()
	if was_crit and weapon.config != null:
		base_damage *= weapon.config.crit_multiplier
	for v in victims:
		var payload := DamagePayload.new()
		payload.amount = base_damage
		payload.source = source
		payload.source_id = weapon.config.weapon_id if weapon.config != null else &"melee"
		payload.damage_type = &"physical"
		payload.can_crit = false  # already resolved at swing level
		payload.was_critical = was_crit
		payload.critical_multiplier = weapon.config.crit_multiplier if weapon.config != null else 1.0
		var tpos := (v as Node3D).global_position
		payload.hit_position = Vector3(tpos.x, origin.y + 0.9, tpos.z)
		payload.knockback = knockback_for(origin, tpos, knockback)
		payload.metadata["combo_step"] = weapon.combo_step
		payload.metadata["victim_index"] = out.size()
		out.append({"target": v, "payload": payload})
	return out


## Convenience: resolve AND apply in one call. Returns the list of DamageResults
## paired with their targets: [{target, result}]. Skips invalid payloads.
static func resolve_and_apply(origin: Vector3, facing: Vector3, candidates: Array, weapon: WeaponInstance, source: Node, was_crit: bool) -> Array:
	var applied: Array = []
	for entry in resolve_swing(origin, facing, candidates, weapon, source, was_crit):
		var target: Variant = entry["target"]
		var payload: DamagePayload = entry["payload"]
		if not payload.is_valid():
			continue
		var result: Variant = target.call("apply_damage", payload)
		if result is DamageResult:
			applied.append({"target": target, "result": result})
	return applied


## Count how many candidates WOULD be hit (for UI telegraphs / AI decisions).
static func count_threatened(origin: Vector3, facing: Vector3, candidates: Array, weapon: WeaponInstance) -> int:
	return select_targets(origin, facing, candidates, weapon).size()
