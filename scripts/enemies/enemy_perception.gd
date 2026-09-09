class_name EnemyPerception
extends RefCounted

## The "brain" layer that stops enemies from being omniscient homing missiles.
## Research summary (docs/ENEMY_AI_RESEARCH.md): players read "alive" from
## stimulus -> reaction -> memory, never from instant perfect pursuit.
##
## Pure RefCounted (no nodes): every input is passed explicitly each update,
## so the exact same module runs in-game and in headless unit tests.
##
## Status machine:
##   UNAWARE      -> wandering idle; wakes via sight or sound
##   REACTING     -> stimulus registered, reaction timer runs (the enemy turns
##                   to look before committing — a human blink, not a lag bug)
##   ENGAGED      -> full pursuit/combat (vision or always-aware archetypes)
##   INVESTIGATING-> sight lost (or a noise heard): march to the last known /
##                   noisy point, linger, then forget
##
## Sight = range + FOV cone + line of sight through the nav grid (an enemy
## will not shoot or sprint at a player it cannot see through a pillar).
## Sound = note_noise(): nearby hits, kills and player attacks pull attention
## even without sight ("pack alert" propagation).

enum Status { UNAWARE, REACTING, ENGAGED, INVESTIGATING }

const INVESTIGATE_ARRIVE_RADIUS := 1.2

var status: int = Status.UNAWARE
var last_seen_pos := Vector3.ZERO
var investigate_pos := Vector3.ZERO
var reaction_left := 0.0

var vision_range := 16.0
var fov_degrees := 360.0
var hearing_range := 8.0
var reaction_base := 0.2
var memory_time := 3.0
var always_aware := false
## Multiplier applied while the enemy is "looking around" (idle glance). A
## human glancing across the room genuinely sees farther for a moment — this
## is the safety net that makes corner-camped players eventually noticed.
var attention_boost := 1.0

var _fov_cos := 1.0
var _los_check: Callable = Callable()
var _memory_left := 0.0
var _has_investigate := false


func configure(vision_range_value: float, fov_value: float, hearing_value: float,
		reaction_value: float, memory_value: float, always_aware_value: bool) -> void:
	vision_range = maxf(vision_range_value, 0.0)
	fov_degrees = clampf(fov_value, 0.0, 360.0)
	hearing_range = maxf(hearing_value, 0.0)
	reaction_base = maxf(reaction_value, 0.0)
	memory_time = maxf(memory_value, 0.0)
	always_aware = always_aware_value
	_fov_cos = cos(0.5 * deg_to_rad(fov_degrees))


## (from: Vector3, to: Vector3) -> bool. Empty Callable = open world (tests,
## arenas without a nav grid).
func set_los_check(check: Callable) -> void:
	_los_check = check


func reset() -> void:
	status = Status.UNAWARE
	last_seen_pos = Vector3.ZERO
	investigate_pos = Vector3.ZERO
	reaction_left = 0.0
	_memory_left = 0.0
	_has_investigate = false


func update(delta: float, eye: Vector3, facing: Vector3, target_pos: Vector3, target_exists: bool) -> void:
	if not target_exists:
		reset()
		return
	if always_aware:
		last_seen_pos = target_pos
		_has_investigate = false
		if status != Status.ENGAGED:
			status = Status.ENGAGED
			reaction_left = 0.0
		return
	if visible_now(eye, facing, target_pos):
		last_seen_pos = target_pos
		if status == Status.UNAWARE:
			reaction_left = reaction_base
			status = Status.REACTING
		elif status == Status.INVESTIGATING:
			# Spotted while prowling: instant commitment, no reaction delay.
			_has_investigate = false
			reaction_left = 0.0
			status = Status.ENGAGED
		if status == Status.REACTING:
			reaction_left -= delta
			if reaction_left <= 0.0:
				status = Status.ENGAGED
		return
	# Lost sight.
	match status:
		Status.UNAWARE:
			pass
		Status.REACTING:
			# Flashed into view then hid: remember where, briefly.
			_start_investigation(last_seen_pos, memory_time * 0.5)
		Status.ENGAGED:
			# Keep pressing toward the last known position for a while —
			# humans do not give up the instant target loses cover.
			_start_investigation(last_seen_pos, memory_time)
		Status.INVESTIGATING:
			_memory_left -= delta
			if _memory_left <= 0.0:
				_has_investigate = false
				status = Status.UNAWARE


## A sound in the world: hits on allies, kills, player attacks/dodges.
## intensity 0..1 scales the hearing radius; strong sounds wake UNAWARE
## enemies into investigation, and cut the REACTING reaction time in half.
func note_noise(pos: Vector3, intensity: float, eye: Vector3) -> void:
	if intensity <= 0.0 or hearing_range <= 0.0:
		return
	if not is_finite(pos.x) or not is_finite(pos.z):
		return
	var reach := hearing_range * (0.4 + 0.6 * clampf(intensity, 0.0, 1.0))
	if eye.distance_to(pos) > reach:
		return
	match status:
		Status.UNAWARE:
			_start_investigation(pos, maxf(memory_time * 0.6, 1.5))
		Status.REACTING:
			reaction_left = minf(reaction_left, reaction_base * 0.5)
		Status.INVESTIGATING:
			# New, louder clue: head there instead.
			investigate_pos = pos
		Status.ENGAGED:
			pass


func visible_now(eye: Vector3, facing: Vector3, target_pos: Vector3) -> bool:
	var to := target_pos - eye
	to.y = 0.0
	var d := to.length()
	if d > vision_range * maxf(attention_boost, 1.0):
		return false
	if d < 0.01:
		return true
	var dir := to / d
	if fov_degrees < 360.0:
		var f := facing
		f.y = 0.0
		if f.length_squared() < 0.001:
			return false  # no facing data -> cannot see into a partial cone
		if dir.dot(f.normalized()) < _fov_cos - 1.0e-4:
			return false
	if _los_check.is_valid():
		if not bool(_los_check.call(eye, target_pos)):
			return false
	return true


func can_engage() -> bool:
	return status == Status.ENGAGED


func has_investigate_point() -> bool:
	return _has_investigate


func investigate_point() -> Vector3:
	return investigate_pos


func investigate_done(eye: Vector3) -> bool:
	return _has_investigate and eye.distance_to(investigate_pos) < INVESTIGATE_ARRIVE_RADIUS


func clear_investigation() -> void:
	_has_investigate = false
	status = Status.UNAWARE


## Direction the "head turn" should face while REACTING (last known / noisy).
func look_direction(eye: Vector3) -> Vector3:
	var target := last_seen_pos if last_seen_pos != Vector3.ZERO else investigate_pos
	var d := Vector3(target.x - eye.x, 0.0, target.z - eye.z)
	if d.length_squared() < 0.0001:
		return Vector3.ZERO
	return d.normalized()


func _start_investigation(pos: Vector3, duration: float) -> void:
	_has_investigate = true
	investigate_pos = pos
	_memory_left = duration
	status = Status.INVESTIGATING


func get_status_name() -> String:
	match status:
		Status.UNAWARE:
			return "unaware"
		Status.REACTING:
			return "reacting"
		Status.ENGAGED:
			return "engaged"
		Status.INVESTIGATING:
			return "investigating"
	return "unknown"
