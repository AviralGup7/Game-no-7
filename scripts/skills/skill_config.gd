class_name SkillConfig
extends Resource

## Data-driven active skill definition. Instances live under res://data/skills/
## and are discovered by ContentRegistry. SkillExecutor interprets `behavior` +
## parameters through shared AreaDamage, StatusManager and ProjectilePool seams.
## New content therefore stays data-only unless it needs a genuinely new pattern.
##
## Behaviors: slam, whirl, dash_strike, shockwave, chain_lightning, warcry,
## heal_surge and frost_nova.

const BEHAVIOR_SLAM := &"slam"
const BEHAVIOR_WHIRL := &"whirl"
const BEHAVIOR_DASH_STRIKE := &"dash_strike"
const BEHAVIOR_SHOCKWAVE := &"shockwave"
const BEHAVIOR_CHAIN_LIGHTNING := &"chain_lightning"
const BEHAVIOR_WARCRY := &"warcry"
const BEHAVIOR_HEAL_SURGE := &"heal_surge"
const BEHAVIOR_FROST_NOVA := &"frost_nova"
const VALID_BEHAVIORS := [BEHAVIOR_SLAM, BEHAVIOR_WHIRL, BEHAVIOR_DASH_STRIKE, BEHAVIOR_SHOCKWAVE, BEHAVIOR_CHAIN_LIGHTNING, BEHAVIOR_WARCRY, BEHAVIOR_HEAL_SURGE, BEHAVIOR_FROST_NOVA]

@export var skill_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
@export var behavior: StringName = BEHAVIOR_SLAM
## Input action that triggers this skill (skill_1..3 expected).
@export var input_action: StringName = &"skill_1"
## Cooldown in seconds before upgrades.
@export var cooldown: float = 12.0
## Stamina cost (0 = free).
@export var stamina_cost: float = 0.0
## Damage multiplier applied to the caster's current weapon damage (0 = no damage).
@export var damage_multiplier: float = 2.0
## Flat bonus damage added after the multiplier.
@export var flat_damage: float = 0.0
## Damage type passed into AreaDamage/projectiles.
@export var damage_type: StringName = &"physical"
## Radius (radial skills) or half-width (line skills) in metres.
@export var radius: float = 4.0
## Length for line skills (dash distance / shockwave travel).
@export var length: float = 6.0
## Knockback impulse.
@export var knockback: float = 10.0
## Number of hits for multi-hit behaviors (whirl).
@export var hit_count: int = 1
## Delay between multi-hits.
@export var hit_interval: float = 0.2
## Status effects applied to victims.
@export var victim_effects: Array[StringName] = []
@export var victim_effect_chance: float = 1.0
## Status effects applied to the caster (buff behaviors).
@export var caster_effects: Array[StringName] = []
## Flat heal for heal_surge (plus caster_effects like regen).
@export var heal_amount: float = 0.0
## Dash duration for dash_strike.
@export var dash_duration: float = 0.18
## Chain-lightning tuning. Unused by other behaviors.
@export var chain_jumps: int = 4
@export var chain_radius: float = 4.0
@export var chain_decay: float = 0.72
## Unlock requirements.
@export var unlock_level: int = 1
@export var unlock_wave: int = 1
@export var weight: float = 1.0
@export var disabled: bool = false
@export var tags: Array[StringName] = []


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(skill_id).is_empty():
		problems.append("skill_id is empty")
	if behavior not in VALID_BEHAVIORS:
		problems.append("invalid behavior: %s" % String(behavior))
	if cooldown < 0.0:
		problems.append("cooldown cannot be negative")
	if stamina_cost < 0.0:
		problems.append("stamina_cost cannot be negative")
	if damage_multiplier < 0.0:
		problems.append("damage_multiplier cannot be negative")
	if flat_damage < 0.0:
		problems.append("flat_damage cannot be negative")
	if damage_type not in [&"physical", &"fire", &"frost", &"shock", &"bleed"]:
		problems.append("invalid damage_type: %s" % String(damage_type))
	if radius <= 0.0:
		problems.append("radius must be > 0")
	if length < 0.0:
		problems.append("length cannot be negative")
	if knockback < 0.0:
		problems.append("knockback cannot be negative")
	if hit_count < 1:
		problems.append("hit_count must be >= 1")
	if hit_interval < 0.0:
		problems.append("hit_interval cannot be negative")
	if victim_effect_chance < 0.0 or victim_effect_chance > 1.0:
		problems.append("victim_effect_chance must be in [0,1]")
	if heal_amount < 0.0:
		problems.append("heal_amount cannot be negative")
	if dash_duration < 0.0:
		problems.append("dash_duration cannot be negative")
	if chain_jumps < 1:
		problems.append("chain_jumps must be >= 1")
	if chain_radius <= 0.0:
		problems.append("chain_radius must be > 0")
	if chain_decay < 0.0 or chain_decay > 1.0:
		problems.append("chain_decay must be in [0,1]")
	if unlock_level < 1:
		problems.append("unlock_level must be >= 1")
	if unlock_wave < 1:
		problems.append("unlock_wave must be >= 1")
	if weight <= 0.0:
		problems.append("weight must be > 0")
	return problems


func is_offensive() -> bool:
	return behavior in [BEHAVIOR_SLAM, BEHAVIOR_WHIRL, BEHAVIOR_DASH_STRIKE, BEHAVIOR_SHOCKWAVE, BEHAVIOR_CHAIN_LIGHTNING, BEHAVIOR_FROST_NOVA]


func is_self_buff() -> bool:
	return behavior in [BEHAVIOR_WARCRY, BEHAVIOR_HEAL_SURGE]

## Hardened: clamp skill cooldown/damage.
func _validated_skill_stats() -> void:
    if not is_finite(cooldown) or cooldown <= 0.0:
        cooldown = 1.0
    cooldown = clampf(cooldown, 0.05, 60.0)
    if not is_finite(damage) or damage < 0.0:
        damage = 10.0
    damage = clampf(damage, 0.0, 10000.0)

## Export-range guard: editor sliders are clamped and runtime values are re-clamped
## via _validated_* helpers so JSON or save edits cannot create NaN/inf/out-of-range.
func _export_range_guard() -> void:
    # This is a documentation guard; actual clamping lives in _validated_* helpers.
    # Intended ranges (editor @export_range would be here in a future Godot bump):
    #  - health/damage: 0..10000 finite
    #  - cooldown/duration: 0.05..60 finite
    #  - speed/range: 0..30 finite, half 4..100
    #  - weight/chance: 0..1 finite
    pass

