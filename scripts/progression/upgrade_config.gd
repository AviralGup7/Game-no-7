class_name UpgradeConfig
extends ValidatedConfig

## Data-driven player upgrade. Applied through the ProgressionComponent interface
## (never by editing arbitrary node properties). Rarity, stack limits, prerequisites,
## exclusions, unlock wave and weighting are validated centrally.
##
## `category` and `tags` are descriptive build metadata. They are intentionally
## data-only: the runtime consumers continue to use the stable modifier keys below,
## which keeps new build archetypes discoverable without hardcoding upgrade ids.

@export var upgrade_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
@export var rarity: StringName = &"common"
@export var category: StringName = &"damage"
@export var max_stacks: int = 99
@export var stat_modifiers: Dictionary = {}
@export var tags: Array[StringName] = []
@export var prerequisites: Array[StringName] = []
@export var exclusions: Array[StringName] = []
@export var unlock_wave: int = 1
@export var weight: float = 1.0
@export var disabled: bool = false

const VALID_RARITIES := [&"common", &"rare", &"epic", &"legendary"]
const VALID_CATEGORIES := [
	&"damage", &"defense", &"mobility", &"crit", &"status", &"aoe",
	&"sustain", &"economy", &"projectile", &"skill", &"hybrid",
]

## Stable modifier keys consumed by ProgressionComponent and combat facades. Keeping
## them here in one place prevents string-typo drift across configs and application
## code. Values are authored in decimal form for percentage stats (0.15 = 15%).
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
	&"crit_chance_add",
	&"crit_multiplier_add",
	&"skill_cooldown_multiplier",
	&"skill_damage_multiplier",
	&"area_radius_multiplier",
	&"area_damage_multiplier",
	&"status_chance_add",
	&"status_duration_multiplier",
	&"status_damage_multiplier",
	&"projectile_count_add",
	&"projectile_pierce_add",
	&"stamina_max_add",
	&"stamina_regen_add",
	&"stamina_delay_add",
	&"xp_multiplier_add",
	&"pickup_radius_add",
]


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(upgrade_id).is_empty():
		problems.append("upgrade_id is empty")
	if rarity not in VALID_RARITIES:
		problems.append("invalid rarity: %s" % String(rarity))
	if category not in VALID_CATEGORIES:
		problems.append("invalid category: %s" % String(category))
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
			elif not is_finite(float(value)):
				problems.append("modifier %s must be finite" % s)
	for prereq in prerequisites:
		if String(prereq).is_empty():
			problems.append("prerequisites cannot contain empty ids")
	for exclusion in exclusions:
		if String(exclusion).is_empty():
			problems.append("exclusions cannot contain empty ids")
	if upgrade_id in prerequisites:
		problems.append("upgrade cannot require itself")
	if upgrade_id in exclusions:
		problems.append("upgrade cannot exclude itself")
	return problems


func modifier_value(key: StringName, fallback: float) -> float:
	if stat_modifiers.has(key):
		var v: Variant = stat_modifiers[key]
		if v is float or v is int:
			return float(v)
	return fallback
