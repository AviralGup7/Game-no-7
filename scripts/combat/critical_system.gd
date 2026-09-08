class_name CriticalSystem
extends RefCounted

## Central critical-hit math: deterministic rolls on an isolated RNG stream,
## pity-timer escalation (each non-crit nudges the next roll), and overkill
## bonuses. Pure/static so weapons, skills and hazards share one tuning point.

const DEFAULT_PITY_STEP := 0.02
const MAX_PITY_BONUS := 0.25


## Roll one crit. `pity_stacks` escalates the effective chance; returns
## {crit: bool, new_pity: int} so callers can persist the pity counter.
static func roll(base_chance: float, bonus: float, pity_stacks: int, rng: RngService, salt: int = RngService.STREAM_CRITS) -> Dictionary:
	if not is_finite(base_chance) or not is_finite(bonus):
		base_chance = clampf(base_chance if is_finite(base_chance) else 0.0, 0.0, 1.0)
		bonus = clampf(bonus if is_finite(bonus) else 0.0, -1.0, 1.0)
	var pity_bonus := minf(float(maxi(pity_stacks, 0)) * DEFAULT_PITY_STEP, MAX_PITY_BONUS)
	var effective := clampf(base_chance + bonus + pity_bonus, 0.0, 1.0)
	var crit := rng != null and is_instance_valid(rng) and rng.chance(salt, effective)
	return {"crit": crit, "new_pity": 0 if crit else maxi(pity_stacks, 0) + 1}


## Apply the crit multiplier to a damage value.
static func apply_multiplier(damage: float, multiplier: float, was_crit: bool) -> float:
	if not was_crit:
		return maxf(damage, 0.0)
	return maxf(damage, 0.0) * maxf(multiplier, 1.0)


## Expected-damage factor 1 + chance*(mult-1): used by DPS estimates and AI.
static func expected_factor(chance: float, multiplier: float) -> float:
	return 1.0 + clampf(chance, 0.0, 1.0) * (maxf(multiplier, 1.0) - 1.0)


## Overkill bonus score: finishing blows that exceed remaining HP by a wide
## margin award style points. Pure function of (dealt, remaining_hp).
static func overkill_bonus(dealt: float, remaining_hp: float) -> int:
	var over := dealt - maxf(remaining_hp, 0.0)
	if over <= 0.0:
		return 0
	return int(minf(over * 0.5, 50.0))


## Crit damage quantized to whole numbers for damage-number display.
static func display_value(damage: float, was_crit: bool) -> int:
	var v := int(round(damage))
	return maxi(v, 2) if was_crit else maxi(v, 1)

## Hardened: clamp crit chance inputs.
func _validated_crit_chance(c: float) -> float:
	if not is_finite(c):
		return 0.0
	return clampf(c, 0.0, 1.0)

