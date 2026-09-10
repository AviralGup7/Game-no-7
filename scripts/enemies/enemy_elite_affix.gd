class_name EliteAffix
extends RefCounted

## Elite affix definitions + application for empowered enemies.
## Elites are regular enemies with 1-2 affixes rolled deterministically at spawn
## (SpawnManager decides eligibility via EnemyConfig.elite_eligible + wave).
## Each affix scales stats, tints the visual, and may grant an on-death effect
## handled by the spawner/boss hooks. Pure/static: no tree access.

const SWIFT := &"swift"
const BRUISER := &"bruiser"
const VOLATILE := &"volatile"    # explodes on death (SpawnManager dispatch)
const VAMPIRIC := &"vampiric"    # heals itself for a share of damage dealt (EnemyBase hook)
const ARMORED := &"armored"
const FRENZIED := &"frenzied"    # attacks faster below half health (EnemyBase cadence hook)
const ALL := [SWIFT, BRUISER, VOLATILE, VAMPIRIC, ARMORED, FRENZIED]

const ELITE_HP_MULT := 2.2
const ELITE_DAMAGE_MULT := 1.35
const ELITE_SCORE_MULT := 3.0
const ELITE_CURRENCY_MULT := 3.0
## Fraction of accepted damage dealt that a VAMPIRIC elite heals back per hit.
const VAMPIRIC_HEAL_RATIO := 0.15
## Health fraction below which a FRENZIED elite's attack cooldown is halved-ish.
const FRENZIED_HP_TRIGGER := 0.5
const FRENZIED_COOLDOWN_MULT := 0.55


## Roll 1-2 distinct affixes for an elite of `archetype` at `wave`.
## Deterministic in (seed, spawn_index).
static func roll_affixes(archetype_id: StringName, wave: int, run_seed: int, spawn_index: int) -> Array[StringName]:
	var rng := RngService.make_generator(run_seed + hash(String(archetype_id)), RngService.STREAM_AI + spawn_index)
	var pool: Array = ALL.duplicate()
	# Volatile needs a death-blast handler; keep it for melee brutes early.
	var count := 1
	if wave >= 6 and rng.randf() < 0.35:
		count = 2
	var out: Array[StringName] = []
	for i in range(count):
		if pool.is_empty():
			break
		var idx := rng.randi_range(0, pool.size() - 1)
		out.append(pool[idx])
		pool.remove_at(idx)
	return out


## Stat multipliers for one affix: {hp, damage, speed, knockback_resist, score}.
static func affix_stats(affix: StringName) -> Dictionary:
	match affix:
		SWIFT:
			return {"hp": 0.85, "damage": 1.0, "speed": 1.5, "knockback_resist": 0.1, "score": 1.2}
		BRUISER:
			return {"hp": 1.8, "damage": 1.3, "speed": 0.85, "knockback_resist": 0.4, "score": 1.5}
		VOLATILE:
			return {"hp": 1.0, "damage": 1.1, "speed": 1.1, "knockback_resist": 0.0, "score": 1.4}
		VAMPIRIC:
			return {"hp": 1.2, "damage": 1.15, "speed": 1.0, "knockback_resist": 0.2, "score": 1.4}
		ARMORED:
			return {"hp": 1.4, "damage": 1.0, "speed": 0.9, "knockback_resist": 0.75, "score": 1.4}
		FRENZIED:
			return {"hp": 1.0, "damage": 1.2, "speed": 1.15, "knockback_resist": 0.0, "score": 1.3}
	return {"hp": 1.0, "damage": 1.0, "speed": 1.0, "knockback_resist": 0.0, "score": 1.0}


## Combine several affixes multiplicatively (knockback resist takes the max).
static func combine(affixes: Array) -> Dictionary:
	var hp := 1.0
	var dmg := 1.0
	var spd := 1.0
	var kb := 0.0
	var score := 1.0
	for a in affixes:
		var s := affix_stats(StringName(String(a)))
		hp *= float(s["hp"])
		dmg *= float(s["damage"])
		spd *= float(s["speed"])
		kb = maxf(kb, float(s["knockback_resist"]))
		score *= float(s["score"])
	return {"hp": hp, "damage": dmg, "speed": spd, "knockback_resist": kb, "score": score}


## Display names + colors for UI / announcement copy.
static func affix_display_name(affix: StringName) -> String:
	match affix:
		SWIFT:
			return "Swift"
		BRUISER:
			return "Bruiser"
		VOLATILE:
			return "Volatile"
		VAMPIRIC:
			return "Vampiric"
		ARMORED:
			return "Armored"
		FRENZIED:
			return "Frenzied"
	return String(affix).capitalize()


static func affix_tint(affix: StringName) -> Color:
	match affix:
		SWIFT:
			return Color(0.5, 0.9, 1.0)
		BRUISER:
			return Color(1.0, 0.5, 0.3)
		VOLATILE:
			return Color(1.0, 0.3, 0.2)
		VAMPIRIC:
			return Color(0.8, 0.2, 0.6)
		ARMORED:
			return Color(0.7, 0.7, 0.8)
		FRENZIED:
			return Color(1.0, 0.85, 0.2)
	return Color.WHITE


## Volatile death-blast tuning (radius, damage scale vs the elite's attack).
static func volatile_blast() -> Dictionary:
	return {"radius": 3.5, "damage_scale": 2.0, "knockback": 12.0}


## Whether an enemy of `archetype` may spawn elite at `wave` (wave gate +
## config flag). Pure so planners and tests agree.
static func elite_allowed(config: EnemyConfig, wave: int) -> bool:
	if config == null or not config.elite_eligible:
		return false
	return wave >= 3


## Elite chance for one spawn slot at `wave` (0 before wave 3, capped 25%).
static func elite_chance(wave: int) -> float:
	if wave < 3:
		return 0.0
	return minf(0.05 + float(wave - 3) * 0.02, 0.25)
