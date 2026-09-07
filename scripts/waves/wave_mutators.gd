class_name WaveMutators
extends RefCounted

## Wave mutator (arena modifier) definitions + selection.
## Mutators twist a wave's rules — faster horde, armored foes, elite surge, fog,
## bounty-rich prey, explosive deaths. Each mutator declares stat multipliers
## plus flags consumed by the WaveManager/SpawnManager/EnemyBase hooks; nothing
## here touches the tree. Selection is deterministic in (seed, wave).

const SWIFT_HORDE := &"swift_horde"
const IRON_HIDE := &"iron_hide"
const ELITE_SURGE := &"elite_surge"
const GLASS_CANNON := &"glass_cannon"
const BOUNTY_HUNT := &"bounty_hunt"
const VOLATILE_MIX := &"volatile_mix"
const EMBER_WINDS := &"ember_winds"
const ALL := [SWIFT_HORDE, IRON_HIDE, ELITE_SURGE, GLASS_CANNON, BOUNTY_HUNT, VOLATILE_MIX, EMBER_WINDS]


## Full definition: display copy, stat multipliers, behavior flags.
static func definition(mutator_id: StringName) -> Dictionary:
	match mutator_id:
		SWIFT_HORDE:
			return {
				"name": "Swift Horde", "description": "Enemies are 30% faster but 15% frailer.",
				"hp_mult": 0.85, "damage_mult": 1.0, "speed_mult": 1.3,
				"score_mult": 1.1, "elite_bonus": 0.0, "explode_chance": 0.0,
				"burn_tick": 0.0, "severity": &"minor",
			}
		IRON_HIDE:
			return {
				"name": "Iron Hide", "description": "Enemies are much tougher but slower.",
				"hp_mult": 1.6, "damage_mult": 1.0, "speed_mult": 0.85,
				"score_mult": 1.25, "elite_bonus": 0.0, "explode_chance": 0.0,
				"burn_tick": 0.0, "severity": &"major",
			}
		ELITE_SURGE:
			return {
				"name": "Elite Surge", "description": "+20% elite chance. Rich kills.",
				"hp_mult": 1.0, "damage_mult": 1.0, "speed_mult": 1.0,
				"score_mult": 1.2, "elite_bonus": 0.2, "explode_chance": 0.0,
				"burn_tick": 0.0, "severity": &"major",
			}
		GLASS_CANNON:
			return {
				"name": "Glass Cannon", "description": "Everyone hits harder — including you. Enemies deal +40%, take +25%.",
				"hp_mult": 0.8, "damage_mult": 1.4, "speed_mult": 1.0,
				"score_mult": 1.3, "elite_bonus": 0.0, "explode_chance": 0.0,
				"burn_tick": 0.0, "severity": &"major", "player_damage_mult": 1.25,
			}
		BOUNTY_HUNT:
			return {
				"name": "Bounty Hunt", "description": "Double currency, tougher marks.",
				"hp_mult": 1.2, "damage_mult": 1.1, "speed_mult": 1.0,
				"score_mult": 1.0, "currency_mult": 2.0, "elite_bonus": 0.05,
				"explode_chance": 0.0, "burn_tick": 0.0, "severity": &"minor",
			}
		VOLATILE_MIX:
			return {
				"name": "Volatile Mix", "description": "35% of enemies explode on death.",
				"hp_mult": 1.0, "damage_mult": 1.0, "speed_mult": 1.05,
				"score_mult": 1.15, "elite_bonus": 0.0, "explode_chance": 0.35,
				"burn_tick": 0.0, "severity": &"major",
			}
		EMBER_WINDS:
			return {
				"name": "Ember Winds", "description": "Burning air: everything takes fire ticks; burn builds faster.",
				"hp_mult": 1.0, "damage_mult": 1.0, "speed_mult": 1.0,
				"score_mult": 1.2, "elite_bonus": 0.0, "explode_chance": 0.0,
				"burn_tick": 1.5, "severity": &"major",
			}
	return {"name": String(mutator_id), "description": "", "hp_mult": 1.0, "damage_mult": 1.0, "speed_mult": 1.0, "score_mult": 1.0, "elite_bonus": 0.0, "explode_chance": 0.0, "burn_tick": 0.0, "severity": &"minor"}


static func is_known(mutator_id: StringName) -> bool:
	return mutator_id in ALL


## Combine several mutators into one multiplier set (multiplicative stats,
## additive chances, max severity).
static func combine(mutator_ids: Array) -> Dictionary:
	var out := {"hp_mult": 1.0, "damage_mult": 1.0, "speed_mult": 1.0, "score_mult": 1.0, "currency_mult": 1.0, "player_damage_mult": 1.0, "elite_bonus": 0.0, "explode_chance": 0.0, "burn_tick": 0.0, "severity": &"minor"}
	for raw in mutator_ids:
		var d := definition(StringName(String(raw)))
		out["hp_mult"] = float(out["hp_mult"]) * float(d.get("hp_mult", 1.0))
		out["damage_mult"] = float(out["damage_mult"]) * float(d.get("damage_mult", 1.0))
		out["speed_mult"] = float(out["speed_mult"]) * float(d.get("speed_mult", 1.0))
		out["score_mult"] = float(out["score_mult"]) * float(d.get("score_mult", 1.0))
		out["currency_mult"] = float(out["currency_mult"]) * float(d.get("currency_mult", 1.0))
		out["player_damage_mult"] = float(out["player_damage_mult"]) * float(d.get("player_damage_mult", 1.0))
		out["elite_bonus"] = float(out["elite_bonus"]) + float(d.get("elite_bonus", 0.0))
		out["explode_chance"] = maxf(float(out["explode_chance"]), float(d.get("explode_chance", 0.0)))
		out["burn_tick"] = maxf(float(out["burn_tick"]), float(d.get("burn_tick", 0.0)))
		if String(d.get("severity", "minor")) == "major":
			out["severity"] = &"major"
	out["elite_bonus"] = clampf(float(out["elite_bonus"]), 0.0, 0.5)
	out["explode_chance"] = clampf(float(out["explode_chance"]), 0.0, 1.0)
	return out


## Deterministic mutator pick for generated waves: none before wave 4, one from
## wave 4, a second from wave 8. Authored waves declare their own instead.
static func roll_for_wave(wave: int, seed: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if wave < 4:
		return out
	var rng := RngService.make_generator(seed, RngService.STREAM_WAVES + wave * 7)
	var pool: Array = ALL.duplicate()
	# Glass Cannon only from wave 6 (needs player builds to bite back).
	if wave < 6:
		pool.erase(GLASS_CANNON)
	out.append(pool[rng.randi_range(0, pool.size() - 1)])
	if wave >= 8:
		pool.erase(out[0])
		out.append(pool[rng.randi_range(0, pool.size() - 1)])
	return out


## Resolve the active set for a wave: authored declarations win; generated waves
## roll (skipped on a director breather, spiced with an extra on a hot streak).
## Unknown ids are dropped, duplicates collapsed. Pure in (declared, wave, seed).
static func resolve_for_wave(declared: Array, wave: int, seed: int, breather: bool, spice: bool) -> Array[StringName]:
	var out: Array[StringName] = []
	var pool: Array = declared.duplicate()
	if pool.is_empty():
		if breather:
			return out
		for m in roll_for_wave(wave, seed):
			pool.append(m)
		if spice and pool.size() < 2:
			var extra := roll_for_wave(wave + 100, seed)
			for m in extra:
				if m not in pool:
					pool.append(m)
					break
	for raw in pool:
		var id := StringName(String(raw))
		if is_known(id) and id not in out:
			out.append(id)
	return out


## Human-readable banner line for a set of mutators.
static func banner_text(mutator_ids: Array) -> String:
	if mutator_ids.is_empty():
		return ""
	var names: PackedStringArray = []
	for raw in mutator_ids:
		names.append(String(definition(StringName(String(raw))).get("name", String(raw))))
	return "Mutators: " + ", ".join(names)
