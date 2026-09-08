class_name BossPhaseConfig
extends Resource

## One data-driven boss phase entry (see BossController). Phases sort by descending
## `threshold` (health fraction that activates the phase); phase index 0 is the
## intro phase. Authored on the boss scene's BossController node so boss tuning is
## content, not code.

@export var phase_name: String = "Phase"
## Health fraction (0..1) at or below which this phase becomes active.
@export var threshold: float = 1.0
## Multiplicative stat bumps applied ON ENTERING the phase (they stack on top of
## wave scaling via EnemyBase.apply_phase_modifiers; shared configs untouched).
@export var damage_mult: float = 1.0
@export var speed_mult: float = 1.0
## Ability ids available in this phase: "slam", "charge", "summon".
@export var abilities: Array[StringName] = [&"slam"]
## Seconds between ability casts while this phase is active (<= 0 uses the
## controller's default cadence, shortened when enraged).
@export var ability_interval: float = 0.0


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(phase_name).strip_edges().is_empty():
		problems.append("phase_name is empty")
	if threshold < 0.0 or threshold > 1.0:
		problems.append("threshold must be in [0,1]")
	if damage_mult <= 0.0 or speed_mult <= 0.0:
		problems.append("phase multipliers must be > 0")
	if abilities.is_empty():
		problems.append("phase has no abilities")
	for ability in abilities:
		if ability not in [&"slam", &"charge", &"summon"]:
			problems.append("unknown ability id: %s" % String(ability))
	if ability_interval < 0.0:
		problems.append("ability_interval cannot be negative")
	return problems


func to_dict() -> Dictionary:
	return {
		"name": phase_name,
		"threshold": threshold,
		"damage_mult": damage_mult,
		"speed_mult": speed_mult,
		"abilities": abilities.duplicate(),
		"interval": ability_interval,
	}
