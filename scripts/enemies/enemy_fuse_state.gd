class_name EnemyFuseState
extends EnemyState

## Exploder self-detonation: inside fuse_range the enemy plants, flashes repeatedly
## (readable warning) and explodes after fuse_time via EnemyBase.detonate_self(),
## which routes through the normal exactly-once death path — the blast itself is the
## existing SpawnManager death-effect dispatch (explodes_on_death). Taking a hit
## interrupts the fuse (Hurt), which is the player's counterplay; once finished, the
## detonation cannot be stopped.

var _elapsed := 0.0
var _blink := 0.0


func _init() -> void:
	super(&"fuse")


func enter(host: EnemyBase) -> void:
	_elapsed = 0.0
	_blink = 0.0
	host.set_desired_move(Vector3.ZERO, 0.0)
	host.play_telegraph_feedback()
	host.play_windup_sound()


func physics_update(host: EnemyBase, delta: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	if not host.is_alive():
		return
	var cfg := host.get_config()
	var fuse := cfg.fuse_time if cfg != null else 0.8
	host.set_desired_move(Vector3.ZERO, 0.0)
	var target := host.get_move_target()
	if target != null:
		host.face_target(target)
	# Accelerating blink as the fuse burns down.
	_blink += delta
	var blink_every := lerpf(0.22, 0.08, clampf(_elapsed / maxf(fuse, 0.01), 0.0, 1.0))
	if _blink >= blink_every:
		_blink = 0.0
		host.play_telegraph_feedback()
	_elapsed += delta
	if _elapsed >= fuse:
		host.play_explosion_sound()
		host.detonate_self()
