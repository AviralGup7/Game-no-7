extends RefCounted

## Regression: player spawn must be on the floor, in-bounds, and off the landmark.
##
## Failure mode this pins: spawn at (0,0,4.5) facing -Z put the camera in the
## south wall / HDRI mountains, and a landmark (forge radius 1.9) could overlap
## a centre spawn. unstuck_origin + get_safe_player_spawn are the contract.


static func suite() -> Array:
	var results: Array = []
	_unstuck(results)
	_safe_spawn(results)
	return results


static func _check(results: Array, name: String, passed: bool, why: String = "") -> void:
	results.append({"name": name, "passed": passed, "why": why})


static func _finite3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


static func _unstuck(results: Array) -> void:
	var arena := Arena.new()
	arena.interior_half = 12.0
	# The half-extents the unstuck solver keeps clear. The field this replaced,
	# `arena._landmark_half`, was a second authored copy of the landmark's shape and is gone; the
	# setter is the same input with a name that says who owns it.
	arena.set_landmark_block_half(Vector3(1.9, 0.7, 1.9))

	var buried := arena.unstuck_origin(Vector3(0.0, -2.0, 0.0))
	_check(results, "centre spawn is pushed off the forge footprint",
		Vector2(buried.x, buried.z).length() >= 1.9 + 1.35 - 0.05 and buried.y >= 0.15,
		"got %s" % str(buried))
	_check(results, "unstuck origin is finite", _finite3(buried), "got %s" % str(buried))

	var outside := arena.unstuck_origin(Vector3(40.0, 0.2, -40.0))
	var half := 12.0 - 2.25
	_check(results, "out-of-yard spawn is clamped to the interior",
		absf(outside.x) <= half + 0.001 and absf(outside.z) <= half + 0.001,
		"got %s" % str(outside))

	var poisoned := arena.unstuck_origin(Vector3(NAN, INF, -INF))
	_check(results, "poisoned spawn is repaired to a finite interior point",
		_finite3(poisoned) and absf(poisoned.x) <= half + 0.001 and absf(poisoned.z) <= half + 0.001,
		"got %s" % str(poisoned))

	var lifted := arena.unstuck_origin(Vector3(4.0, -8.0, 4.0))
	_check(results, "below-lifted spawn is lifted",
		lifted.y >= 0.15, "y=%.3f" % lifted.y)

	arena.free()


static func _safe_spawn(results: Array) -> void:
	var arena := Arena.new()
	arena.interior_half = 12.0
	arena.set_landmark_block_half(Vector3(0.55, 2.3, 0.55))
	var xf := arena.get_safe_player_spawn()
	_check(results, "safe spawn origin is finite and on the floor",
		_finite3(xf.origin) and xf.origin.y >= 0.15,
		"got %s" % str(xf.origin))
	_check(results, "safe spawn basis is usable (non-zero determinant)",
		absf(xf.basis.determinant()) > 0.5,
		"det=%.3f" % xf.basis.determinant())
	arena.free()
