class_name EnemyIdleState
extends EnemyState

## Idle is no longer "stand frozen until told": it is the unaware side of a
## human-like awareness loop (see EnemyPerception).
##
##   * UNAWARE:      wander slowly around the spawn spot (personal radius from
##                   the rolled personality) with random "look around" pauses —
##                   a pack of loafers, not a statuesque ambush.
##   * REACTING:     turn to face the stimulus and hold the beat while the
##                   reaction timer runs ("huh?").
##   * INVESTIGATING: pace to the last-seen / noisy point, linger, forget.
##   * ENGAGED:      commit to Chase (or Ranged).
##
## When perception reports no awareness (vision 0 + hearing 0 + no noise) the
## enemy falls back to the legacy idle-in-place behavior, so always-aware
## configs and headless fixtures behave exactly as before.

const LOOK_PAUSE_MIN := 0.3
const LOOK_PAUSE_MAX := 0.9
const WANDER_INTERVAL_MIN := 1.5
const WANDER_INTERVAL_MAX := 3.0
const WANDER_SPEED_FRACTION := 0.35
const INVESTIGATE_SPEED_FRACTION := 0.7
const LINGER_TIME := 0.6

var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var _look_timer := 0.0
var _linger_timer := 0.0


func _init() -> void:
	super(&"idle")


func enter(host: EnemyBase) -> void:
	host.set_desired_move(Vector3.ZERO, 0.0)
	_wander_timer = 0.0
	_look_timer = 0.0
	_linger_timer = 0.0
	if host.get_perception() != null:
		host.get_perception().attention_boost = 1.0


func physics_update(host: EnemyBase, delta: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	if not host.is_alive():
		return
	var target := host.get_move_target()
	if target == null:
		host.set_desired_move(Vector3.ZERO, 0.0)
		return
	var cfg := host.get_config()
	if cfg == null:
		return
	var perception := host.get_perception()
	# Attention baseline: only an ACTIVE look-pause widens sight
	# (EnemyPerception.attention_boost). Resetting here — before any branch —
	# guarantees a raised boost can never leak into REACTING or
	# INVESTIGATING from a wander branch of a previous tick.
	perception.attention_boost = 1.0
	match perception.status:
		EnemyPerception.Status.ENGAGED:
			if String(cfg.ai_behavior) == "ranged":
				host.state_machine_change_to(&"ranged")
			else:
				host.state_machine_change_to(&"chase")
		EnemyPerception.Status.REACTING:
			# The "huh?" beat: face the stimulus, hold still.
			var look := perception.look_direction(host.global_position)
			if look != Vector3.ZERO:
				host.face_direction(look)
			host.set_desired_move(Vector3.ZERO, 0.0)
		EnemyPerception.Status.INVESTIGATING:
			_investigate(host, perception, cfg, delta)
		_:
			_unaware_wander(host, cfg, delta)


## PACE to the last-known / noisy point, linger there, then forget.
func _investigate(host: EnemyBase, perception: EnemyPerception, _cfg: EnemyConfig, delta: float) -> void:
	if not perception.has_investigate_point():
		perception.clear_investigation()
		return
	var point := perception.investigate_point()
	if perception.investigate_done(host.global_position):
		# Linger (check the corner) before losing interest.
		_linger_timer += delta
		host.set_desired_move(Vector3.ZERO, 0.0)
		if _linger_timer >= LINGER_TIME:
			perception.clear_investigation()
			_linger_timer = 0.0
		return
	_linger_timer = 0.0
	var fallback := Vector3.ZERO
	var to := point - host.global_position
	to.y = 0.0
	if to.length_squared() > 0.0001:
		fallback = to.normalized()
	var steer := host.get_navigation_direction_toward(point, fallback, delta)
	host.set_desired_move(steer, host.get_effective_speed() * INVESTIGATE_SPEED_FRACTION)
	if steer != Vector3.ZERO:
		host.face_direction(steer)


## UNAWARE: slow personal wander around the home spot with random look-pauses.
## (Always-aware archetypes never land here with a live target — their
## perception is ENGAGED by construction.)
func _unaware_wander(host: EnemyBase, cfg: EnemyConfig, delta: float) -> void:
	_look_timer -= delta
	# Looking around genuinely extends sight for the beat (see attention_boost).
	host.get_perception().attention_boost = 1.6 if _look_timer > 0.0 else 1.0
	if _look_timer > 0.0:
		host.set_desired_move(Vector3.ZERO, 0.0)
		return
	_wander_timer -= delta
	var personality := host.get_personality()
	var radius := cfg.wander_radius * (personality.wander_scale if personality != null else 1.0)
	if _wander_timer <= 0.0:
		_wander_timer = WANDER_INTERVAL_MIN \
				+ (WANDER_INTERVAL_MAX - WANDER_INTERVAL_MIN) * host.personality_roll()
		var roll := host.personality_roll()
		if roll < 0.3:
			# Look around a random direction (standing still, head turned).
			_look_timer = LOOK_PAUSE_MIN + (LOOK_PAUSE_MAX - LOOK_PAUSE_MIN) * host.personality_roll()
			var angle := host.personality_roll() * TAU
			host.face_direction(Vector3(cos(angle), 0.0, sin(angle)))
			_wander_target = host.get_home_position()
			return
		var angle := host.personality_roll() * TAU
		var r := radius * host.personality_roll()
		_wander_target = host.get_home_position() + Vector3(cos(angle) * r, 0.0, sin(angle) * r)
	var to := _wander_target - host.global_position
	to.y = 0.0
	if to.length_squared() < 0.04:
		host.set_desired_move(Vector3.ZERO, 0.0)
		return
	var fallback := to.normalized()
	var steer := host.get_navigation_direction_toward(_wander_target, fallback, delta)
	host.set_desired_move(steer, host.get_effective_speed() * WANDER_SPEED_FRACTION)
	if steer != Vector3.ZERO:
		host.face_direction(steer)


static func host_set_still(host: EnemyBase) -> void:
	if host != null:
		host.set_desired_move(Vector3.ZERO, 0.0)
