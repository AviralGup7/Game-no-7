extends RefCounted

## Regression: camera boom must stay inside the playable yard.
##
## Failure mode this pins: PlayerStart faced -Z with a 9 m arm, so the lens sat
## in/through the south wall. The player looked like they were in the HDRI
## "mountains" while the body was still in the arena; turning around sphere-cast
## from inside a collider and crashed. Pure math — no World3D.


static func suite() -> Array:
	var results: Array = []
	_boom_fit(results)
	_spherical_offset(results)
	return results


static func _check(results: Array, name: String, passed: bool, why: String = "") -> void:
	results.append({"name": name, "passed": passed, "why": why})


static func _finite3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


static func _boom_fit(results: Array) -> void:
	var focus := Vector3(0.0, 1.5, 4.5)
	var half := 10.65
	var south_wall := Vector3(0.0, 4.0, 18.0)
	var fitted := CameraMath.shorten_arm_to_box(focus, south_wall, half)
	_check(results, "south-wall boom is shortened inside the yard",
		absf(fitted.z) <= half + 0.001 and _finite3(fitted),
		"got %s" % str(fitted))
	_check(results, "shortened boom stays on the focus-to-cam segment (same X)",
		absf(fitted.x - focus.x) < 0.02,
		"got %s" % str(fitted))

	var east_wall := Vector3(22.0, 5.0, 4.5)
	var east := CameraMath.shorten_arm_to_box(focus, east_wall, half)
	_check(results, "east-wall boom is shortened inside the yard",
		absf(east.x) <= half + 0.001 and _finite3(east),
		"got %s" % str(east))

	var inside := Vector3(1.0, 3.0, 2.0)
	_check(results, "already-inside boom is unchanged",
		CameraMath.shorten_arm_to_box(focus, inside, half).is_equal_approx(inside))

	var corner := Vector3(40.0, 8.0, 40.0)
	var cfit := CameraMath.shorten_arm_to_box(Vector3.ZERO, corner, half)
	_check(results, "diagonal boom never leaves the square",
		absf(cfit.x) <= half + 0.001 and absf(cfit.z) <= half + 0.001 and _finite3(cfit),
		"got %s" % str(cfit))

	_check(results, "NaN focus falls back to a finite lift",
		_finite3(CameraMath.shorten_arm_to_box(Vector3(NAN, 0.0, 0.0), south_wall, half)))
	_check(results, "NaN camera falls back to a finite lift",
		_finite3(CameraMath.shorten_arm_to_box(focus, Vector3(INF, 0.0, 0.0), half)))
	_check(results, "non-finite half falls back to a finite lift",
		_finite3(CameraMath.shorten_arm_to_box(focus, south_wall, NAN)))


static func _spherical_offset(results: Array) -> void:
	_check(results, "infinite orbit distance sanitizes to ZERO",
		CameraMath.spherical_offset(0.0, 0.0, INF) == Vector3.ZERO)
	_check(results, "NaN yaw sanitizes to ZERO",
		CameraMath.spherical_offset(NAN, 0.4, 9.0) == Vector3.ZERO)
	var ok := CameraMath.spherical_offset(0.0, 0.0, 4.0)
	_check(results, "finite orbit offset stays finite and behind +Z",
		_finite3(ok) and absf(ok.z - 4.0) < 0.001,
		"got %s" % str(ok))
