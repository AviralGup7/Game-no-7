class_name EnemyChaseState
extends EnemyState

## Chase: steers toward the target at the configured move speed (via navigation when
## available, else direct pursuit) and transitions to Attack once in range. Falls back
## to Idle when the target disappears.

func _init() -> void:
	super(&"chase")


func enter(host: EnemyBase) -> void:
	host.set_desired_move(Vector3.ZERO, 0.0)


func physics_update(host: EnemyBase, _delta: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	if not host.is_alive():
		return
	var target := host.get_move_target()
	if target == null:
		host.set_desired_move(Vector3.ZERO, 0.0)
		host.state_machine_change_to(&"idle")
		return
	if host.target_in_attack_range(target):
		host.set_desired_move(Vector3.ZERO, 0.0)
		host.state_machine_change_to(&"attack")
		return
	var cfg := host.get_config()
	if cfg == null:
		return
	# Ranged archetypes orbit + volley instead of closing to melee.
	if String(cfg.ai_behavior) == "ranged":
		host.state_machine_change_to(&"ranged")
		return
	var offset := target.global_position - host.global_position
	offset.y = 0.0
	var desired := Vector3.FORWARD
	if offset.length_squared() > 0.0001:
		desired = offset.normalized()
	var steer := host.get_navigation_direction(desired)
	host.set_desired_move(steer, host.get_effective_speed())
	host.face_direction(steer)
