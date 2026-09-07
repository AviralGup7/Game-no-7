class_name EnemyAttackState
extends EnemyState

## Attack: telegraph (windup) -> one melee damage query -> cooldown -> back to Chase.
## Performs the hit exactly once per pass through the windup (phase gating) which,
## together with the EnemyBase death guard, prevents duplicate hits / double score.

enum { PHASE_WINDUP, PHASE_COOLDOWN }

var _phase := PHASE_WINDUP
var _elapsed := 0.0


func _init() -> void:
	super(&"attack")


func enter(host: EnemyBase) -> void:
	_phase = PHASE_WINDUP
	_elapsed = 0.0
	host.set_desired_move(Vector3.ZERO, 0.0)
	if host.has_signal("attack_started"):
		host.attack_started.emit()


func physics_update(host: EnemyBase, _delta: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	if not host.is_alive():
		return
	var cfg := host.get_config()
	if cfg == null:
		host.state_machine_change_to(&"idle")
		return
	var target := host.get_move_target()
	if target == null:
		host.state_machine_change_to(&"idle")
		return
	host.set_desired_move(Vector3.ZERO, 0.0)
	host.face_target(target)
	if _phase == PHASE_WINDUP:
		_elapsed += _delta
		if _elapsed >= cfg.attack_windup:
			host.perform_enemy_attack()
			_phase = PHASE_COOLDOWN
			_elapsed = 0.0
	elif _phase == PHASE_COOLDOWN:
		_elapsed += _delta
		if _elapsed >= cfg.attack_cooldown:
			host.state_machine_change_to(&"chase")
