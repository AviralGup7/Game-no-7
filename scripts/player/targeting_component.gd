extends Node
class_name TargetingComponent

## Owns aim assistance, target filtering, and target prioritization. Phase 1 holds
## configuration and the pure filtering logic; weapon-facing lookup is added with
## combat. Kept independent so multiple/future weapons share one targeting policy.

@export var aim_assist_strength: float = 0.6
@export var max_target_range: float = 12.0
@export var angular_favor_degrees: float = 20.0

var _owner_node: Node3D = null


func _ready() -> void:
	_owner_node = get_parent() as Node3D


func bind_owner(node: Node3D) -> void:
	_owner_node = node


func set_aim_assist(value: float) -> void:
	aim_assist_strength = clampf(value, 0.0, 1.0)


## Given candidate targets (with is_alive()/global_position), pick the best based on
## distance and angular closeness to the owner's facing. Pure enough to unit test.
func pick_best_target(candidates: Array) -> Node:
	if _owner_node == null or candidates.is_empty():
		return null
	var best: Node = null
	var best_score := -INF
	var origin := _owner_node.global_position
	var facing := _facing_forward()
	var range_squared := maxf(max_target_range, 0.0) * maxf(max_target_range, 0.0)
	var cone := cos(deg_to_rad(clampf(angular_favor_degrees, 0.0, 89.0)))
	for c in candidates:
		if not is_instance_valid(c):
			continue
		# Damageable is the explicit combat protocol (see damageable.gd): a plain
		# Node3D without it is not a valid target, no string-based probing.
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
		var dist := sqrt(distance_squared)
		var dot := facing.dot(to_target / dist) if dist > 0.0001 else 1.0
		# Aim preference is bounded in metres: a distant forward enemy cannot
		# steal aim from a close threat. Equal scores preserve candidate order.
		var favor := clampf((dot - cone) / maxf(1.0 - cone, 0.001), 0.0, 1.0)
		var score := -dist + favor * clampf(aim_assist_strength, 0.0, 1.0)
		if score > best_score:
			best_score = score
			best = c
	return best


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
	}

