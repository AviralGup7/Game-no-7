class_name CameraFramingController
extends RefCounted

## Cinematic framing – shoulder offset, look-ahead, combat awareness.
## Inspired by Uncharted/TLOU/God of War: keep player in lower third, slightly ahead,
## pull back when surrounded. Uses profile combat_* fields for data-driven tuning.

var _profile: CameraProfile = null

# Combat framing state
var _enemy_count_near := 0
var _combat_distance_boost := 0.0
var _combat_fov_boost := 0.0
var _last_enemy_check := 0.0

func setup(profile: CameraProfile) -> void:
	_profile = profile

func set_profile(profile: CameraProfile) -> void:
	_profile = profile

func calculate_desired_position(focus: Vector3, orbit: CameraOrbitState) -> Vector3:
	if _profile == null or orbit == null:
		return focus

	var pitch := orbit.current_pitch
	var yaw := orbit.current_yaw
	var dist := orbit.current_distance + _combat_distance_boost

	var horiz := dist * cos(pitch)
	var vert := dist * sin(pitch)

	var offset := Vector3(
		sin(yaw) * horiz,
		vert + _profile.height * 0.55,
		cos(yaw) * horiz
	)

	var right := CameraMath.right_from_yaw(yaw)
	offset += right * _profile.shoulder_offset.x
	offset.y += _profile.shoulder_offset.y

	return focus + offset

func calculate_look_target(focus: Vector3, velocity_tracker: CameraVelocityTracker) -> Vector3:
	if _profile == null:
		return focus
	var look_target := focus
	if velocity_tracker != null:
		look_target += velocity_tracker.velocity * _profile.velocity_influence * 0.12
	look_target.y += _profile.shoulder_offset.y * 0.3
	return look_target

func tick_combat_framing(delta: float, player_pos: Vector3, tree: SceneTree) -> void:
	if _profile == null or not _profile.combat_framing_enabled:
		return

	_last_enemy_check += delta
	var interval := _profile.combat_check_interval if _profile != null else 0.25
	if _last_enemy_check < interval:
		return
	_last_enemy_check = 0.0

	# Count nearby enemies for dynamic pull-back
	var count := 0
	var radius := _profile.combat_enemy_radius if _profile != null else 8.0
	if tree != null:
		var enemies := tree.get_nodes_in_group("enemies")
		for e in enemies:
			if e is Node3D:
				var d := (e as Node3D).global_position.distance_to(player_pos)
				if d < radius:
					count += 1

	_enemy_count_near = count

	# Data-driven boosts from profile
	var target_dist_boost := 0.0
	var target_fov_boost := 0.0
	if count >= 6:
		target_dist_boost = _profile.combat_distance_boost_6 if _profile != null else 2.5
		target_fov_boost = _profile.combat_fov_boost_6 if _profile != null else 4.0
	elif count >= 4:
		target_dist_boost = _profile.combat_distance_boost_4 if _profile != null else 1.2
		target_fov_boost = _profile.combat_fov_boost_4 if _profile != null else 2.0
	elif count >= 2:
		target_dist_boost = _profile.combat_distance_boost_2 if _profile != null else 0.4

	_combat_distance_boost = lerpf(_combat_distance_boost, target_dist_boost, clampf(delta * 1.5, 0.0, 1.0))
	_combat_fov_boost = lerpf(_combat_fov_boost, target_fov_boost, clampf(delta * 1.5, 0.0, 1.0))

func get_combat_distance_boost() -> float:
	return _combat_distance_boost

func get_combat_fov_boost() -> float:
	return _combat_fov_boost

func get_enemy_count() -> int:
	return _enemy_count_near

func reset() -> void:
	_enemy_count_near = 0
	_combat_distance_boost = 0.0
	_combat_fov_boost = 0.0
	_last_enemy_check = 0.0
