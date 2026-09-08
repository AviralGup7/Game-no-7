class_name Damageable
extends CharacterBody3D

## Explicit combat protocol for anything that can receive damage.
##
## GDScript has no interfaces; the documented idiom (and the pattern used by the
## Godot community for polymorphic seams) is an abstract base class in the
## `class_name` + `extends` hierarchy. `Player` and `EnemyBase` both extend this
## class, so every combat system (MeleeResolver, RangedResolver, AreaDamage,
## Projectile, EnemyStriker, ArenaHazards, CombatQuery, Minimap...) can hold a
## typed reference and make direct, compile-checked calls instead of
## `has_method("apply_damage")` + `.call()` string lookups.
##
## Subclasses MUST override `apply_damage()`; `is_alive()` defaults to true and
## should be overridden by anything with a death state. Attackers filter with
## `target is Damageable` — that single check replaces the old
## has_method("apply_damage") / has_method("is_alive") duck-typing pair and makes
## the combat contract enforceable at compile time.

## Rejection reason used by the base implementation when a subclass forgot to
## override the damage intake. Surfaced in DamageResult.ignored_reason so a
## mis-wired entity shows up in diagnostics instead of silently eating hits.
const IGNORE_NOT_IMPLEMENTED: StringName = &"damageable_not_implemented"


## Apply a damage payload to this entity. Returns the synchronous DamageResult
## (accepted/rejected + final amount). The base implementation rejects safely.
## Override in every concrete entity.
func apply_damage(payload: DamagePayload) -> DamageResult:
	var result := DamageResult.new()
	result.ignored_reason = IGNORE_NOT_IMPLEMENTED
	return result


## Whether this entity can currently be targeted and hit. The base
## implementation reports alive; override when the entity owns a death state.
func is_alive() -> bool:
	return true
