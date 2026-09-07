class_name UpgradeConfig
extends Resource

## Data-driven player upgrade. Applied through the ProgressionComponent interface
## (never by editing arbitrary node properties). Rarity, stack limits, prerequisites,
## exclusions, unlock wave and weighting are validated centrally.

@export var upgrade_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
@export var rarity: StringName = &"common"
@export var max_stacks: int = 99
@export var stat_modifiers: Dictionary = {}
@export var tags: Array[StringName] = []
@export var prerequisites: Array[StringName] = []
@export var exclusions: Array[StringName] = []
@export var unlock_wave: int = 1
@export var weight: float = 1.0
@export var disabled: bool = false

const VALID_RARITIES := [&"common", &"rare", &"epic", &"legendary"]

## Stable modifier keys consumed by ProgressionComponent. Keeping them here in one
## place prevents string-typo drift across configs and application code.
const MODIFIER_KEYS := [
	&"max_health_add",
	&"move_speed_multiplier",
	&"attack_damage_multiplier",
	&"attack_cooldown_multiplier",
	&"damage_resistance_add",
	&"score_multiplier_add",
	&"attack_range_add",
	&"knockback_multiplier",
	&"healing_on_kill",
	&"dodge_cooldown_multiplier",
	&"currency_multiplier_add",
]


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(upgrade_id).is_empty():
		problems.append("upgrade_id is empty")
	if rarity not in VALID_RARITIES:
		problems.append("invalid rarity: %s" % String(rarity))
	if max_stacks < 1:
		problems.append("max_stacks must be >= 1")
	if unlock_wave < 1:
		problems.append("unlock_wave must be >= 1")
	if weight <= 0.0:
		problems.append("weight must be > 0")
	for key in stat_modifiers:
		var s: String = str(key)
		if s not in MODIFIER_KEYS:
			problems.append("unknown modifier key: %s" % s)
		else:
			var value = stat_modifiers[key]
			if not (value is float or value is int):
				problems.append("modifier %s must be numeric" % s)
	return problems


func modifier_value(key: StringName, fallback: float) -> float:
	if stat_modifiers.has(key):
		var v: Variant = stat_modifiers[key]
		if v is float or v is int:
			return float(v)
	return fallback
