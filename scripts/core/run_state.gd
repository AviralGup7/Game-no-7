class_name RunState
extends RefCounted

## Runtime-only state for a single run. Never written directly to disk; the only
## serialization path is summary() / lifetime-export which omit live node refs and
## transient objects. Owned by GameRoot and reset per run.
##
## `selected_upgrades` remains the authoritative progression mirror. The rest of
## the build fields are a read-only serialization mirror used by summaries and
## SaveManager; live weapon/skill instances remain owned by their components.

const BUILD_SCHEMA_VERSION := 1

var run_id: int = 0
## `rng_seed`, not `seed`: `seed()` is a built-in global function. The serialized
## key stays "seed" so existing saves keep loading.
var rng_seed: int = 0
var arena_id: StringName = &"default_arena"
var mode_id: StringName = &"standard"
var current_wave: int = 0
var score: int = 0
var currency: int = 0
var kills: int = 0
var combo: int = 0
var best_combo: int = 0
var bosses_slain: int = 0
var damage_taken: float = 0.0
var elapsed_seconds: float = 0.0
var player_alive: bool = true
var paused: bool = false
var victory: bool = false
var upgrade_choices: Array[StringName] = []
var selected_upgrades: Dictionary = {}          # upgrade_id -> stack count
var active_modifiers: Array[StringName] = []
## This wave's folded rule multipliers (mutators + adaptive director), published by WaveManager at
## every wave start and read by RunScorekeeper and WeaponManager. Live state only, on purpose: the
## numbers are derived from `active_modifiers` plus the director, so the ids are what a save carries
## and a resumed run recomputes them at the next wave launch. Keeping floats here would let a
## restored save disagree with the wave it re-rolled them for.
var modifiers: WaveModifiers = WaveModifiers.neutral()
var equipped_weapons: Array[StringName] = []
var equipped_skills: Array[StringName] = []
var build_archetypes: Array[StringName] = []
var completed_objectives: Array[StringName] = []
var run_statistics: Dictionary = {}
## Objective-mode live progress. `objective_progress` is the mode-specific counter
## (relics banked for Collect, or beacon-health percent for Defend); GameMode /
## the objective director interpret it. Runtime-only, mirrored into summaries.
var objective_progress: int = 0
var objective_failed: bool = false


func reset() -> void:
	run_id = 0
	rng_seed = 0
	arena_id = &"default_arena"
	mode_id = &"standard"
	current_wave = 0
	score = 0
	currency = 0
	kills = 0
	combo = 0
	best_combo = 0
	bosses_slain = 0
	damage_taken = 0.0
	elapsed_seconds = 0.0
	player_alive = true
	paused = false
	victory = false
	upgrade_choices.clear()
	selected_upgrades.clear()
	active_modifiers.clear()
	modifiers = WaveModifiers.neutral()
	equipped_weapons.clear()
	equipped_skills.clear()
	build_archetypes.clear()
	completed_objectives.clear()
	run_statistics.clear()
	objective_progress = 0
	objective_failed = false


## Add a score delta and update state. Guards against negative drift.
func add_score(delta: int) -> void:
	if not is_finite(float(delta)):
		delta = 0
	score = clampi(score + delta, 0, 999999999)


func add_currency(delta: int) -> void:
	if not is_finite(float(delta)):
		delta = 0
	currency = clampi(currency + delta, 0, 999999999)


func add_kill() -> void:
	kills += 1


func add_boss_kill() -> void:
	bosses_slain += 1


func set_combo(value: int) -> void:
	combo = maxi(value, 0)
	if combo > best_combo:
		best_combo = combo


func add_damage_taken(amount: float) -> void:
	damage_taken += maxf(amount, 0.0)


## Update the serializable build mirror from a component-owned snapshot. IDs are
## normalized to StringNames, duplicates are removed while preserving loadout order.
func set_build_snapshot(snapshot: Dictionary) -> void:
	equipped_weapons = _unique_ids(snapshot.get("equipped_weapons", []))
	equipped_skills = _unique_ids(snapshot.get("equipped_skills", []))
	build_archetypes = _unique_ids(snapshot.get("build_archetypes", []))


func build_snapshot() -> Dictionary:
	return {
		"schema_version": BUILD_SCHEMA_VERSION,
		"seed": rng_seed,
		"current_wave": current_wave,
		"equipped_weapons": equipped_weapons.duplicate(),
		"equipped_skills": equipped_skills.duplicate(),
		"build_archetypes": build_archetypes.duplicate(),
		"selected_upgrades": selected_upgrades.duplicate(),
		"active_modifiers": active_modifiers.duplicate(),
	}


## Publish one wave's folded rules. Called by WaveManager at wave launch (and nowhere else), which
## is what keeps `active_modifiers` honest: the ids shown in the run summary, written to the save and
## folded into this wave's multipliers are now the same array rather than one that nobody wrote.
func set_wave_modifiers(mods: WaveModifiers) -> void:
	modifiers = mods if mods != null else WaveModifiers.neutral()
	active_modifiers = modifiers.mutator_ids.duplicate()


func _unique_ids(raw_values: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if not raw_values is Array:
		return out
	for raw in raw_values:
		var id := StringName(String(raw))
		if String(id).is_empty() or id in out:
			continue
		out.append(id)
	return out


## A safe, serializable snapshot suitable for a run-summary screen, analytics or
## SaveManager's last-run build record. No live node references are included.
func summary() -> Dictionary:
	return {
		"run_id": run_id,
		"seed": rng_seed,
		"arena_id": String(arena_id),
		"mode_id": String(mode_id),
		"current_wave": current_wave,
		"score": score,
		"currency": currency,
		"kills": kills,
		"combo": combo,
		"best_combo": best_combo,
		"bosses_slain": bosses_slain,
		"damage_taken": damage_taken,
		"elapsed_seconds": elapsed_seconds,
		"player_alive": player_alive,
		"victory": victory,
		"objective_progress": objective_progress,
		"objective_failed": objective_failed,
		"selected_upgrades": selected_upgrades.duplicate(),
		"active_modifiers": active_modifiers.duplicate(),
		"completed_objectives": completed_objectives.duplicate(),
		"build": build_snapshot(),
		"equipped_weapons": equipped_weapons.duplicate(),
		"equipped_skills": equipped_skills.duplicate(),
		"build_archetypes": build_archetypes.duplicate(),
	}
