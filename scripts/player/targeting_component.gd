extends Node
class_name TargetingComponent

## Aim assistance, sticky lock, line-of-sight filter, and prioritization.
## Settings.aim_assist_enabled scales strength to zero when the player turns it off.

@export var aim_assist_strength: float = 0.6
@export var max_target_range: float = 12.0
@export var angular_favor_degrees: float = 20.0
@export var sticky_bonus: float = 2.4
@export var require_line_of_sight: bool = true

var _owner_node: Node3D = null
var _sticky: Node = null


func _ready() -> void:
	_owner_node = get_parent() as Node3D
	apply_settings()


func bind_owner(node: Node3D) -> void:
	_owner_node = node


func apply_settings() -> void:
	if SaveManager == null:
		return
	var on := SaveManager.get_settings().is_aim_assist_enabled()
	# Keep the authored curve when assist is on; hard-off when the toggle is false.
	if not on:
		aim_assist_strength = 0.0


func set_aim_assist(value: float) -> void:
	aim_assist_strength = clampf(value, 0.0, 1.0)


func clear_sticky() -> void:
	_sticky = null


func get_sticky() -> Node:
	if _sticky != null and is_instance_valid(_sticky):
		var d := _sticky as Damageable
		if d != null and d.is_alive():
			return _sticky
	_sticky = null
	return null


## Given candidate targets (with is_alive()/global_position), pick the best based on
## distance, facing cone, stickiness, and optional world LOS. Pure enough to unit test
## when require_line_of_sight is false (headless has no physics).
func pick_best_target(candidates: Array) -> Node:
	if _owner_node == null or candidates.is_empty():
		return null
	var best: Node = null
	var best_score := -INF
	var origin := _owner_node.global_position
	var facing := _facing_forward()
	var range_squared := maxf(max_target_range, 0.0) * maxf(max_target_range, 0.0)
	var cone := cos(deg_to_rad(clampf(angular_favor_degrees, 0.0, 89.0)))
	var sticky := get_sticky()
	var space: PhysicsDirectSpaceState3D = null
	if require_line_of_sight and _owner_node.is_inside_tree():
		var world := _owner_node.get_world_3d()
		if world != null:
			space = world.direct_space_state
	for c in candidates:
		if not is_instance_valid(c):
			continue
		var candidate := c as Damageable
		if candidate == null:
			continue
		if not candidate.is_alive():
			continue
		var node := c as Node3D
		if node == null:
			continue
		var to_target := node.global_position - origin
		to_target.y = 0.0
		var distance_squared := to_target.length_squared()
		if distance_squared > range_squared:
			continue
		if space != null and _blocked(space, origin, node.global_position):
			continue
		var dist := sqrt(distance_squared)
		var dot := facing.dot(to_target / dist) if dist > 0.0001 else 1.0
		var favor := clampf((dot - cone) / maxf(1.0 - cone, 0.001), 0.0, 1.0)
		var score := -dist + favor * clampf(aim_assist_strength, 0.0, 1.0)
		if score > best_score:
			best_score = score
			best = c
		elif c == sticky and not is_equal_approx(score, best_score) and score + sticky_bonus > best_score:
			# Stickiness may keep a slightly worse lock, but never override a true tie
			# (tests and lock-on both require input-order determinism on equal scores).
			best_score = score + sticky_bonus
			best = c
	if best != null:
		_sticky = best
	return best


func _blocked(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var a := from + Vector3(0.0, 1.1, 0.0)
	var b := to + Vector3(0.0, 1.1, 0.0)
	var q := PhysicsRayQueryParameters3D.create(a, b)
	# Only arena geometry breaks a lock-on; another enemy in the way does not. Named bit, because
	# `collision_mask = 1` stops meaning anything the moment a layer is renumbered.
	q.collision_mask = CollisionLayers.OBSTRUCTORS
	if _owner_node is CollisionObject3D:
		q.exclude = [(_owner_node as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	return not hit.is_empty()


func _facing_forward() -> Vector3:
	if _owner_node == null:
		return Vector3.FORWARD
	var b := _owner_node.global_transform.basis
	var f := -b.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


func get_debug_snapshot() -> Dictionary:
	return {
		"aim_assist_strength": aim_assist_strength,
		"max_target_range": max_target_range,
		"sticky": _sticky != null and is_instance_valid(_sticky),
	}
