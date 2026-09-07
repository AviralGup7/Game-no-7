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
@export var navigation_target_update_interval: float = 0.2
@export var color_tint: Color = Color.WHITE
@export var tags: Array[StringName] = []
@export var unlock_wave: int = 1
@export var elite_eligible: bool = false
@export var spawn_priority: int = 0
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
	if score_value < 0:
		problems.append("score_value cannot be negative")
	if currency_value < 0:
		problems.append("currency_value cannot be negative")
	if unlock_wave < 1:
		problems.append("unlock_wave must be >= 1")
	return problems
