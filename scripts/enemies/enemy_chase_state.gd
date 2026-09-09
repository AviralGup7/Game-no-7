class_name EnemyChaseState
extends EnemyState

## Chase: pursue the target at the configured move speed, but never in lockstep.
##
## Every enemy re-rolls a MANEUVER on its own clock (0.9–1.8 s, personality
## weighted): close straight in, flank left/right around a personal orbit
## radius, or strafe at range. Packs therefore arrive in staggered arcs —
## the single biggest "scripted horde" tell removed. Griefed enemies (two
## nearby allies killed while wounded) back off briefly before re-committing.
##
## Movement always routes through EnemyNavigator: line of sight -> direct,
## otherwise the shared flow field around pillars/landmark (no clipping).
## Archetypes with a dash_trigger_range launch a telegraphed charge instead of
## walking in — gated by the personality's dash_willingness so some charges
## simply never come (fakes read as hesitation). Exploders ignite inside
## fuse_range. Falls back to Idle when the target disappears.

enum Maneuver { STRAIGHT, FLANK_A, FLANK_B, STRAFE }

const MANEUVER_INTERVAL_MIN := 0.9
const MANEUVER_INTERVAL_MAX := 1.8
const ORBIT_DIST_MIN := 2.4
const ORBIT_DIST_MAX := 4.4

var _maneuver: int = Maneuver.STRAIGHT
var _maneuver_timer := 0.0
var _flank_sign := 1.0


func _init() -> void:
	super(&"chase")


func enter(host: EnemyBase) -> void:
	host.set_desired_move(Vector3.ZERO, 0.0)
	_maneuver_timer = 0.0


func physics_update(host: EnemyBase, delta: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	if not host.is_alive():
		return
	var target := host.get_move_target()
	if target == null:
		host.set_desired_move(Vector3.ZERO, 0.0)
		host.state_machine_change_to(&"idle")
		return
	var cfg := host.get_config()
	if cfg == null:
		return
	var flat_offset := target.global_position - host.global_position
	flat_offset.y = 0.0
	var dist := flat_offset.length()
	# Ranged archetypes orbit + volley instead of closing to melee.
	if String(cfg.ai_behavior) == "ranged":
		host.state_machine_change_to(&"ranged")
		return
	# Exploder: inside the fuse radius, plant and ignite instead of meleeing.
	if cfg.fuse_range > 0.0 and dist <= cfg.fuse_range:
		host.state_machine_change_to(&"fuse")
		return
	# Dasher: prefer a telegraphed charge over walking in once off cooldown —
	# but the personality decides whether THIS individual really commits.
	if cfg.dash_trigger_range > 0.0 and dist <= cfg.dash_trigger_range and dist > cfg.attack_range:
		var willingness := 1.0
		var personality := host.get_personality()
		if personality != null:
			willingness = personality.dash_willingness
		if host.personality_roll() < willingness and host.try_begin_dash():
			host.state_machine_change_to(&"dash")
			return
	if host.target_in_attack_range(target):
		host.set_desired_move(Vector3.ZERO, 0.0)
		host.state_machine_change_to(&"attack")
		return
	# Grief: wounded, cautious enemies back off after nearby allies died.
	if host.is_fear_retreating():
		var away := Vector3.BACK if flat_offset.length_squared() < 0.001 else -flat_offset.normalized()
		host.set_desired_move(away, host.get_effective_speed() * 0.9)
		host.face_direction(away)
		return
	_roll_maneuver(host, cfg, dist, delta)
	var goal := _maneuver_goal(host, target.global_position, flat_offset, dist)
	var to := goal - host.global_position
	to.y = 0.0
	var desired := Vector3.FORWARD
	if to.length_squared() > 0.0001:
		desired = to.normalized()
	var steer := host.get_navigation_direction(desired)
	host.set_desired_move(steer, host.get_effective_speed())
	host.face_direction(steer if steer != Vector3.ZERO else desired)


## Re-roll the maneuver on this enemy's personal clock (deterministic stream).
func _roll_maneuver(host: EnemyBase, cfg: EnemyConfig, dist: float, delta: float) -> void:
	_maneuver_timer -= delta
	if _maneuver_timer > 0.0:
		return
	_maneuver_timer = MANEUVER_INTERVAL_MIN \
			+ (MANEUVER_INTERVAL_MAX - MANEUVER_INTERVAL_MIN) * host.personality_roll()
	var personality := host.get_personality()
	var strafe_chance := cfg.strafe_chance
	var aggressive := 0.5
	var bias := 0.0
	if personality != null:
		aggressive = personality.aggression
		bias = personality.strafe_bias
	strafe_chance *= (1.0 - 0.5 * aggressive)  # aggressive individuals close more
	if dist <= cfg.attack_range * 1.9 and host.personality_roll() < strafe_chance:
		_maneuver = Maneuver.STRAFE
		return
	# Flank side: personality bias picks the preferred shoulder; coin flips the rest.
	var flank_side := host.personality_roll()
	_flank_sign = -1.0 if (flank_side < 0.5) != (bias < 0.0) else 1.0
	var roll := host.personality_roll()
	var flank_weight := 0.35 * (1.0 - 0.4 * aggressive)
	if roll < flank_weight:
		_maneuver = Maneuver.FLANK_A
	elif roll < flank_weight * 2.0:
		_maneuver = Maneuver.FLANK_B
	else:
		_maneuver = Maneuver.STRAIGHT


func _maneuver_goal(host: EnemyBase, target_pos: Vector3, flat_offset: Vector3, dist: float) -> Vector3:
	var to_target := flat_offset.normalized() if flat_offset.length_squared() > 0.001 else Vector3.FORWARD
	var personality := host.get_personality()
	match _maneuver:
		Maneuver.STRAIGHT:
			# Personal approach offset keeps packs fanned (original behavior).
			return host.get_approach_point(target_pos)
		Maneuver.FLANK_A, Maneuver.FLANK_B:
			var side := _flank_sign if _maneuver == Maneuver.FLANK_A else -_flank_sign
			var orbit := ORBIT_DIST_MIN \
					+ (ORBIT_DIST_MAX - ORBIT_DIST_MIN) * (personality.aggression if personality != null else 0.5)
			var perp := Vector3(-to_target.z, 0.0, to_target.x) * side
			# A point beside the lane to the target: arcs in instead of piling on.
			return target_pos + perp * orbit + to_target * (0.5 * orbit)
		Maneuver.STRAFE:
		_:
			# Hold the current band and drift sideways (skirmisher rhythm).
			var perp := Vector3(-to_target.z, 0.0, to_target.x) * _flank_sign
			var hold := clampf(dist, cfg_attack_range(host) * 0.9, cfg_attack_range(host) * 1.4)
			return host.global_position + perp * 0.8 + to_target * (hold - dist)


func cfg_attack_range(host: EnemyBase) -> float:
	var cfg := host.get_config()
	return cfg.attack_range if cfg != null else 1.5


## Hardened: clamp chase speed and validate target each frame.
func _validated_chase(target: Node3D, speed: float) -> Dictionary:
	if target == null or not is_instance_valid(target):
		return {"valid": false, "speed": 0.0}
	if not is_finite(speed) or speed < 0.0:
		speed = 2.0
	speed = clampf(speed, 0.0, 20.0)
	if not target.is_inside_tree():
		return {"valid": false, "speed": speed}
	return {"valid": true, "speed": speed}

func _chase_is_target_valid(t: Node) -> bool:
	return t != null and is_instance_valid(t) and t.is_inside_tree() and t.has_method("get_health_fraction") or t is Node3D
