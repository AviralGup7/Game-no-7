class_name CombatQuery
## Pure, deterministic melee/arc query helpers. No scene state, no RNG: given an
## origin, a facing direction and a candidate list, return which targets fall inside
## the attack arc at a range. Unit-testable headlessly; used by the AttackController
## to resolve real hits each swing.

## Returns the subset of `targets` that:
##  - are alive (have is_alive() == true, or no is_alive -> treated alive),
##  - lie within `range` of `origin`,
##  - lie within `half_angle_degrees` of `forward` (measured from the target offset).
static func find_targets_in_arc(
	origin: Vector3,
	forward: Vector3,
	targets: Array,
	range: float,
	half_angle_degrees: float
) -> Array:
	var out: Array = []
	var fwd := forward
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var cos_limit := cos(deg_to_rad(maxf(half_angle_degrees, 0.0)))
	for t in targets:
		if not is_valid_target(t):
			continue
		var node := t as Node3D
		var offset := Vector3.ZERO
		if node != null:
			offset = (node.global_position - origin) * Vector3(1, 0, 1)
		var dist_sq := offset.length_squared()
		if dist_sq > range * range:
			continue
		if dist_sq < 0.0001:
			out.append(t)
			continue
		var dir := offset.normalized()
		if fwd.dot(dir) >= cos_limit:
			out.append(t)
	return out


static func is_valid_target(target: Node) -> bool:
	if not is_instance_valid(target):
		return false
	if target.has_method("is_alive") and not bool(target.call("is_alive")):
		return false
	if not target is Node3D:
		return false
	return true


## Optional second pass so knockback/feedback can read per-hit geometry.
static func build_hit_offset(origin: Vector3, target: Node) -> Vector3:
	if target is Node3D:
		return (target.global_position - origin) * Vector3(1, 0, 1)
	return Vector3.ZERO
