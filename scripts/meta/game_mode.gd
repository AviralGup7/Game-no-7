class_name GameMode
extends RefCounted

## Run-mode selection and behaviour. The *definitions* are authored data now
## (`res://data/game_modes/<mode_id>.tres`, `GameModeConfig`); what stays here has to be code: how a
## wave's archetype list is built from a mode's plan rows or its planner rule, which live progress an
## objective label prints, and how a scaling mode re-reads the prestige ladder.
##
## It used to hold both. `CATALOG` was a Dictionary of Dictionaries inside the script that ran the
## modes, and its own doc comment promised that "adding a mode is data-only". It wasn't: each of the
## thirteen accessors re-typed a Dictionary read with its own private default (`upgrade_every`
## defaulted to 2, `boss_interval` to 10), `def()` answered an unknown mode id with Standard's
## record so a stale save or a misnamed file became a playable "Endless waves" run, five modes'
## encounter scripts were `match` arms here, and `narrator_id`, `boss_interval` and `unlock_prestige`
## were authored on all seven modes and read by nothing. `docs/EXTENDING.md` told modders to "append
## an entry to the dict"; now that sentence describes reality: you write a `.tres`.
##
## Pure static API — no tree access. GameRoot stores the active mode id on RunState; WaveManager /
## Main / UI query helpers here.

const MODE_STANDARD := &"standard"
const MODE_BOSS_RUSH := &"boss_rush"
const MODE_SURVIVAL := &"survival"
const MODE_CHALLENGE := &"challenge"
const MODE_CAMPAIGN := &"campaign"
const MODE_DEFEND := &"defend"
const MODE_COLLECT := &"collect"

## The seven shipped ids. Handles for callers, not content: the strings are the file stems under
## `res://data/game_modes/`, and `tests/python/test_regress_run_modes.py` fails if a handle here
## stops naming a file (which is how `unlock_prestige` was able to sit unread for so long).
const MODES: Array[StringName] = [
	MODE_STANDARD, MODE_BOSS_RUSH, MODE_SURVIVAL, MODE_CHALLENGE,
	MODE_CAMPAIGN, MODE_DEFEND, MODE_COLLECT,
]

## Objective vocabulary. The literals belong to `GameModeConfig` (the `.tres` files validate against
## them); these are the handles `ObjectiveDirector`, the setup panel and the HUD match on.
const OBJECTIVE_CLEAR_WAVES := GameModeConfig.OBJECTIVE_CLEAR_WAVES
const OBJECTIVE_SURVIVE_TIME := GameModeConfig.OBJECTIVE_SURVIVE_TIME
const OBJECTIVE_SLAY_BOSSES := GameModeConfig.OBJECTIVE_SLAY_BOSSES
const OBJECTIVE_DEFEND_POINT := GameModeConfig.OBJECTIVE_DEFEND_POINT
const OBJECTIVE_COLLECT := GameModeConfig.OBJECTIVE_COLLECT

## Folder scan for the no-registry path, cached: in the headless harness (no autoloads) the
## alternative is re-listing `res://data/game_modes` for every accessor call. Authored content does
## not change inside a session, and a live game never reaches this path — ContentRegistry answers
## first. Same rule `WaveMutators` and the arena systems follow.
static var _disk_configs: Array[GameModeConfig] = []
static var _disk_scanned := false


static func is_known(mode_id: StringName) -> bool:
	return resolve(mode_id) != null


## Registry first, disk second, and *no stand-in*: `def()` used to hand back Standard's whole record
## for any id it did not recognise, which is indistinguishable from a mode that genuinely wants
## endless waves. Null here means "nobody authored this mode", and `validated()` is where a caller
## opts into the clamp.
static func resolve(mode_id: StringName) -> GameModeConfig:
	if mode_id == &"":
		return null
	if ContentRegistry != null:
		var registered: GameModeConfig = ContentRegistry.get_game_mode(mode_id)
		if registered != null:
			return registered
	for cfg in _all_configs():
		if cfg.mode_id == mode_id:
			return cfg
	return null


## The definition a caller should use, with an unknown id reported once per call site and clamped to
## Standard (a run must still be startable from a save file that names a deleted mode).
static func definition(mode_id: StringName) -> GameModeConfig:
	if mode_id == &"":
		# "No mode chosen yet" is not a broken reference: RunState defaults to Standard and
		# GameRoot clamps before starting, so an empty id here means a caller queried between runs.
		return null
	var cfg := resolve(validated(mode_id))
	if cfg == null:
		push_error("GameMode: no mode definition resolves for '%s' (not even %s)"
				% [String(mode_id), String(MODE_STANDARD)])
	return cfg


## The line read on the victory announcement (authored per mode, so the announcer never has to know
## which modes exist).
static func victory_line(mode_id: StringName) -> String:
	var cfg := definition(mode_id)
	return cfg.victory_line if cfg != null else ""


## The scripted row for one wave of a mode, or null. This is how a mode's encounter content and its
## narration stay together: `Narrator` asks the mode for the wave's beat instead of owning a second
## int-keyed table of the same arc.
static func beat_for_wave(mode_id: StringName, wave_number: int) -> GameModeWavePlan:
	var cfg := definition(mode_id)
	return cfg.plan_for_wave(maxi(wave_number, 1)) if cfg != null else null


static func display_name(mode_id: StringName) -> String:
	var cfg := definition(mode_id)
	return cfg.display_name if cfg != null else String(mode_id)


static func blurb(mode_id: StringName) -> String:
	var cfg := definition(mode_id)
	return cfg.blurb if cfg != null else ""


## The line the announcer reads when a run starts. `Narrator.mode_intro` is the caller; it exists so
## the mode's copy stays on the mode instead of in a second table keyed by a `narrator_id` that no
## code ever followed.
static func intro_line(mode_id: StringName) -> String:
	var cfg := definition(mode_id)
	return cfg.intro_line if cfg != null else ""


## Every authored mode, sorted by id: `run_setup_panel` builds its mode cards in this order, so the
## sort is the UI's contract rather than whichever order the folder scan returned.
static func all_mode_ids() -> Array[StringName]:
	var names := PackedStringArray()
	for cfg in _all_configs():
		names.append(String(cfg.mode_id))
	names.sort()
	var out: Array[StringName] = []
	for name in names:
		out.append(StringName(name))
	return out


static func score_multiplier(mode_id: StringName) -> float:
	var cfg := definition(mode_id)
	return cfg.score_mult if cfg != null else 1.0


static func currency_multiplier(mode_id: StringName) -> float:
	var cfg := definition(mode_id)
	return cfg.currency_mult if cfg != null else 1.0


## Wave the run is won on; 0 = endless.
static func max_waves(mode_id: StringName) -> int:
	var cfg := definition(mode_id)
	return cfg.max_waves if cfg != null else 0


static func target_seconds(mode_id: StringName) -> float:
	var cfg := definition(mode_id)
	return cfg.target_seconds if cfg != null else 0.0


## Relic quota for a `collect` objective (0 for every other mode, by validation rather than by
## default: `GameModeConfig` refuses to author a quota an objective will not read).
static func collect_target(mode_id: StringName) -> int:
	var cfg := definition(mode_id)
	return maxi(cfg.collect_target, 0) if cfg != null else 0


static func upgrade_every(mode_id: StringName) -> int:
	var cfg := definition(mode_id)
	return cfg.upgrade_every if cfg != null else 0


static func forced_mutators(mode_id: StringName) -> Array[StringName]:
	var cfg := definition(mode_id)
	if cfg == null:
		return []
	# Duplicated: the config is a shared loaded resource, and a caller that sorted or popped this
	# list would be editing the .tres in memory for every later wave.
	return cfg.forced_mutators.duplicate()


static func fixed_weapon(mode_id: StringName) -> StringName:
	var cfg := definition(mode_id)
	return cfg.fixed_weapon if cfg != null else &""


static func objective(mode_id: StringName) -> StringName:
	var cfg := definition(mode_id)
	return cfg.objective if cfg != null else OBJECTIVE_CLEAR_WAVES


## ---------- Prestige-scaled runs ----------
## A mode can re-read its payout and length from the prestige ladder's challenge tiers, so a higher
## rank is a harsher, better-paying, longer run rather than the same fixed loadout every time. The
## mutator SET is drawn from the mode's own ordered pool (`prestige_mutator_pool`) by the tier's
## count, so tier 0 reproduces the historical [glass_cannon, ember_winds] pair and each rung adds
## pressure. `ContentLoader` checks the three numbers agree across the two files; before this phase
## nothing did.

## Whether this mode's run parameters scale with prestige tier.
static func scales_with_prestige(mode_id: StringName) -> bool:
	var cfg := definition(mode_id)
	return cfg != null and cfg.scales_with_prestige


## Deterministic mutator set for a scaling run at `prestige_rank`. Non-scaling modes keep their
## authored forced_mutators regardless of rank.
static func challenge_mutators(mode_id: StringName, prestige_rank: int) -> Array[StringName]:
	var cfg := definition(mode_id)
	if cfg == null:
		return []
	if not cfg.scales_with_prestige:
		return cfg.forced_mutators.duplicate()
	var count := Prestige.challenge_tier_mutator_count(prestige_rank)
	var out: Array[StringName] = []
	for i in range(mini(count, cfg.prestige_mutator_pool.size())):
		out.append(cfg.prestige_mutator_pool[i])
	return out


## Prestige-aware wrappers. Callers with a live run pass GameRoot.get_prestige_rank(); the rank is
## only consulted for modes that scale.
static func score_multiplier_for(mode_id: StringName, prestige_rank: int) -> float:
	if scales_with_prestige(mode_id):
		return Prestige.challenge_tier_score_mult(prestige_rank)
	return score_multiplier(mode_id)


static func currency_multiplier_for(mode_id: StringName, prestige_rank: int) -> float:
	if scales_with_prestige(mode_id):
		return Prestige.challenge_tier_currency_mult(prestige_rank)
	return currency_multiplier(mode_id)


static func max_waves_for(mode_id: StringName, prestige_rank: int) -> int:
	if scales_with_prestige(mode_id):
		return Prestige.challenge_tier_waves(prestige_rank)
	return max_waves(mode_id)


static func is_victory_wave_for(mode_id: StringName, wave_number: int, prestige_rank: int) -> bool:
	var cap := max_waves_for(mode_id, prestige_rank)
	if cap <= 0:
		return false
	return wave_number >= cap


## Label shown in the run-setup preview / announcements for the active tier.
static func challenge_tier_label(mode_id: StringName, prestige_rank: int) -> String:
	if scales_with_prestige(mode_id):
		return Prestige.challenge_tier_label(prestige_rank)
	return display_name(mode_id)


## Whether the run should end in victory after completing `wave_number`.
static func is_victory_wave(mode_id: StringName, wave_number: int) -> bool:
	var cap := max_waves(mode_id)
	if cap <= 0:
		return false
	return wave_number >= cap


## Timed modes: victory when elapsed time reaches the authored target.
static func is_survival_victory(mode_id: StringName, elapsed: float) -> bool:
	if objective(mode_id) != OBJECTIVE_SURVIVE_TIME:
		return false
	var target := target_seconds(mode_id)
	return target > 0.0 and elapsed >= target


## Deterministic spawn queue override for modes that don't use the standard planner. Returns empty
## when the mode should fall through to WavePlanner.
##
## The five private queue builders this replaces (`_boss_rush_queue`, `_survival_queue`,
## `_defend_queue`, `_collect_queue`, and a fifteen-arm `match wave_number` for the campaign) all
## reduced to two rules: some waves are scripted exactly, and the rest are the planner asked for a
## different wave number with an occasional extra archetype on a cadence. Those are knobs, so they
## are authored on the mode and this is one loop over them.
static func spawn_queue(mode_id: StringName, wave_number: int, seed: int) -> Array[StringName]:
	var cfg := definition(mode_id)
	var out: Array[StringName] = []
	if cfg == null or not cfg.overrides_planner():
		return out
	var w := maxi(wave_number, 1)
	var plan := cfg.plan_for_wave(w)
	if plan != null and not plan.archetypes.is_empty():
		out.append_array(plan.archetypes)
	elif cfg.planner_wave_offset != 0 or cfg.planner_wave_floor > 1:
		var asked := maxi(w + cfg.planner_wave_offset, cfg.planner_wave_floor)
		out = WavePlanner.extended_queue_for_wave(asked, seed)
	if cfg.every_n_waves > 1 and w % cfg.every_n_waves == 0:
		out.append_array(cfg.every_n_append)
	return out


## Whether this wave should offer an upgrade under the mode's cadence. 0 = never, which the old
## `maxi(int(get(...)), 1)` made impossible to author: a mode that wanted no upgrades had to omit
## the key and get "every 2 waves".
static func wants_upgrade(mode_id: StringName, wave_number: int) -> bool:
	var every := upgrade_every(mode_id)
	if every <= 0:
		return false
	return wave_number % every == 0


## Objective progress string for HUD / summary. `progress` carries mode-specific live state (relics
## collected, beacon fraction) so this stays pure and typed. The *targets* are data; which live
## counter fills the blank is behaviour, keyed on the objective the config chose.
static func objective_label(mode_id: StringName, wave: int, elapsed: float, bosses_slain: int, progress: int = 0) -> String:
	match objective(mode_id):
		OBJECTIVE_SURVIVE_TIME:
			var left := maxf(target_seconds(mode_id) - elapsed, 0.0)
			return "Survive  %d:%02d remaining" % [int(left) / 60, int(left) % 60]
		OBJECTIVE_SLAY_BOSSES:
			return "Bosses  %d / %d" % [bosses_slain, max_waves(mode_id)]
		OBJECTIVE_DEFEND_POINT:
			var left_d := maxf(target_seconds(mode_id) - elapsed, 0.0)
			return "Hold  %d:%02d  •  Beacon %d%%" % [int(left_d) / 60, int(left_d) % 60, clampi(progress, 0, 100)]
		OBJECTIVE_COLLECT:
			return "Relics  %d / %d" % [progress, collect_target(mode_id)]
		OBJECTIVE_CLEAR_WAVES:
			var cap := max_waves(mode_id)
			if cap > 0:
				return "Wave  %d / %d" % [wave, cap]
			return "Wave  %d" % wave
		_:
			return "Wave  %d" % wave


## Hardened: clamp unknown mode ids to standard — and say so. The clamp is what lets a save file
## from a build that had a now-deleted mode still start a run; reporting it is what stops that being
## invisible (an unknown mode used to read as a normal Standard game, at Standard's payout).
static func validated(mode_id: StringName) -> StringName:
	if is_known(mode_id):
		return mode_id
	if mode_id == &"":
		return MODE_STANDARD
	push_error("GameMode: unknown mode id '%s' clamped to '%s'" % [String(mode_id), String(MODE_STANDARD)])
	return MODE_STANDARD


static func _all_configs() -> Array[GameModeConfig]:
	var out: Array[GameModeConfig] = []
	if ContentRegistry != null:
		for res in ContentRegistry.get_all_game_modes().values():
			if res is GameModeConfig:
				out.append(res)
		return out
	# Headless harness / tooling without a registry: read the folder directly so the same ids still
	# resolve. Sorted by id, so directory order cannot leak into the mode list the UI renders.
	if not _disk_scanned:
		_disk_scanned = true
		var dir := DirAccess.open("res://data/game_modes")
		if dir != null:
			dir.list_dir_begin()
			var fname := dir.get_next()
			while not fname.is_empty():
				if fname.ends_with(".tres"):
					var cfg := load("res://data/game_modes/%s" % fname) as GameModeConfig
					if cfg != null:
						_disk_configs.append(cfg)
				fname = dir.get_next()
			dir.list_dir_end()
	return _disk_configs.duplicate()
