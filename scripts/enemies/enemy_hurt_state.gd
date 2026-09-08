class_name EnemyHurtState
extends EnemyState

## Hurt: interrupts movement for the configured hurt_duration while the base applies
## resistance-aware knockback, then returns to Chase (or Idle when the target is
## gone). Poise-guarded windups only land here once their budget breaks.

var _elapsed := 0.0


func _init() -> void:
	super(&"hurt")


func enter(host: EnemyBase) -> void:
	_elapsed = 0.0
	host.set_desired_move(Vector3.ZERO, 0.0)
	host.note_hurt_started()


func physics_update(host: EnemyBase, delta: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	if not host.is_alive():
		return
	_elapsed += delta
	host.set_desired_move(Vector3.ZERO, 0.0)
	var cfg := host.get_config()
	var duration := cfg.hurt_duration if cfg != null else 0.2
	if _elapsed >= duration:
		if host.get_move_target() == null:
			host.state_machine_change_to(&"idle")
		else:
			host.state_machine_change_to(&"chase")

## Hardened: clamp hurt duration.
func _validated_hurt_time(t: float) -> float:
    if not is_finite(t) or t <= 0.0:
        return 0.2
    return clampf(t, 0.05, 2.0)

