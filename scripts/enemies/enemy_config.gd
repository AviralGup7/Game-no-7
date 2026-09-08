class_name EnemyConfig
extends ValidatedConfig

## Static, data-driven definition of one enemy archetype. Instances live under
## res://data/enemies/ and are loaded + validated by the ContentRegistry. Runtime
## per-enemy values are kept in EnemyStats so configs are never mutated mid-run.

@export var archetype_id: StringName = &""
@export var display_name: String = ""
@export var scene: PackedScene = null
@export_range(0.0, 10000.0, 0.5) var max_health: float = 10.0
@export_range(0.0, 30.0, 0.1) var move_speed: float = 2.0
@export_range(0.0, 100.0, 0.5) var acceleration: float = 8.0
@export_range(0.0, 10000.0, 0.5) var attack_damage: float = 5.0
@export_range(0.1, 30.0, 0.1) var attack_range: float = 1.5
@export_range(0.05, 60.0, 0.05) var attack_cooldown: float = 1.2
@export_range(0.0, 10.0, 0.05) var attack_windup: float = 0.35
@export_range(0, 100000) var score_value: int = 10
@export_range(0, 10000) var currency_value: int = 1
@export_range(0.0, 1.0, 0.01) var knockback_resistance: float = 0.0
## How far this enemy will first notice a target (0 => always alert).
@export_range(0.0, 100.0, 0.5) var detect_range: float = 0.0
## Seconds spent in the "hurt" reaction after taking damage.
@export var hurt_duration: float = 0.25
## World-space XZ radius used to keep enemies inside the arena bounds.
@export var bounds_radius: float = 0.6
@export var navigation_target_update_interval: float = 0.2
@export var color_tint: Color = Color.WHITE
## Applied to VisualRoot for a distinct silhouette (heavy bigger, fast smaller).
@export var visual_scale: float = 1.0
@export var tags: Array[StringName] = []
@export var unlock_wave: int = 1
@export var elite_eligible: bool = false
@export var spawn_priority: int = 0

## --- Behaviour / ranged archetype ---------------------------------------
## "melee" closes to attack_range; "ranged" orbits at preferred_distance and volleys.
@export var ai_behavior: StringName = &"melee"
## Maximum distance a ranged archetype will fire from.
@export var ranged_range: float = 14.0
## Seconds between volleys.
@export var ranged_cooldown: float = 2.0
## Telegraph time before a volley is released.
@export var ranged_windup: float = 0.5
@export var projectile_speed: float = 12.0
@export var projectile_count: int = 1
## Total spread cone in degrees when projectile_count > 1.
@export var projectile_spread: float = 8.0
## Projectile damage as a fraction of attack_damage.
@export var projectile_damage_scale: float = 0.8
## Distance a ranged archetype tries to hold from its target.
@export var preferred_distance: float = 9.0
## Strafe speed as a fraction of the effective move speed.
@export var strafe_speed: float = 0.6

## --- Melee identity -------------------------------------------------------
## Damage absorbed during an attack windup before the hit interrupts into Hurt.
## 0 = every accepted hit interrupts (grunts); heavies/bosses set high poise so
## their slow swings stay threatening instead of being stun-locked.
@export var poise: float = 0.0
## Seconds spent back-pedaling after a melee hit lands (hit-and-run identity,
## used by fast skirmishers). 0 = stay planted for the cooldown.
@export var attack_retreat_time: float = 0.0

## --- Dasher archetype -------------------------------------------------------
## 0 = this archetype never dashes. > 0: within this distance the enemy prefers
## a telegraphed charge over walking in (see EnemyDashState).
@export var dash_trigger_range: float = 0.0
## Telegraph before the charge releases (feedback flash + crouch).
@export var dash_windup: float = 0.45
@export var dash_speed: float = 13.0
## How long the charge travels before recovery.
@export var dash_duration: float = 0.45
## Contact radius for the one hit a charge may land.
@export var dash_contact_radius: float = 1.2
## Damage of the charge hit as a multiple of attack_damage.
@export var dash_damage_scale: float = 1.0
## Vulnerable stagger after the charge ends.
@export var dash_recovery: float = 0.7
## Seconds between dashes (also gates melee fallback).
@export var dash_cooldown: float = 3.0

## --- Exploder archetype -----------------------------------------------------
## 0 = never self-detonates. > 0: inside this radius the enemy plants, flashes
## and detonates after fuse_time (see EnemyFuseState); the blast itself still
## comes from the explodes_on_death/death_blast fields below.
@export var fuse_range: float = 0.0
@export var fuse_time: float = 0.8

## --- Death effects (exploder / splitter) ---------------------------------
@export var explodes_on_death: bool = false
@export var death_blast_radius: float = 3.0
## Blast damage as a multiple of attack_damage.
@export var death_blast_damage_scale: float = 1.5
## Archetype id spawned when this enemy dies (empty = no split).
@export var splits_into: StringName = &""
@export var split_count: int = 0
## When true the SplitManager burst-spawns children around the parent's death
## position; when false (or when spawning is impossible) children join the
## pending queue like any other spawn.
@export var split_burst: bool = true

@export_multiline var balance_notes: String = ""

const MIN_HEALTH: float = 1.0
const MIN_MOVE_SPEED: float = 0.1


## Return a list of human-readable validation problems. Empty means valid.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(archetype_id).is_empty():
		problems.append("archetype_id is empty")
	if scene == null:
		problems.append("scene is null for %s" % String(archetype_id))
	if max_health < MIN_HEALTH:
		problems.append("max_health too low")
	if move_speed < MIN_MOVE_SPEED:
		problems.append("move_speed too low")
	if acceleration <= 0.0:
		problems.append("acceleration must be > 0")
	if attack_damage < 0.0:
		problems.append("attack_damage cannot be negative")
	if knockback_resistance < 0.0 or knockback_resistance > 1.0:
		problems.append("knockback_resistance must be in [0,1]")
	if hurt_duration < 0.0:
		problems.append("hurt_duration cannot be negative")
	if visual_scale <= 0.0:
		problems.append("visual_scale must be > 0")
	if score_value < 0:
		problems.append("score_value cannot be negative")
	if currency_value < 0:
		problems.append("currency_value cannot be negative")
	if unlock_wave < 1:
		problems.append("unlock_wave must be >= 1")
	if ai_behavior not in [&"melee", &"ranged"]:
		problems.append("ai_behavior must be melee or ranged")
	if ranged_range <= 0.0:
		problems.append("ranged_range must be > 0")
	if ranged_cooldown < 0.2:
		problems.append("ranged_cooldown too small")
	if ranged_windup < 0.0:
		problems.append("ranged_windup cannot be negative")
	if projectile_speed <= 0.0:
		problems.append("projectile_speed must be > 0")
	if projectile_count < 1:
		problems.append("projectile_count must be >= 1")
	if projectile_damage_scale < 0.0:
		problems.append("projectile_damage_scale cannot be negative")
	if preferred_distance < 0.0:
		problems.append("preferred_distance cannot be negative")
	if strafe_speed < 0.0:
		problems.append("strafe_speed cannot be negative")
	if poise < 0.0:
		problems.append("poise cannot be negative")
	if attack_retreat_time < 0.0:
		problems.append("attack_retreat_time cannot be negative")
	if dash_trigger_range < 0.0:
		problems.append("dash_trigger_range cannot be negative")
	if dash_trigger_range > 0.0:
		if dash_speed <= 0.0:
			problems.append("dash_speed must be > 0 when dashing is enabled")
		if dash_windup < 0.05:
			problems.append("dash_windup too short to read as a telegraph")
		if dash_duration <= 0.0:
			problems.append("dash_duration must be > 0")
		if dash_contact_radius <= 0.0:
			problems.append("dash_contact_radius must be > 0")
		if dash_damage_scale < 0.0:
			problems.append("dash_damage_scale cannot be negative")
		if dash_recovery < 0.0:
			problems.append("dash_recovery cannot be negative")
		if dash_cooldown < dash_duration:
			problems.append("dash_cooldown must cover at least the dash itself")
	if fuse_range < 0.0:
		problems.append("fuse_range cannot be negative")
	if fuse_range > 0.0 and fuse_time < 0.1:
		problems.append("fuse_time too short to react to")
	if death_blast_radius < 0.0:
		problems.append("death_blast_radius cannot be negative")
	if death_blast_damage_scale < 0.0:
		problems.append("death_blast_damage_scale cannot be negative")
	if split_count < 0:
		problems.append("split_count cannot be negative")
	if split_count > 0 and String(splits_into).is_empty():
		problems.append("split_count > 0 requires splits_into")
	return problems
