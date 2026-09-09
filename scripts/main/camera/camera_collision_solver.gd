class_name CameraCollisionSolver
extends RefCounted

## Spring-arm collision – sphere-cast from focus to desired, whiskers, ground
## clearance. Fast pull-in, slow push-out (Unreal SpringArm style).
##
## HOT-PATH CONTRACT (why this file is longer than the maths it contains):
## `solve()` runs once per RENDER frame from `CameraRig._process`, not once per
## physics tick. On a 90/120 Hz phone that is 2x the spatial queries, and every
## query used to allocate a fresh SphereShape3D + PhysicsShapeQueryParameters3D
## plus one PhysicsRayQueryParameters3D per whisker — RID-backed objects handed to
## the physics server, i.e. avoidable allocation on the frame-critical path. Two
## rules, both pinned by `tests/python/test_regress_physics_timing_and_ccd.py`:
##
##   1. Query objects are created ONCE and mutated per query. The server reads the
##      parameter object at call time, so reuse is safe — the same pattern
##      `EnemyPack._sep_query` already documents.
##   2. Spatial work is time- AND distance-gated. A full pass costs one motion
##      cast, at most `whisker_count` short rays and one ground ray; it runs
##      every QUERY_INTERVAL seconds, or immediately once the arm has moved more
##      than CACHE_SLACK (a fast orbit or a teleport can therefore never see a
##      stale result). Only the OBSTACLE TEST is amortised: the cached pullback is
##      applied to the *current* arm direction every frame, so the camera keeps
##      tracking the player with zero added latency.
##
## The arm queries CollisionLayers.CAMERA_QUERY_MASK (arena geometry only): a
## horde must never shove the player's view around, pillars and walls must.

## Minimum seconds between full spatial passes (one pass per physics tick at the
## project's 60 Hz, so a 60 fps device is behaviourally identical to before).
const QUERY_INTERVAL := 1.0 / 60.0
## How far the arm may travel on a stale cache before a fresh pass is forced.
const CACHE_SLACK := 0.4
## Distance shaved off a hit so the camera never rests exactly on a collider
## (a resting spring arm flickers between "touching" and "clear" per frame).
const PULLBACK_PADDING := 0.25
## Whiskers stop this far short of whatever they find, for the same reason.
const WHISKER_PADDING := 0.3
## Motion-cast start margin: big enough to survive a shape that begins a hair
## inside a wall, small enough not to visibly shorten the arm.
const CAST_MARGIN := 0.02

var is_colliding := false
var recovery_timer := 0.0

var _profile: CameraProfile = null

# Pooled query state (never re-created after setup(); see rule 1 above).
var _sphere: SphereShape3D = null
var _shape_query: PhysicsShapeQueryParameters3D = null
var _ray_query: PhysicsRayQueryParameters3D = null
var _exclude: Array = []

# Cache (see rule 2 above).
var _time_until_query := 0.0
var _cache_valid := false
var _cached_to := Vector3.INF
var _cached_from := Vector3.INF
var _cached_pullback := 0.0
var _cached_hit := false
var _cached_ground_y := 0.0
var _cached_ground_hit := false
## Diagnostics: how many spatial queries the last solve() actually issued.
var queries_last_pass := 0
var passes_total := 0


func setup(profile: CameraProfile) -> void:
	_profile = profile
	_ensure_query_objects()
	if profile != null:
		_sphere.radius = maxf(profile.collision_radius, 0.05)
	invalidate_cache()


func set_profile(profile: CameraProfile) -> void:
	_profile = profile
	_ensure_query_objects()
	if profile != null and _sphere != null:
		_sphere.radius = maxf(profile.collision_radius, 0.05)
	invalidate_cache()


## The ONLY place the query objects exist. `new()` here, never in solve().
func _ensure_query_objects() -> void:
	if _sphere == null:
		_sphere = SphereShape3D.new()
		_sphere.radius = 0.35
	if _shape_query == null:
		_shape_query = PhysicsShapeQueryParameters3D.new()
		_shape_query.shape = _sphere
		_shape_query.collide_with_bodies = true
		_shape_query.collide_with_areas = false
	if _ray_query == null:
		_ray_query = PhysicsRayQueryParameters3D.new()
		_ray_query.collide_with_bodies = true
		_ray_query.collide_with_areas = false


## Drop the cached pass so the next solve() queries for sure (profile change,
## rig re-target, cut-scene snap).
func invalidate_cache() -> void:
	_cache_valid = false
	_cached_to = Vector3.INF
	_cached_from = Vector3.INF
	_time_until_query = 0.0


## Per-frame tick from the rig: decays the push-out hold AND drives the query
## clock (solve() has no delta of its own, so the clock lives here).
func tick_recovery(delta: float) -> void:
	if recovery_timer > 0.0:
		recovery_timer = maxf(recovery_timer - maxf(delta, 0.0), 0.0)
	if not is_finite(delta) or delta <= 0.0:
		return
	_time_until_query = maxf(_time_until_query - delta, 0.0)


func solve(from: Vector3, to: Vector3, orbit: CameraOrbitState, target: Node3D, world: World3D) -> Vector3:
	if _profile == null or orbit == null:
		return to

	var dir := to - from
	var dist := dir.length()
	if dist < 0.001:
		return to

	queries_last_pass = 0
	if _needs_fresh_pass(from, to):
		_run_pass(from, to, dist, orbit, target, world)

	var final_dir := dir.normalized()
	if not final_dir.is_finite():
		return to

	var result := from
	if _cache_valid and _cached_hit:
		var held := clampf(_cached_pullback, _profile.min_distance, _profile.max_distance)
		orbit.collision_distance = held
		result = from + final_dir * held
	else:
		orbit.collision_distance = clampf(dist, _profile.min_distance, _profile.max_distance)
		result = from + final_dir * orbit.current_distance

	if _cache_valid and _cached_ground_hit:
		result = _apply_ground_clearance(result, from)
	return result


## The cache holds only while BOTH ends of the arm stay put. `to` (the desired
## camera position) is what sweeps into geometry; `from` (the focus) moves with
## shoulder offset, look-ahead and the boss/combat framing, and a shifted focus
## invalidates a previous whisker fan even when the length is unchanged.
func _needs_fresh_pass(from: Vector3, to: Vector3) -> bool:
	if not _cache_valid or _time_until_query <= 0.0:
		return true
	var slack_sq := CACHE_SLACK * CACHE_SLACK
	var moved := (to - _cached_to).length_squared() > slack_sq
	moved = moved or (from - _cached_from).length_squared() > slack_sq
	return moved


func _run_pass(from: Vector3, to: Vector3, dist: float, orbit: CameraOrbitState, target: Node3D, world: World3D) -> void:
	_time_until_query = QUERY_INTERVAL
	passes_total += 1
	_cache_valid = true
	_cached_to = to
	_cached_from = from
	# Recompute the collision state from a clean slate every pass; the push-out
	# hold (recovery_timer) is what makes it asymmetric, not the cache.
	var hit_anything := false
	var held := dist

	# `use_sphere_cast` is an authored per-profile switch (every shipped profile
	# turns it on); when it is off the whiskers alone do the work.
	var safe := _cast_safe_fraction(from, to, target, world) if _profile.use_sphere_cast else 1.0
	if safe < 1.0:
		held = maxf(dist * safe - PULLBACK_PADDING, _profile.min_distance)
		hit_anything = true
	else:
		var whisker_dist := _whisker_check(from, to, dist, orbit, target, world)
		if whisker_dist < dist:
			held = whisker_dist
			hit_anything = true

	if hit_anything:
		is_colliding = true
		recovery_timer = _profile.collision_recovery_delay
	elif recovery_timer > 0.0:
		# Slow push-out: stay flagged as colliding (the shake controller damps
		# against is_colliding) while the recovery delay runs off, so an arm
		# resting on a ledge cannot flicker between states every frame. Distance
		# itself is NOT held: the arm already tracks the desired length here, so
		# only the flag decays — same shape as before the cache existed.
		is_colliding = true
	else:
		is_colliding = false

	_cached_hit = hit_anything
	_cached_pullback = clampf(held, _profile.min_distance, _profile.max_distance)
	_ground_probe(to, world)


## One motion cast against the arena. Returns the safe fraction of `to - from`
## (1.0 = clear). A shape that already starts inside geometry yields no collision
## here — the whiskers and the Area3D overlap paths still cover that case.
func _cast_safe_fraction(from: Vector3, to: Vector3, target: Node3D, world: World3D) -> float:
	var space := _space(world)
	if space == null or _shape_query == null:
		return 1.0
	_shape_query.transform = Transform3D(Basis(), from)
	_shape_query.motion = to - from
	_shape_query.collision_mask = CollisionLayers.CAMERA_QUERY_MASK
	_shape_query.margin = CAST_MARGIN
	_fill_exclude(target)
	_shape_query.exclude = _exclude
	queries_last_pass += 1
	var result := space.cast_motion(_shape_query)
	if result.size() < 2:
		return 1.0
	var safe := float(result[0])
	if not is_finite(safe):
		return 1.0
	return clampf(safe, 0.0, 1.0)


## Short rays fanned either side of the arm: they catch the wall a straight cast
## grazes past when the arm swings across a corner.
func _whisker_check(from: Vector3, to: Vector3, base_dist: float, orbit: CameraOrbitState, target: Node3D, world: World3D) -> float:
	if _profile.whisker_count <= 0:
		return base_dist
	var space := _space(world)
	if space == null or _ray_query == null:
		return base_dist

	var min_dist := base_dist
	var yaw := orbit.current_yaw if orbit != null else 0.0
	var pitch := orbit.current_pitch if orbit != null else 0.5
	for i in range(_profile.whisker_count):
		var angle_offset := deg_to_rad(_profile.whisker_angle_deg) * (i + 1) * (1 if i % 2 == 0 else -1)
		var test_yaw := yaw + angle_offset
		var test_dir := Vector3(sin(test_yaw) * cos(pitch), sin(pitch), cos(test_yaw) * cos(pitch)).normalized()
		var res := _cast_ray(space, from, from + test_dir * base_dist, target)
		if res.is_empty():
			continue
		var hit_pos: Vector3 = res.get("position", to)
		min_dist = minf(min_dist, maxf(from.distance_to(hit_pos) - WHISKER_PADDING, _profile.min_distance))
	return clampf(min_dist, _profile.min_distance, base_dist)


## Ground height under the camera, so the arm never dips through the floor.
## Probed at the DESIRED position rather than the resolved one (the resolved one is
## what this probe produces, so sampling it would feed the cache back into itself);
## on a flat arena floor the two agree, and the `focus.y - 1.0` floor below bounds
## the difference on any geometry that does have height.
func _ground_probe(cam_pos: Vector3, world: World3D) -> void:
	_cached_ground_hit = false
	var space := _space(world)
	if space == null or _ray_query == null:
		return
	var down_from := cam_pos + Vector3(0.0, 0.5, 0.0)
	var down_to := cam_pos + Vector3(0.0, -6.0, 0.0)
	var result := _cast_ray(space, down_from, down_to, null)
	if result.is_empty():
		return
	var hit_pos: Vector3 = result.get("position", Vector3.ZERO)
	var ground_y := hit_pos.y
	if not is_finite(ground_y):
		return
	_cached_ground_y = ground_y
	_cached_ground_hit = true


func _apply_ground_clearance(cam_pos: Vector3, focus: Vector3) -> Vector3:
	var min_y := _cached_ground_y + _profile.ground_clearance
	if cam_pos.y < min_y:
		cam_pos.y = min_y
	var min_allowed := focus.y - 1.0
	if cam_pos.y < min_allowed:
		cam_pos.y = lerpf(cam_pos.y, min_allowed, 0.5)
	return cam_pos


## Reused ray parameters: mutate + call, never allocate (rule 1).
func _cast_ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, target: Node3D) -> Dictionary:
	_ray_query.from = from
	_ray_query.to = to
	_ray_query.collision_mask = CollisionLayers.CAMERA_QUERY_MASK
	_fill_exclude(target)
	_ray_query.exclude = _exclude
	queries_last_pass += 1
	return space.intersect_ray(_ray_query)


func _fill_exclude(target: Node3D) -> void:
	_exclude.clear()
	if target == null or not (target is CollisionObject3D):
		return
	# Narrowed by the `is` check above; a typed local beats an `as` cast here (the
	# architecture gate keeps its engine-cast allowlist deliberately short).
	var collider: CollisionObject3D = target
	_exclude.append(collider.get_rid())


func _space(world: World3D) -> PhysicsDirectSpaceState3D:
	if world == null:
		return null
	return world.direct_space_state


func get_debug_snapshot() -> Dictionary:
	return {
		"is_colliding": is_colliding,
		"recovery_timer": recovery_timer,
		"cache_valid": _cache_valid,
		"cached_pullback": _cached_pullback,
		"cached_hit": _cached_hit,
		"ground_hit": _cached_ground_hit,
		"queries_last_pass": queries_last_pass,
		"passes_total": passes_total,
	}
