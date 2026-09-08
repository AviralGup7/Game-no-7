class_name DamageResult
extends RefCounted

## Result returned by a HealthComponent / combat pipeline after a damage event is
## evaluated. Kept as an object (not just signals) so synchronous callers can read
## the outcome directly; duplicate-emission bugs are avoided by making scoring
## react to this object rather than raw events.

## Whether the damage was accepted (target took it) at all.
var accepted: bool = false

## The amount actually dealt to health after mitigation.
var final_amount: float = 0.0

## Whether this hit rolled as a critical hit.
var was_critical: bool = false

## Whether the target died as a result of this hit.
var target_died: bool = false

## The knockback that ended up applied to the target.
var knockback_applied: Vector3 = Vector3.ZERO

## Reason the damage was ignored when !accepted.
var ignored_reason: StringName = &""

## Status effects successfully applied on this hit.
var status_effects_applied: Array[StringName] = []


func _init() -> void:
	pass


static func accepted_reason() -> StringName:
	return &"accepted"


## Rejection reason constants (documented in the spec).
const IGNORE_INVULNERABLE: StringName = &"invulnerable"
const IGNORE_DEAD: StringName = &"dead"
const IGNORE_INVALID_PAYLOAD: StringName = &"invalid_payload"
const IGNORE_FRIENDLY_FIRE: StringName = &"friendly_fire_disabled"
const IGNORE_OUT_OF_RANGE: StringName = &"out_of_range"
const IGNORE_BLOCKED: StringName = &"blocked"
const IGNORE_DUPLICATE_HIT: StringName = &"duplicate_hit"

## Hardened: clamp result amounts.
func _validated_final(amt: float) -> float:
    if not is_finite(amt) or amt < 0.0:
        return 0.0
    return clampf(amt, 0.0, 999999.0)

