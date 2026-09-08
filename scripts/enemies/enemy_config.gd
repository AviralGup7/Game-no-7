class_name EnemyConfig
extends Resource

## Static, data-driven definition of one enemy archetype. Instances live under
## res://data/enemies/ and are loaded + validated by the ContentRegistry. Runtime
## per-enemy values are kept in EnemyStats so configs are never mutated mid-run.

@export var archetype_id: StringName = &""
@export var display_name: String = ""
@export var scene: PackedScene = null
@export var max_health: float = 10.0
@export var move_speed: float = 2.0
@export var acceleration: float = 8.0
@export var attack_damage: float = 5.0
@export var attack_range: float = 1.5
@export var attack_cooldown: float = 1.2
@export var attack_windup: float = 0.35
@export var score_value: int = 10
@export var currency_value: int = 1
@export var knockback_resistance: float = 0.0
## How far this enemy will first notice a target (0 => always alert).
@export var detect_range: float = 0.0
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

## --- Death effects (exploder / splitter) ---------------------------------
@export var explodes_on_death: bool = false
@export var death_blast_radius: float = 3.0
## Blast damage as a multiple of attack_damage.
@export var death_blast_damage_scale: float = 1.5
## Archetype id spawned when this enemy dies (empty = no split).
@export var splits_into: StringName = &""
@export var split_count: int = 0

@export_multiline var balance_notes: String = ""
@export var ai_behavior: StringName = &"melee"
@export var ranged_range: float = 8.0
@export var ranged_cooldown: float = 2.0
@export var ranged_windup: float = 0.5
@export var projectile_speed: float = 10.0
@export var projectile_count: int = 1
@export var projectile_damage_scale: float = 1.0
@export var preferred_distance: float = 4.0
@export var strafe_speed: float = 1.5
@export var death_blast_radius: float = 0.0
@export var death_blast_damage_scale: float = 0.0
@export var split_count: int = 0
@export var splits_into: StringName = &""

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
	if death_blast_radius < 0.0:
		problems.append("death_blast_radius cannot be negative")
	if death_blast_damage_scale < 0.0:
		problems.append("death_blast_damage_scale cannot be negative")
	if split_count < 0:
		problems.append("split_count cannot be negative")
	if split_count > 0 and String(splits_into).is_empty():
		problems.append("split_count > 0 requires splits_into")
	return problems
