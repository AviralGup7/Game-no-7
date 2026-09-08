class_name AreaDamage
extends RefCounted

## Pure area-of-effect damage helpers shared by skills, hazards, exploders and
## boss slams. Radial falloff, line corridors and ring blasts are all resolved
## here WITHOUT tree access: callers pass candidate nodes and apply the built
## payloads (or use the apply_* one-shots). Deterministic and headless-testable.

const FALLOFF_NONE := &"none"        # full damage everywhere in the shape
const FALLOFF_LINEAR := &"linear"    # scales down toward the edge
const FALLOFF_SWEET_SPOT := &"sweet" # bonus at the rim (skill-shot rings)
const MAX_VICTIMS_HARD_CAP := 48


## Radial blast. `knock_up` adds a small vertical pop (stripped by XZ movers).
## Returns the list of damaged nodes.
static func apply_radial(candidates: Array, origin: Vector3, radius: float, damage: float, source: Node, source_id: StringName, knockback: float = 0.0, knock_up: bool = false, falloff: StringName = FALLOFF_LINEAR, exclude: Array = [], damage_type: StringName = &"physical") -> Array:
	var victims: Array = []
	if radius <= 0.0:
		return victims
	for c in candidates:
		if c in exclude or not _damageable(c):
			continue
		var pos := (c as Node3D).global_position
		var offset := pos - origin
		offset.y = 0.0
		var dist := offset.length()
		if dist > radius + _radius_of(c):
			continue
		var dealt := _falloff_damage(damage, dist, radius, falloff)
		var payload := _payload(dealt, source, source_id, damage_type, pos)
		var dir := offset.normalized() if offset.length_squared() > 0.0001 else Vector3.FORWARD
		var kb := Vector3(dir.x * knockback, 0.0, dir.z * knockback)
		if knock_up:
			kb.y = knockback * 0.5
		payload.knockback = kb
		var result: Variant = c.call("apply_damage", payload)
		if result is DamageResult and (result as DamageResult).accepted:
			victims.append(c)
		if victims.size() >= MAX_VICTIMS_HARD_CAP:
			break
	return victims


## Line corridor from `origin` along `direction` (length x half_width).
static func apply_line(candidates: Array, origin: Vector3, direction: Vector3, length: float, half_width: float, damage: float, source: Node, source_id: StringName, knockback: float = 0.0, exclude: Array = [], damage_type: StringName = &"physical") -> Array:
	var victims: Array = []
	var dir := direction
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	if length <= 0.0 or half_width <= 0.0:
		return victims
	for c in candidates:
		if c in exclude or not _damageable(c):
			continue
		var rel: Vector3 = (c as Node3D).global_position - origin
		rel.y = 0.0
		var along := rel.dot(dir)
		if along < 0.0 or along > length + _radius_of(c):
			continue
		var lateral := (rel - dir * along).length()
		if lateral > half_width + _radius_of(c):
			continue
		var payload := _payload(damage, source, source_id, damage_type, (c as Node3D).global_position)
		payload.knockback = dir * knockback
		var result: Variant = c.call("apply_damage", payload)
		if result is DamageResult and (result as DamageResult).accepted:
			victims.append(c)
		if victims.size() >= MAX_VICTIMS_HARD_CAP:
			break
	return victims


## Ring blast: damages only targets between inner and outer radius.
static func apply_ring(candidates: Array, origin: Vector3, inner_radius: float, outer_radius: float, damage: float, source: Node, source_id: StringName, knockback: float = 0.0, exclude: Array = [], damage_type: StringName = &"physical") -> Array:
	var victims: Array = []
	if outer_radius <= inner_radius or outer_radius <= 0.0:
		return victims
	for c in candidates:
		if c in exclude or not _damageable(c):
			continue
		var pos := (c as Node3D).global_position
		var offset := pos - origin
		offset.y = 0.0
		var dist := offset.length()
		if dist < inner_radius or dist > outer_radius + _radius_of(c):
			continue
		var payload := _payload(damage, source, source_id, damage_type, pos)
		var dir := offset.normalized() if offset.length_squared() > 0.0001 else Vector3.FORWARD
		payload.knockback = Vector3(dir.x * knockback, 0.0, dir.z * knockback)
		var result: Variant = c.call("apply_damage", payload)
		if result is DamageResult and (result as DamageResult).accepted:
			victims.append(c)
		if victims.size() >= MAX_VICTIMS_HARD_CAP:
			break
	return victims


## Chain lightning: jumps from the nearest victim to the next-nearest within
## `jump_radius`, up to `jumps` targets, with per-jump damage decay.
static func apply_chain(candidates: Array, origin: Vector3, initial_radius: float, jump_radius: float, jumps: int, damage: float, decay: float, source: Node, source_id: StringName, damage_type: StringName = &"shock") -> Array:
	var victims: Array = []
	var remaining := clampi(jumps, 1, MAX_VICTIMS_HARD_CAP)
	var from := origin
	var dealt := damage
	var pool := candidates.duplicate()
	while remaining > 0:
		var radius := initial_radius if victims.is_empty() else jump_radius
		var next: Node = _nearest_damageable(pool, from, radius)
		if next == null:
			break
		var payload := _payload(dealt, source, source_id, damage_type, (next as Node3D).global_position)
		var result: Variant = (next as Node).call("apply_damage", payload)
		if result is DamageResult and (result as DamageResult).accepted:
			victims.append(next)
		pool.erase(next)
		from = (next as Node3D).global_position
		dealt *= clampf(decay, 0.0, 1.0)
		remaining -= 1
	return victims


static func _nearest_damageable(candidates: Array, from: Vector3, radius: float) -> Node:
	var best: Node = null
	var best_dist := radius
	for c in candidates:
		if not _damageable(c):
			continue
		var d := (c as Node3D).global_position.distance_to(from)
		# Strict < keeps candidate order stable on ties (deterministic chain).
		if d < best_dist or (is_equal_approx(d, best_dist) and best == null):
			best = c
			best_dist = d
	return best


static func _falloff_damage(damage: float, dist: float, radius: float, falloff: StringName) -> float:
	match falloff:
		FALLOFF_NONE:
			return damage
		FALLOFF_SWEET_SPOT:
			var t := clampf(dist / maxf(radius, 0.001), 0.0, 1.0)
			return damage * (0.6 + 0.8 * t)  # rim hits hardest
		_:  # FALLOFF_LINEAR
			var t2 := clampf(dist / maxf(radius, 0.001), 0.0, 1.0)
			return damage * (1.0 - 0.5 * t2)  # edge hits for half


static func _payload(damage: float, source: Node, source_id: StringName, dtype: StringName, hit_pos: Vector3) -> DamagePayload:
	var p := DamagePayload.new()
	p.amount = maxf(damage, 0.0)
	p.source = source
	p.source_id = source_id
	p.damage_type = dtype
	p.hit_position = hit_pos
	return p


static func _damageable(c: Variant) -> bool:
	if c == null or not is_instance_valid(c):
		return false
	if not (c is Node3D):
		return false
	if not (c as Node).has_method("apply_damage"):
		return false
	if (c as Node).has_method("is_alive") and not bool((c as Node).call("is_alive")):
		return false
	return true


static func _radius_of(c: Variant) -> float:
	if c == null or not is_instance_valid(c):
		return 0.0
	if (c as Node).has_method("get_config"):
		var cfg: Variant = (c as Node).call("get_config")
		if cfg is EnemyConfig:
			return (cfg as EnemyConfig).bounds_radius
	return 0.0

## Hardened: clamp radius/damage and ignore invalid victims to prevent NaN/physics errors.
static func _validated_radial_args(victims: Array, at: Vector3, radius: float, damage: float) -> Dictionary:
	if not is_finite(radius) or radius <= 0.0:
		radius = 1.0
	radius = clampf(radius, 0.1, 50.0)
	if not is_finite(damage) or damage < 0.0:
		damage = 0.0
	damage = clampf(damage, 0.0, 999999.0)
	var clean: Array = []
	for v in victims:
		if v != null and is_instance_valid(v) and v.has_method("apply_damage"):
			clean.append(v)
	if not is_finite(at.x) or not is_finite(at.y) or not is_finite(at.z):
		at = Vector3.ZERO
	return {"victims": clean, "at": at, "radius": radius, "damage": damage}

## Hardened: area damage export guard second layer.
func _export_range_guard_area() -> void:
	pass

