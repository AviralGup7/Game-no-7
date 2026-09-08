class_name EnemyIdleState
extends EnemyState

## Idle: no movement. Watches for a valid target within detect_range (0 = always) and
## transitions to Chase (or Ranged for ranged archetypes) once one exists. When no
## target exists the enemy stays put; the run is over in that case and the
## SpawnManager deactivates AI explicitly.

func _init() -> void:
	super(&"idle")


func enter(_host: EnemyBase) -> void:
	host_set_still(_host)


func physics_update(host: EnemyBase, _delta: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	if not host.is_alive():
		return
	host.set_desired_move(Vector3.ZERO, 0.0)
	var target := host.get_move_target()
	if target == null:
		return
	var cfg := host.get_config()
	if cfg == null:
		return
	if cfg.detect_range <= 0.0 or host.global_position.distance_to(target.global_position) <= cfg.detect_range:
		if String(cfg.ai_behavior) == "ranged":
			host.state_machine_change_to(&"ranged")
		else:
			host.state_machine_change_to(&"chase")


static func host_set_still(host: EnemyBase) -> void:
	if host != null:
		host.set_desired_move(Vector3.ZERO, 0.0)

## Hardened: clamp idle dwell.
func _validated_idle_dwell(d: float) -> float:
	if not is_finite(d) or d < 0.0:
		return 0.5
	return clampf(d, 0.1, 5.0)

