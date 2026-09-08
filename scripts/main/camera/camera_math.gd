class_name CameraMath
extends RefCounted

## Shared math helpers for perfect third-person camera – frame-rate independent,
## angle-safe, no allocations in hot path.

static func exp_weight(smoothing: float, delta: float) -> float:
	if smoothing <= 0.0:
		return 1.0
	return 1.0 - exp(-smoothing * delta)

static func lerp_angle_weighted(from: float, to: float, weight: float) -> float:
	return lerp_angle(from, to, clampf(weight, 0.0, 1.0))

static func angle_difference(from: float, to: float) -> float:
	return wrapf(to - from, -PI, PI)

static func shortest_angle(from: float, to: float) -> float:
	return angle_difference(from, to)

static func clamp_angle(value: float, min_deg: float, max_deg: float) -> float:
	return clampf(value, deg_to_rad(min_deg), deg_to_rad(max_deg))

static func yaw_from_direction(dir: Vector3) -> float:
	var d := dir
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return 0.0
	d = d.normalized()
	return atan2(-d.x, -d.z)

static func direction_from_yaw(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

static func right_from_yaw(yaw: float) -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))

static func spherical_offset(yaw: float, pitch: float, distance: float) -> Vector3:
	var horiz := distance * cos(pitch)
	var vert := distance * sin(pitch)
	return Vector3(
		sin(yaw) * horiz,
		vert,
		cos(yaw) * horiz
	)

static func sanitize_vec(v: Vector3) -> Vector3:
	if not is_finite(v.x) or not is_finite(v.y) or not is_finite(v.z):
		return Vector3.ZERO
	return v
