class_name HazardConfig
extends ValidatedConfig

## Authored data for one arena hazard. Instances live under res://data/hazards/ and
## are discovered by ContentRegistry, exactly like skills and status effects.
##
## The hazard SYSTEM implements two mechanics; everything else is content:
##   "pulse"  a discrete burst. Either it fires on a period (fire vent) or it waits
##            for a victim to walk into it and then detonates on a cooldown
##            (pressure plate). Optional telegraph time before the burst.
##   "field"  an effect that applies while a victim stands in the volume — spike bed,
##            healing ward, slowing pool. `victim_cooldown` throttles re-application
##            per victim, so a spike bed hurts once a second and not once a frame.
## A field may also be given an orbit, which is what a moving ember is: travel is a
## property of the placement, not a sixth code path.
##
## Content that reuses a mechanic is one .tres file, with no edit to any core system
## (docs/EXTENDING.md). `mechanic` is validated against VALID_MECHANICS at load, so a
## typo in an authored file is a hard authoring error instead of a hazard that silently
## does nothing — the failure mode the string-keyed layout this replaces had.
##
## Resources are SHARED between every placement of this config, so nothing mutable may
## live here: timers, per-victim cooldowns and marker references belong to HazardInstance.

const MECHANIC_PULSE := &"pulse"
const MECHANIC_FIELD := &"field"
const VALID_MECHANICS := [MECHANIC_PULSE, MECHANIC_FIELD]

const TRIGGER_PERIODIC := &"periodic"
const TRIGGER_PROXIMITY := &"proximity"
const VALID_TRIGGERS := [TRIGGER_PERIODIC, TRIGGER_PROXIMITY]

@export var hazard_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Which of the two mechanics drives this hazard ("pulse" or "field").
@export var mechanic: StringName = MECHANIC_PULSE
## How a pulse is armed: on its period, or when something steps on it.
@export var trigger: StringName = TRIGGER_PERIODIC

## Effect radius: the burst area (pulse) or the standing area (field). The visual disc is
## built from this same number, so a wider hitbox can never be a guess.
@export_range(0.25, 12.0, 0.05) var radius: float = 2.0
## Radius used to *detect* a victim, when that differs from the effect radius
## (a plate is stood on at 2 m and detonates at 3.5 m). <= 0 means "use radius".
@export_range(0.0, 12.0, 0.05) var trigger_radius: float = 0.0

## "pulse": seconds between detonations, and the warning window before one. A field has
## no burst clock at all, so it authors 0 and the timer never runs.
@export_range(0.0, 60.0, 0.05) var period: float = 4.0
@export_range(0.0, 10.0, 0.05) var telegraph: float = 0.0
## "pulse": seconds the hazard must wait after detonating before it can fire again
## (the plate's re-arm). Independent of `period`, which drives periodic vents.
@export_range(0.0, 60.0, 0.05) var fire_cooldown: float = 0.0
## "field": minimum seconds between two applications to the SAME victim. This is the
## throttle that used to be a stringly-keyed per-victim cooldown in node metadata.
@export_range(0.0, 10.0, 0.05) var victim_cooldown: float = 0.0
## How often a hazard looks for victims at all. 0 = every physics tick; the field
## hazards run at 0.05 (3 ticks), which is well inside their own radius at walking
## speed and cuts the scan rate by ~3x. Periodic pulses ignore this: they only need
## a query on the tick they detonate.
@export_range(0.0, 0.25, 0.005) var scan_interval: float = 0.0

## Burst/contact damage. In a "field" this is per application (throttled by
## victim_cooldown), never per second — healing is the only per-second channel.
@export_range(0.0, 200.0, 0.5) var damage: float = 0.0
## Falloff name consumed by AreaDamage ("none", "linear" or "sweet").
@export var falloff: StringName = &"none"
## Damage type carried into the payload. Defaults to physical, which is what AreaDamage
## and DamagePayload have always used for hazard hits; switching a disc to "fire" makes
## frost armour meaningful against it, so it is authored deliberately per hazard.
@export var damage_type: StringName = &"physical"
@export_range(0.0, 40.0, 0.5) var knockback: float = 0.0
@export var knock_up: bool = false
## Continuous player regeneration inside a field (hp per second).
@export_range(0.0, 100.0, 0.5) var heal_per_second: float = 0.0
## Status effect stamped on affected victims ("" = none). Existence and duration are
## cross-checked against the status table by ContentLoader._validate_references.
@export var status_effect_id: StringName = &""
@export_range(1, 8) var status_stacks: int = 1

@export var affects_player: bool = true
@export var affects_enemies: bool = true
## Proximity trigger must be pressed by the player specifically (plate: the player
## arms it, the enemies eat the blast).
@export var proximity_needs_player: bool = false
## Beneficial hazards are drawn on the minimap ring and never counted as threats.
@export var is_beneficial: bool = false

## Orbit: > 0 makes the hazard circle its authored position at `arena_half * fraction`
## (clamped to the min/max below), which is how a mover stays inside any arena size.
@export_range(0.0, 0.9, 0.01) var orbit_radius_fraction: float = 0.0
@export_range(2.0, 16.0, 0.5) var orbit_radius_min: float = 4.0
@export_range(2.0, 20.0, 0.5) var orbit_radius_max: float = 10.0
@export_range(0.05, 4.0, 0.05) var orbit_speed: float = 1.1

## DamagePayload attribution, surfaced in damage numbers and the debug overlay.
@export var source_id: StringName = &"hazard"
## Optional visual. The gameplay tick never reads these: they are handed to the marker
## once, at build time (alpha lives in the colour so there is one alpha to reason about).
@export var marker_color: Color = Color(1.0, 0.5, 0.2, 0.35)
@export_range(0.0, 4.0, 0.05) var marker_emission: float = 0.4
## Emission while arming (telegraph ramp / player standing on a plate).
@export_range(0.0, 4.0, 0.05) var marker_emission_armed: float = 1.2
@export_range(0.01, 1.0, 0.01) var marker_height: float = 0.08
@export var tags: Array[StringName] = []


## Radius used to find victims (may be smaller than the effect radius).
## Resolves one authored hazard by id. The registry owns the tables at runtime; tools and
## the headless harness (which runs without autoloads) get the same resource straight from
## res://data/hazards/, so an id means the same thing in both — the same shape the arena
## picker in RunSetupPanel uses. `load()` is cached by Godot, so this is not disk I/O.
static func resolve(hazard_id: StringName) -> HazardConfig:
	var path := "res://data/hazards/%s.tres" % String(hazard_id)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as HazardConfig


func contact_radius() -> float:
	return radius if trigger_radius <= 0.0 else minf(trigger_radius, radius)


func is_periodic() -> bool:
	return mechanic == MECHANIC_PULSE and trigger == TRIGGER_PERIODIC


func is_proximity() -> bool:
	return mechanic == MECHANIC_PULSE and trigger == TRIGGER_PROXIMITY


## True when this hazard travels, i.e. its position is not its authored origin.
func moves() -> bool:
	return orbit_radius_fraction > 0.0


## Seconds of warning before a periodic burst; 0 when there is nothing to telegraph.
func telegraph_window() -> float:
	if mechanic != MECHANIC_PULSE or telegraph <= 0.0:
		return 0.0
	return minf(telegraph, period * 0.5)


func has_status() -> bool:
	return not String(status_effect_id).is_empty()


func needs_health() -> bool:
	return heal_per_second > 0.0


## Seconds from the hazard's own clock between two victim scans.
func scan_period() -> float:
	return maxf(scan_interval, 0.0)


func debug_label() -> String:
	return "%s@(%d,%d)" % [String(hazard_id), int(round(radius * 10.0)), int(round(period * 10.0))]


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(hazard_id).is_empty():
		problems.append("hazard_id is empty")
	if mechanic not in VALID_MECHANICS:
		problems.append("unknown mechanic '%s' (a hazard is either 'pulse' or 'field')" % String(mechanic))
	if trigger not in VALID_TRIGGERS:
		problems.append("unknown trigger '%s' (valid: periodic, proximity)" % String(trigger))
	if radius <= 0.0 or not is_finite(radius):
		problems.append("radius must be > 0 and finite")
	if trigger_radius > 0.0 and trigger_radius > radius:
		problems.append("trigger_radius must not exceed radius (a victim could be hit before being detected)")
	# Every authored number is checked for finiteness: a NaN period makes a hazard
	# never fire, and a NaN radius makes it hit everything in the bucket.
	for value in [period, telegraph, fire_cooldown, victim_cooldown, scan_interval, damage, knockback, heal_per_second, orbit_radius_fraction, orbit_speed, marker_emission]:
		if not is_finite(value):
			problems.append("a numeric field must be finite")
			break
	if damage < 0.0 or heal_per_second < 0.0 or knockback < 0.0:
		problems.append("damage, heal_per_second and knockback cannot be negative")
	if falloff not in AreaDamage.VALID_FALLOFFS:
		problems.append("falloff must be none, linear or sweet")
	if not affects_player and not affects_enemies:
		problems.append("affects_player and affects_enemies are both false — this hazard can never affect anything")
	if is_beneficial and (damage > 0.0 or has_status()):
		problems.append("a beneficial hazard must not deal damage or apply a status")
	if mechanic == MECHANIC_PULSE:
		if period <= 0.0:
			problems.append("pulse mechanics need period > 0")
		if telegraph < 0.0 or telegraph >= period:
			problems.append("telegraph must be in [0, period) so a burst is not telegraphed forever")
		if trigger == TRIGGER_PROXIMITY and fire_cooldown <= 0.0:
			problems.append("a proximity pulse needs fire_cooldown > 0 or it detonates every tick")
	if mechanic == MECHANIC_FIELD and scan_interval <= 0.0 and victim_cooldown <= 0.0:
		problems.append("a field with neither a scan_interval nor a victim_cooldown re-applies every physics tick")
	if status_stacks < 1:
		problems.append("status_stacks must be >= 1")
	if orbit_radius_fraction > 0.0:
		if orbit_radius_min > orbit_radius_max:
			problems.append("orbit_radius_min exceeds orbit_radius_max")
		if orbit_radius_max < radius:
			problems.append("orbit_radius_max is smaller than the effect radius")
	if marker_height <= 0.0 or not is_finite(marker_height):
		problems.append("marker_height must be > 0 (it is also the disc's collision-free lift off the floor)")
	if marker_color.a <= 0.0:
		problems.append("marker_color is fully transparent — the hazard would be invisible while still dealing damage")
	return problems
