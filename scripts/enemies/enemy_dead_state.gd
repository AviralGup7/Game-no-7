class_name EnemyDeadState
extends EnemyState

## Dead: stops all behaviour. Actual exactly-once death handling (score payload,
## despawn signal, feedback, freeing) stays in EnemyBase so the Phase 2 guarantees are
## preserved; this state only reports that behaviour has ceased while the tween plays.

func _init() -> void:
	super(&"dead")


func enter(host: EnemyBase) -> void:
	host.set_desired_move(Vector3.ZERO, 0.0)
	host.set_velocity_flat(Vector3.ZERO)


func update(_host: EnemyBase, _delta: float) -> void:
	pass


func physics_update(_host: EnemyBase, _delta: float) -> void:
	pass
