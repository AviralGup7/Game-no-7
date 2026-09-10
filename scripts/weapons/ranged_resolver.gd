class_name RangedResolver
extends RefCounted

## Pure hitscan / projectile-launch math for ranged weapons.
## Computes muzzle transforms and per-projectile spread directions so the
## Projectile pool and enemy shooters share one deterministic implementation.
## No tree access, no autoloads.

const MAX_PROJECTILES_PER_SHOT := 12


## Evenly fanned directions across `spread_degrees` (0 spread = all identical).
## For N projectiles the offsets are symmetric around `facing`.
static func spread_directions(facing: Vector3, projectile_count: int, spread_degrees: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := clampi(projectile_count, 1, MAX_PROJECTILES_PER_SHOT)
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	var clamped_spread := maxf(spread_degrees, 0.0)
	if n == 1 or clamped_spread <= 0.0:
		for shot_idx in range(n):
			out.append(flat)
		return out
	var half := deg_to_rad(clamped_spread) * 0.5
	for i in range(n):
		var t := 0.0
		if n > 1:
			t = float(i) / float(n - 1) * 2.0 - 1.0  # -1..1
		out.append(flat.rotated(Vector3.UP, t * half))
	return out


## Jittered directions: deterministic per-shot random spread driven by an
## RngService stream (used for shotguns / enemy volleys).
static func jittered_directions(facing: Vector3, projectile_count: int, spread_degrees: float, rng: RngService, salt: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := clampi(projectile_count, 1, MAX_PROJECTILES_PER_SHOT)
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	var half := deg_to_rad(maxf(spread_degrees, 0.0)) * 0.5
	for i in range(n):
		var offset := 0.0
		if rng != null and half > 0.0:
			offset = rng.randf_range(salt, -half, half)
		out.append(flat.rotated(Vector3.UP, offset))
	return out


## Muzzle position: origin pushed forward so projectiles spawn clear of the
## wielder's own body, at chest height.
static func muzzle_position(origin: Vector3, facing: Vector3, forward_offset: float = 0.6, height: float = 1.1) -> Vector3:
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	return Vector3(origin.x + flat.x * forward_offset, origin.y + height, origin.z + flat.z * forward_offset)


## Lead a moving target: aim point = target pos + velocity * flight time.
## `target_velocity` is the flat (XZ) velocity; returns the desired direction.
static func lead_direction(muzzle: Vector3, target_pos: Vector3, target_velocity: Vector3, projectile_speed: float) -> Vector3:
	var speed := maxf(projectile_speed, 0.1)
	var to_target := target_pos - muzzle
	to_target.y = 0.0
	var flight := to_target.length() / speed
	var aim := target_pos + Vector3(target_velocity.x, 0.0, target_velocity.z) * flight - muzzle
	aim.y = 0.0
	if aim.length_squared() < 0.0001:
		return Vector3.FORWARD
	return aim.normalized()


## Maximum travel distance before the projectile expires.
static func max_travel_distance(projectile_speed: float, lifetime: float) -> float:
	return maxf(projectile_speed, 0.0) * maxf(lifetime, 0.0)


## Hitscan resolution against candidates along a ray (for instant weapons and
## enemy telegraphed beams). Returns [{target, distance}] sorted near-first.
static func hitscan(origin: Vector3, direction: Vector3, candidates: Array, max_distance: float, radius_tolerance: float = 0.4) -> Array:
	var hits: Array = []
	var dir := direction
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	for c in candidates:
		if c == null or not is_instance_valid(c) or not (c is Node3D):
			continue
		var damageable := c as Damageable
		if damageable == null:
			continue
		if not damageable.is_alive():
			continue
		var to: Vector3 = (c as Node3D).global_position - origin
		var along := to.dot(dir)
		if along < 0.0 or along > max_distance + maxf(damageable.get_hit_radius(), 0.0):
			continue
		var perpendicular := (to - dir * along).length()
		var radius := radius_tolerance + maxf(damageable.get_hit_radius(), 0.0)
		if perpendicular <= radius:
			hits.append({"target": c, "distance": along})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
	return hits

