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
	if not is_finite(yaw) or not is_finite(pitch) or not is_finite(distance):
		return Vector3.ZERO
	var horiz := distance * cos(pitch)
	var vert := distance * sin(pitch)
	var offset := Vector3(
		sin(yaw) * horiz,
		vert,
		cos(yaw) * horiz
	)
	return offset if is_finite_v3(offset) else Vector3.ZERO


## Pull `cam` toward `focus` until XZ sits inside a square of half-extent `half`.
## Used so the boom never crosses the arena walls into the HDRI skybox, even when
## collision queries miss (origin already inside a collider, or no World3D).
static func shorten_arm_to_box(focus: Vector3, cam: Vector3, half: float) -> Vector3:
	if not is_finite_v3(focus) or not is_finite_v3(cam) or not is_finite(half):
		if is_finite_v3(focus):
			return focus + Vector3(0.0, 2.4, 0.0)
		return Vector3(0.0, 2.4, 0.0)
	half = maxf(half, 0.5)
	if absf(cam.x) <= half and absf(cam.z) <= half:
		return cam
	var dir := cam - focus
	var lo := 0.0
	var hi := 1.0
	for _i in 12:
		var mid := (lo + hi) * 0.5
		var p := focus + dir * mid
		if absf(p.x) <= half and absf(p.z) <= half:
			lo = mid
		else:
			hi = mid
	var fitted := focus + dir * lo
	if not is_finite_v3(fitted):
		return Vector3(clampf(focus.x, -half, half), focus.y + 2.4, clampf(focus.z, -half, half))
	fitted.x = clampf(fitted.x, -half, half)
	fitted.z = clampf(fitted.z, -half, half)
	return fitted

## Finiteness gate for every vector the rig is about to write into a Node3D.
## A single NaN in a Camera3D transform makes the projection/cull matrices invalid,
## which is unrecoverable mid-frame on mobile; callers must reject it, not clamp it.
static func is_finite_v3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


static func is_finite_transform(xform: Transform3D) -> bool:
	if not is_finite_v3(xform.origin):
		return false
	for axis in [xform.basis.x, xform.basis.y, xform.basis.z]:
		if not is_finite_v3(axis):
			return false
	return true


static func sanitize_vec(v: Vector3) -> Vector3:
	if not is_finite(v.x) or not is_finite(v.y) or not is_finite(v.z):
		return Vector3.ZERO
	return v
