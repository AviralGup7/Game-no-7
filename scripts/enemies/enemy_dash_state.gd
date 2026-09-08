class_name EnemyDashState
extends EnemyState

## Dasher charge cycle: WINDUP (planted, telegraph flash + sound, direction locked
## at release) -> CHARGE (movement override drives the body in a straight line; one
## contact hit via EnemyStriker.execute_dash) -> RECOVERY (rooted, vulnerable
## stagger) -> back to Chase. Entry is cooldown-gated by EnemyBase.try_begin_dash()
## from the Chase state, so this state itself never re-triggers on a cooldown.

enum { PHASE_WINDUP, PHASE_CHARGE, PHASE_RECOVERY }

var _phase := PHASE_WINDUP
var _elapsed := 0.0
var _dir := Vector3.FORWARD
var _struck := false


func _init() -> void:
	super(&"dash")


func enter(host: EnemyBase) -> void:
	_phase = PHASE_WINDUP
	_elapsed = 0.0
	_struck = false
	_dir = Vector3.FORWARD
	host.set_desired_move(Vector3.ZERO, 0.0)
	# Telegraph: root in place, flash, growl — the charge must be readable.
	var cfg := host.get_config()
	host.set_move_override(Vector3.ZERO, 0.0, cfg.dash_windup if cfg != null else 0.45)
	host.play_telegraph_feedback()
	host.play_windup_sound()


func exit(host: EnemyBase) -> void:
	host.clear_move_override()


func physics_update(host: EnemyBase, delta: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	if not host.is_alive():
		return
	var cfg := host.get_config()
	if cfg == null:
		host.state_machine_change_to(&"chase")
		return
	_elapsed += delta
	match _phase:
		PHASE_WINDUP:
			var target := host.get_move_target()
			if target != null:
				host.face_target(target)
			if _elapsed >= cfg.dash_windup:
				# Lock the charge direction at release (dodgeable, not homing).
				if target != null:
					var flat := target.global_position - host.global_position
					flat.y = 0.0
					if flat.length_squared() > 0.0001:
						_dir = flat.normalized()
				_phase = PHASE_CHARGE
				_elapsed = 0.0
				host.set_move_override(_dir, host.get_effective_dash_speed(), cfg.dash_duration)
				host.play_dash_sound()
		PHASE_CHARGE:
			# Keep the override fresh (it also decays on its own) and try the one
			# contact hit the charge is allowed.
			if not _struck and host.get_move_target() != null:
				if host.global_position.distance_to(host.get_move_target().global_position) <= cfg.dash_contact_radius:
					_struck = host.perform_dash_strike(cfg.dash_contact_radius)
					if not _struck:
						# Target died/vanished mid-charge: do not keep rolling hits.
						_struck = true
			if _elapsed >= cfg.dash_duration:
				_phase = PHASE_RECOVERY
				_elapsed = 0.0
				host.set_move_override(Vector3.ZERO, 0.0, cfg.dash_recovery)
		PHASE_RECOVERY:
			if _elapsed >= cfg.dash_recovery:
				host.state_machine_change_to(&"chase")

## Hardened: clamp dash speed/time.
func _validated_dash(speed: float, time: float) -> Dictionary:
    if not is_finite(speed) or speed <= 0.0:
        speed = 12.0
    if not is_finite(time) or time <= 0.0:
        time = 0.3
    speed = clampf(speed, 1.0, 40.0)
    time = clampf(time, 0.05, 2.0)
    return {"speed": speed, "time": time}

