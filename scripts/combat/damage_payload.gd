class_name DamagePayload
extends RefCounted

## Immutable-ish description of a damage event. Created by an attacker and handed
## to a HealthComponent (or combat pipeline). Validated before it is applied so
## that invalid/NaN/infinite/negative values never reach gameplay systems.

## Amount of raw damage. Negative/NaN/infinite is invalid.
var amount: float = 0.0

## Who dealt the damage (Node3D attacker, if any).
var source: Node = null

## Stable identifier of the source archetype/weapon (no live node reference).
var source_id: StringName = &"unknown"

## Damage type tag, e.g. &"physical", &"fire". Reserved for future resistances.
var damage_type: StringName = &"physical"

## World-space knockback impulse applied to the target on hit.
var knockback: Vector3 = Vector3.ZERO

## World-space position where the hit connected (for hit FX / floating text).
var hit_position: Vector3 = Vector3.ZERO

## Whether this payload may roll a critical hit.
var can_crit: bool = false

## Multiplier applied on a critical hit. Must be >= 1.0.
var critical_multiplier: float = 1.0

## True once the attacker has rolled a critical hit for this payload. Set by the
## attacker BEFORE the payload is validated/applied; the receiving HealthComponent
## reflects it into DamageResult.was_critical so metadata and result agree.
var was_critical: bool = false

## Status effects (tags) this hit tries to apply. Reserved for future content.
var status_effects: Array[StringName] = []

## Free-form metadata bag (never serialized to disk).
var metadata: Dictionary = {}

## Monotonic creation time in milliseconds. Set at construction.
var timestamp_msec: int = 0


func _init() -> void:
	timestamp_msec = Time.get_ticks_msec()


## Validate the payload. Returns true when the payload may be applied.
func is_valid() -> bool:
	if amount < 0.0:
		return false
	if not is_finite(amount):
		return false
	if critical_multiplier < 1.0:
		return false
	if not is_finite(critical_multiplier):
		return false
	if knockback.x != 0.0 or knockback.y != 0.0 or knockback.z != 0.0:
		if not knockback.is_finite():
			return false
	return true


## Full clone with a replaced amount (mitigation/shield pipelines). Status and
## metadata containers are duplicated deeply so the copy never aliases the original.
func with_amount(new_amount: float) -> DamagePayload:
	var copy := DamagePayload.new()
	copy.amount = maxf(new_amount, 0.0)
	copy.source = source
	copy.source_id = source_id
	copy.damage_type = damage_type
	copy.knockback = knockback
	copy.hit_position = hit_position
	copy.can_crit = can_crit
	copy.critical_multiplier = critical_multiplier
	copy.was_critical = was_critical
	# Deep duplicate prevents aliasing of nested structures in status riders.
	copy.status_effects = status_effects.duplicate(false)
	copy.metadata = metadata.duplicate(true)
	# Preserve original timestamp for audit trails; clone is same event, different amount.
	copy.timestamp_msec = timestamp_msec
	return copy

func is_safely_valid() -> bool:
	return is_valid() and is_finite(amount) and amount >= 0.0
