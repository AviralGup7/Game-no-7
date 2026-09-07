class_name EnemyIdleState
extends EnemyState

## Idle: no movement. Watches for a valid target within detect_range (0 = always) and
## transitions to Chase once one exists. Falls back to Chase defensively when no
## target is present so the enemy never permanently stalls in a live wave.

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
		# No live player: fall back to chase so we keep trying rather than stalling.
		host.state_machine_change_to(&"chase")
		return
	var cfg := host.get_config()
	if cfg == null:
		return
	if cfg.detect_range <= 0.0 or host.global_position.distance_to(target.global_position) <= cfg.detect_range:
		host.state_machine_change_to(&"chase")


static func host_set_still(host: EnemyBase) -> void:
	if host != null:
		host.set_desired_move(Vector3.ZERO, 0.0)
