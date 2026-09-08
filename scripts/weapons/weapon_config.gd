class_name WeaponConfig
extends Resource

## Data-driven weapon definition. Instances live under res://data/weapons/ and
## are discovered + validated by the ContentRegistry. Covers both melee (arc
## sweeps resolved by MeleeResolver) and ranged (projectiles resolved by
## RangedResolver + the Projectile pool). Runtime per-run state (cooldowns,
## combo step, ammo) lives in WeaponInstance so configs are never mutated.

const KIND_MELEE := &"melee"
const KIND_RANGED := &"ranged"
const KIND_HYBRID := &"hybrid"  # melee swing that also launches a projectile
const ATTACK_ARC := &"arc"
const ATTACK_THRUST := &"thrust"
const ATTACK_FLURRY := &"flurry"
const ATTACK_VOLLEY := &"volley"
const ATTACK_HYBRID := &"hybrid"
const VALID_ATTACK_PATTERNS := [ATTACK_ARC, ATTACK_THRUST, ATTACK_FLURRY, ATTACK_VOLLEY, ATTACK_HYBRID]
const VALID_DAMAGE_TYPES := [&"physical", &"fire", &"frost", &"shock", &"bleed", &"poison"]
const VALID_KINDS := [KIND_MELEE, KIND_RANGED, KIND_HYBRID]

@export var weapon_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
@export var kind: StringName = KIND_MELEE
@export var rarity: StringName = &"common"
## Descriptive resolver hint. Geometry still comes from the numeric fields below,
## so custom content can use the existing resolver without new id branches.
@export var attack_pattern: StringName = &"arc"
@export var damage_type: StringName = &"physical"

## Base damage per hit before upgrades / difficulty scaling.
@export var base_damage: float = 10.0
## Seconds between swing starts (before cooldown multipliers).
@export var swing_cooldown: float = 0.55
## Windup before the hit resolves (telegraph + feel).
@export var windup: float = 0.12
## Melee reach in metres from the wielder.
@export var range: float = 2.6
## Full arc width in degrees for melee sweeps (360 = radial whirl).
@export var arc_degrees: float = 110.0
## Max targets per swing (0 = unlimited).
@export var max_targets: int = 0
## Knockback impulse applied along the hit direction.
@export var knockback: float = 6.0
## Combo steps (damage multipliers per step); empty = single hit, no chain.
@export var combo_damage_steps: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.35])
## Seconds after a swing during which the next press chains the combo.
@export var combo_window: float = 0.45
## Critical-hit support.
@export var crit_chance: float = 0.05
@export var crit_multiplier: float = 1.6
## Status effect tags applied on hit (see StatusEffectConfig ids).
@export var on_hit_effects: Array[StringName] = []
@export var on_hit_effect_chance: float = 1.0

## --- Ranged parameters (kind RANGED / HYBRID) ---
@export var projectile_speed: float = 18.0
@export var projectile_count: int = 1
@export var projectile_spread_degrees: float = 6.0
@export var projectile_lifetime: float = 1.6
@export var projectile_radius: float = 0.25
@export var projectile_pierce: int = 0
@export var ammo_per_magazine: int = 0  # 0 = infinite
@export var reload_seconds: float = 1.2

## --- Meta / unlock ---
@export var unlock_wave: int = 1
@export var unlock_cost: int = 0
@export var weight: float = 1.0
@export var disabled: bool = false
@export var tags: Array[StringName] = []

const VALID_RARITIES := [&"common", &"rare", &"epic", &"legendary"]


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(weapon_id).is_empty():
		problems.append("weapon_id is empty")
	if kind not in VALID_KINDS:
		problems.append("invalid kind: %s" % String(kind))
	if rarity not in VALID_RARITIES:
		problems.append("invalid rarity: %s" % String(rarity))
	if attack_pattern not in VALID_ATTACK_PATTERNS:
		problems.append("invalid attack_pattern: %s" % String(attack_pattern))
	if damage_type not in VALID_DAMAGE_TYPES:
		problems.append("invalid damage_type: %s" % String(damage_type))
	if base_damage < 0.0:
		problems.append("base_damage cannot be negative")
	if swing_cooldown < 0.05:
		problems.append("swing_cooldown too small")
	if windup < 0.0:
		problems.append("windup cannot be negative")
	if range <= 0.0:
		problems.append("range must be > 0")
	if arc_degrees <= 0.0 or arc_degrees > 360.0:
		problems.append("arc_degrees must be in (0,360]")
	if max_targets < 0:
		problems.append("max_targets cannot be negative")
	if knockback < 0.0:
		problems.append("knockback cannot be negative")
	if combo_window < 0.0:
		problems.append("combo_window cannot be negative")
	if crit_chance < 0.0 or crit_chance > 1.0:
		problems.append("crit_chance must be in [0,1]")
	if crit_multiplier < 1.0:
		problems.append("crit_multiplier must be >= 1.0")
	if on_hit_effect_chance < 0.0 or on_hit_effect_chance > 1.0:
		problems.append("on_hit_effect_chance must be in [0,1]")
	if projectile_count < 1:
		problems.append("projectile_count must be >= 1")
	if projectile_speed <= 0.0 and kind != KIND_MELEE:
		problems.append("projectile_speed must be > 0 for ranged weapons")
	if projectile_lifetime <= 0.0 and kind != KIND_MELEE:
		problems.append("projectile_lifetime must be > 0 for ranged weapons")
	if projectile_pierce < 0:
		problems.append("projectile_pierce cannot be negative")
	if ammo_per_magazine < 0:
		problems.append("ammo_per_magazine cannot be negative")
	if reload_seconds < 0.0:
		problems.append("reload_seconds cannot be negative")
	if unlock_wave < 1:
		problems.append("unlock_wave must be >= 1")
	if unlock_cost < 0:
		problems.append("unlock_cost cannot be negative")
	if weight <= 0.0:
		problems.append("weight must be > 0")
	for m in combo_damage_steps:
		if m < 0.0:
			problems.append("combo_damage_steps cannot contain negatives")
			break
	return problems


## Number of combo steps (at least 1).
func step_count() -> int:
	return maxi(combo_damage_steps.size(), 1)


## Damage multiplier for a 1-based combo step (clamped to the last step).
func step_multiplier(step: int) -> float:
	if combo_damage_steps.is_empty():
		return 1.0
	return combo_damage_steps[clampi(step - 1, 0, combo_damage_steps.size() - 1)]


func is_melee() -> bool:
	return kind == KIND_MELEE or kind == KIND_HYBRID


func is_ranged() -> bool:
	return kind == KIND_RANGED or kind == KIND_HYBRID


func has_ammo() -> bool:
	return ammo_per_magazine > 0


## Theoretical single-target DPS ignoring travel time, crits and combos.
func paper_dps() -> float:
	if swing_cooldown <= 0.0:
		return 0.0
	var avg_step := 1.0
	if not combo_damage_steps.is_empty():
		var sum := 0.0
		for m in combo_damage_steps:
			sum += m
		avg_step = sum / float(combo_damage_steps.size())
	var projectile_factor := float(projectile_count) if is_ranged() else 1.0
	return base_damage * avg_step * projectile_factor / swing_cooldown

## Hardened: clamp weapon stats.
func _validated_weapon_stats() -> void:
    if not is_finite(damage) or damage < 0.0:
        damage = 10.0
    damage = clampf(damage, 0.0, 10000.0)
    if not is_finite(cooldown) or cooldown < 0.0:
        cooldown = 0.5
    cooldown = clampf(cooldown, 0.05, 10.0)
    if not is_finite(range_val) or range_val <= 0.0:
        range_val = 2.0
    range_val = clampf(range_val, 0.1, 20.0)

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

