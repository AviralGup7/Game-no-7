class_name EnemyEliteKit
extends RefCounted

## Elite affixes for EnemyBase (see EliteAffix): the affix cache, the blend of their
## tints, the archetype scale bump that makes an elite read at a glance, the FRENZIED
## attack-cadence multiplier and the VAMPIRIC heal hook.
##
## The cache is read by other systems through the host's facade
## (`is_elite()` / `get_elite_affixes()`), and SpawnManager checks
## `get_elite_affixes()` for the VOLATILE death blast, so the array handed out is a
## copy — mutation from outside must not change what this enemy is.

## Scale bump applied on top of the archetype's visual scale for elites.
const ELITE_SCALE_MULT := 1.12
## Meta key the affixes are published under (debug overlay / analytics).
const META_KEY := "elite_affixes"

var _affixes: Array[StringName] = []


## Mark this enemy elite. The serial-rolled approach offset is deliberately left
## alone: re-rolling here would break run determinism.
func set_affixes(host: EnemyBase, affixes: Array) -> void:
	_affixes.clear()
	for raw in affixes:
		_affixes.append(StringName(String(raw)))
	host.set_meta(META_KEY, _affixes.duplicate())
	var tint := tint()
	var feedback := host.get_feedback()
	if feedback != null:
		feedback.recolor(tint)
	var cfg := host.get_config()
	host.get_presentation().apply_visual_scale(host, (cfg.visual_scale if cfg != null else 1.0) * ELITE_SCALE_MULT)


func is_elite() -> bool:
	return not _affixes.is_empty()


## Copy by design: callers (SpawnManager, UI) inspect, they never mutate.
func get_affixes() -> Array:
	return _affixes.duplicate()


## Blended affix tint (white when no affix is known).
func tint() -> Color:
	var blended := Color.WHITE
	for affix in _affixes:
		blended = blended.blend(EliteAffix.affix_tint(affix))
	return blended


func has(affix: StringName) -> bool:
	return affix in _affixes


## FRENZIED attacks faster below its health trigger; every other elite swings on the
## archetype's clock. Never mutates the shared config.
func attack_cooldown_multiplier(health_fraction: float) -> float:
	if has(EliteAffix.FRENZIED) and health_fraction < EliteAffix.FRENZIED_HP_TRIGGER:
		return EliteAffix.FRENZIED_COOLDOWN_MULT
	return 1.0


## VAMPIRIC elites sustain off the damage they deal (routed through the host's
## attack_hit signal, so the heal lands exactly once per reported hit).
func heal_from_hit(host: EnemyBase, result: DamageResult) -> void:
	if result == null or not result.accepted or not host.is_alive():
		return
	var health := host.get_health_component()
	if health != null:
		health.heal(result.final_amount * EliteAffix.VAMPIRIC_HEAL_RATIO)
