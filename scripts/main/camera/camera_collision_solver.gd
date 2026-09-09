class_name CameraCollisionSolver
extends RefCounted

## Spring-arm collision – sphere-cast from focus to desired, whiskers, ground clearance.
## Fast pull-in, slow push-out (Unreal SpringArm style).

var is_colliding := false
var recovery_timer := 0.0

var _profile: CameraProfile = null

func setup(profile: CameraProfile) -> void:
	_profile = profile

func set_profile(profile: CameraProfile) -> void:
	_profile = profile

func solve(from: Vector3, to: Vector3, orbit: CameraOrbitState, target: Node3D, world: World3D) -> Vector3:
	if _profile == null or orbit == null:
		return to

	var dir := to - from
	var dist := dir.length()
	if dist < 0.001:
		return to

	var hit := _sphere_cast(from, to, _profile.collision_radius, target, world)
	var target_dist := dist

	if hit.has("fraction"):
		var safe := float(hit.get("fraction", 1.0))
		target_dist = maxf(dist * safe - 0.25, _profile.min_distance)
		is_colliding = true
		recovery_timer = _profile.collision_recovery_delay
	else:
		var whisker_dist := _whisker_check(from, to, orbit, target, world)
		if whisker_dist < dist:
			target_dist = whisker_dist
			is_colliding = true
			recovery_timer = _profile.collision_recovery_delay
		else:
			if recovery_timer > 0.0:
				# Keep colliding state during recovery to avoid jitter
				is_colliding = true
				# recovery_timer is decreased outside? We'll handle with delta via caller or here with fixed?
				# For simplicity, we don't auto-decrease here; caller will tick recovery.
			else:
				is_colliding = false

	orbit.collision_distance = clampf(target_dist, _profile.min_distance, _profile.max_distance)

	var final_dir := dir.normalized()
	var result: Vector3
	if is_colliding:
		result = from + final_dir * orbit.collision_distance
	else:
		result = from + final_dir * orbit.current_distance

	result = _enforce_ground_clearance(result, from, world)
	return result

func tick_recovery(delta: float) -> void:
	if recovery_timer > 0.0:
		recovery_timer = maxf(recovery_timer - delta, 0.0)

func _sphere_cast(from: Vector3, to: Vector3, radius: float, target: Node3D, world: World3D) -> Dictionary:
	if world == null:
		return {}
	var space := world.direct_space_state
	if space == null:
		return {}

	var sphere := SphereShape3D.new()
	sphere.radius = maxf(radius, 0.05)

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), from)
	query.motion = to - from
	query.collision_mask = 1
	query.margin = 0.02
	if target != null and target is CollisionObject3D:
		query.exclude = [target.get_rid()]

	var result := space.cast_motion(query)
	if result.size() >= 2:
		var safe := float(result[0])
		var unsafe := float(result[1])
		if safe < 1.0 - 0.001:
			var point := from + (to - from) * safe
			return {"fraction": safe, "unsafe": unsafe, "point": point}

	# Fallback raycast
	var ray_query := PhysicsRayQueryParameters3D.create(from, to)
	ray_query.collision_mask = 1
	if target != null and target is CollisionObject3D:
		ray_query.exclude = [target.get_rid()]
	var ray_result := space.intersect_ray(ray_query)
	if not ray_result.is_empty():
		var hit_pos: Vector3 = ray_result.get("position", to)
		var hit_dist := from.distance_to(hit_pos)
		var total_dist := from.distance_to(to)
		if total_dist > 0.001:
			return {"fraction": hit_dist / total_dist, "point": hit_pos}
	return {}

func _whisker_check(from: Vector3, to: Vector3, orbit: CameraOrbitState, target: Node3D, world: World3D) -> float:
	if _profile.whisker_count <= 0 or world == null:
		return from.distance_to(to)
	var space := world.direct_space_state
	if space == null:
		return from.distance_to(to)

	var base_dist := from.distance_to(to)
	var min_dist := base_dist
	var yaw := orbit.current_yaw if orbit != null else 0.0
	var pitch := orbit.current_pitch if orbit != null else 0.5

	for i in range(_profile.whisker_count):
		var angle_offset := deg_to_rad(_profile.whisker_angle_deg) * (i + 1) * (1 if i % 2 == 0 else -1)
		var test_yaw := yaw + angle_offset
		var test_dir := Vector3(sin(test_yaw) * cos(pitch), sin(pitch), cos(test_yaw) * cos(pitch)).normalized()
		var test_to := from + test_dir * base_dist

		var q := PhysicsRayQueryParameters3D.create(from, test_to)
		q.collision_mask = 1
		if target != null and target is CollisionObject3D:
			q.exclude = [target.get_rid()]
		var res := space.intersect_ray(q)
		if not res.is_empty():
			var hit_pos: Vector3 = res.get("position", test_to)
			var d := from.distance_to(hit_pos) - 0.3
			min_dist = minf(min_dist, d)

	return clampf(min_dist, _profile.min_distance, base_dist)

func _enforce_ground_clearance(cam_pos: Vector3, focus: Vector3, world: World3D) -> Vector3:
	if world == null:
		return cam_pos
	var space := world.direct_space_state
	if space == null:
		return cam_pos

	var down_from := cam_pos + Vector3(0.0, 0.5, 0.0)
	var down_to := cam_pos + Vector3(0.0, -6.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(down_from, down_to)
	query.collision_mask = 1
	var result := space.intersect_ray(query)
	if not result.is_empty():
		var ground_y: float = result.get("position", cam_pos).y
		var min_y := ground_y + _profile.ground_clearance
		if cam_pos.y < min_y:
			cam_pos.y = min_y

	var min_allowed := focus.y - 1.0
	if cam_pos.y < min_allowed:
		cam_pos.y = lerpf(cam_pos.y, min_allowed, 0.5)

	return cam_pos
