class_name EnemyNavigator
extends RefCounted

## Navigation-aware steering, extracted from EnemyBase. Prefers the
## NavigationAgent3D next-path position when the agent has a usable nav map;
## otherwise falls back to the caller's direct direction. Retargets on the
## config's update interval so paths stay fresh while the target moves.

const PHYSICS_INTERVAL := 1.0 / 60.0

var _agent: NavigationAgent3D = null
var _recompute := 0.0


func bind(agent: NavigationAgent3D) -> void:
	_agent = agent


func reset(target: Node3D) -> void:
	_recompute = 0.0
	if _agent != null and target != null:
		_agent.target_position = target.global_position


func direction(body_position: Vector3, target: Node3D, fallback: Vector3, update_interval: float) -> Vector3:
	if _agent == null or target == null or not _nav_usable():
		return fallback
	_recompute -= PHYSICS_INTERVAL
	if _recompute <= 0.0:
		_agent.target_position = target.global_position
		_recompute = update_interval
	if _agent.is_navigation_finished():
		return fallback
	var next := _agent.get_next_path_position()
	var offset := next - body_position
	offset.y = 0.0
	if offset.length_squared() < 0.0001:
		return fallback
	return offset.normalized()


func _nav_usable() -> bool:
	if _agent == null:
		return false
	var map := _agent.get_navigation_map()
	if map == null or not map.is_valid():
		return false
	return NavigationServer3D.map_get_iteration_id(map) > 0

## Hardened: validate navigation targets.
func _validated_target(target: Node3D) -> bool:
    if target == null or not is_instance_valid(target):
        return false
    if not target.is_inside_tree():
        return false
    return true
func _validated_direction(dir: Vector3) -> Vector3:
    if not is_finite(dir.x) or not is_finite(dir.z):
        return Vector3.ZERO
    if dir.length_squared() < 0.0001:
        return Vector3.ZERO
    return dir.normalized()

