class_name HazardInstance
extends RefCounted

## Mutable state for ONE live hazard: where it is, where it is in its cycle, and who it
## has already touched. The system used to keep these as untyped Dictionary records
## ("kind"/"pos"/"timer"/"node", plus "angle"/"tick" created on first use) which meant a
## typo was a runtime Variant error, a new kind silently did nothing, and every read cost
## a hash lookup in the middle of the tick loop.

## The authored data. Never written to: configs are shared between placements.
var config: HazardConfig = null
## Stable index within the owning system (identity for debug and for the trigger signal).
var slot: int = -1
## Where the designer put it, clamped into the arena. Orbits pivot around this.
var origin: Vector3 = Vector3.ZERO
## Where it currently is. Differs from origin only for orbiting hazards.
var position: Vector3 = Vector3.ZERO

var radius: float = 0.0
var radius_squared: float = 0.0
var contact_radius: float = 0.0
var contact_radius_squared: float = 0.0
var period: float = 0.0
var telegraph: float = 0.0
## Seconds of *game* time since this hazard last detonated, and the remaining re-arm.
var timer: float = 0.0
var rearm: float = 0.0
## Cadence bookkeeping: time accumulated since the last victim scan, and the time that
## scan covered (heal fields integrate over it so a slower scan rate changes nothing).
var scan_timer: float = 0.0
var scanned_delta: float = 0.0
var angle: float = 0.0
## True while a telegraph is running or a player is standing on the trigger.
var armed: bool = false
## Optional visual; may be freed with the arena at any time, so read it via visual().
var marker: HazardMarker = null

## Per-victim re-application throttle, keyed by Node.get_instance_id() and measured on
## the hazard system's own scaled clock. This replaces stringly-keyed cooldowns written
## into the *victim's* metadata, which were slow, serialized with the scene, and — the
## actual bug — ran on the wall clock, so a hitstop of 0.05x spent a 1 s cooldown in
## 50 ms of game time.
var _victim_ready: Dictionary[int, float] = {}
var _next_prune: float = 0.0


static func build(p_config: HazardConfig, p_slot: int, p_origin: Vector3, p_radius: float, p_period: float) -> HazardInstance:
	var instance := HazardInstance.new()
	instance.config = p_config
	instance.slot = p_slot
	instance.origin = p_origin
	instance.position = p_origin
	instance.period = p_period
	instance.apply_radius(p_radius)
	if p_config != null:
		instance.telegraph = p_config.telegraph_window()
	return instance


## Keeps the hitbox and the disc in step: both derive from this one number. A placement
## that overrides the radius moves the detection circle with it unless the config asked
## for a smaller one (the plate's 2 m tread inside a 3.5 m blast).
func apply_radius(p_radius: float) -> void:
	radius = p_radius if p_radius > 0.25 else 0.25
	radius_squared = radius * radius
	var authored_contact := radius
	if config != null and config.trigger_radius > 0.0:
		authored_contact = config.trigger_radius
	contact_radius = minf(authored_contact, radius)
	contact_radius_squared = contact_radius * contact_radius


func covers(target: Vector3, pad: float) -> bool:
	var dx := target.x - position.x
	var dz := target.z - position.z
	var reach := radius + pad
	return dx * dx + dz * dz <= reach * reach


## Seconds until this hazard is allowed to look for victims again.
func scan_due() -> bool:
	if config == null:
		return true
	return scan_timer >= config.scan_period()


## Marks the start of a scan window and returns how much game time it covers.
func begin_scan() -> float:
	scanned_delta = scan_timer
	scan_timer = 0.0
	return scanned_delta


func advance(delta: float) -> void:
	scan_timer += delta
	if rearm > 0.0:
		rearm = maxf(rearm - delta, 0.0)
	if period > 0.0:
		timer += delta
		if timer >= period * 2.0:
			# A hazard that never detonated (paused world, zero victims) must not let its
			# clock drift arbitrarily far past the period.
			timer = period


## True when a periodic burst should fire now; consumes the timer.
func burst_due() -> bool:
	if period <= 0.0 or timer < period:
		return false
	timer = 0.0
	return true


## Progress of the telegraph ramp in [0,1], for the marker and for tests.
func telegraph_level() -> float:
	if telegraph <= 0.0 or period <= 0.0:
		return 0.0
	var remaining := period - timer
	if remaining > telegraph:
		return 0.0
	return clampf(1.0 - remaining / telegraph, 0.0, 1.0)


func can_fire() -> bool:
	return rearm <= 0.0


func fire() -> void:
	if config != null:
		rearm = config.fire_cooldown


## Orbiting hazards travel on a circle around the position they were authored at. The
## radius comes from the arena so one config works in a 12 m pit and a 20 m crucible, and
## it is additionally capped so the circle never leaves the floor — an orbit that would
## escape shrinks to a still hazard instead. (Previously a mover ignored its authored
## position and circled the arena centre, so the coordinate in the layout was a lie.)
const ORBIT_WALL_MARGIN := 1.0


func orbit_radius(arena_half: float) -> float:
	if config == null or not config.moves():
		return 0.0
	var span := arena_half - ORBIT_WALL_MARGIN - Vector2(origin.x, origin.z).length()
	if span <= config.orbit_radius_min:
		return 0.0
	return clampf(arena_half * config.orbit_radius_fraction, config.orbit_radius_min, minf(config.orbit_radius_max, span))


func advance_orbit(delta: float, arena_half: float) -> void:
	if config == null or not config.moves():
		return
	var orbit := orbit_radius(arena_half)
	if orbit <= 0.0:
		position = origin
		return
	angle += config.orbit_speed * delta
	position = Vector3(origin.x + cos(angle) * orbit, origin.y, origin.z + sin(angle) * orbit)


func victim_ready(victim_id: int, now: float) -> bool:
	if not _victim_ready.has(victim_id):
		return true
	return float(_victim_ready[victim_id]) <= now


func stamp_victim(victim_id: int, now: float) -> void:
	var cooldown := config.victim_cooldown if config != null else 0.0
	if cooldown <= 0.0:
		# An unthrottled field (the healing ward) gains nothing from a table it never
		# consults, so it does not pay a dictionary write per victim per scan.
		return
	_victim_ready[victim_id] = now + cooldown
	_next_prune = maxf(_next_prune, now + 1.0)


## Expired keys are useless and victims die, so the table is swept once a second;
## without this a long run leaks one entry per victim per hazard.
func prune(now: float) -> void:
	if _victim_ready.is_empty() or now < _next_prune:
		return
	_next_prune = now + 1.0
	for key in _victim_ready.keys():
		if float(_victim_ready[key]) <= now:
			_victim_ready.erase(key)


func clear_history() -> void:
	_victim_ready.clear()


## The marker belongs to the arena and a world rebuild can free it while hazards are
## still ticking, so every visual touch goes through here: one validity check, then the
## caller may dereference freely. Gameplay never depends on the answer.
func visual() -> HazardMarker:
	if marker == null or not is_instance_valid(marker):
		return null
	return marker


func position_is_sane() -> bool:
	return is_finite(position.x) and is_finite(position.y) and is_finite(position.z)


func label() -> String:
	if config == null:
		return "hazard#%d" % slot
	return "%s#%d" % [String(config.hazard_id), slot]


func debug_snapshot() -> Dictionary:
	return {
		"label": label(),
		"mechanic": String(config.mechanic) if config != null else "?",
		"position": position,
		"radius": radius,
		"timer": snappedf(timer, 0.01),
		"rearm": snappedf(rearm, 0.01),
		"armed": armed,
		"throttled": _victim_ready.size(),
	}
