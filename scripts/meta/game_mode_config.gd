class_name GameModeConfig
extends ValidatedConfig

## Authored definition of one playable run mode: `res://data/game_modes/<mode_id>.tres`.
##
## This file exists because `GameMode.CATALOG` claimed to be data while being code. The seven
## shipped modes lived as a Dictionary of Dictionaries inside the same script that ran them, so:
##
## * every read was `def(id).get("key", <default>)`, and each of the thirteen accessors picked its
##   own default — `upgrade_every` defaulted to 2, `boss_interval` to 10, `objective` to
##   `clear_waves`. A mode that simply *omitted* a key was a mode with a number nobody wrote down.
## * `def()` answered an unknown mode id with Standard's whole record, so a typo in a save file,
##   a mod's mode, or a renamed folder rendered as a playable "Endless waves" run.
## * three of the eleven keys (`narrator_id`, `boss_interval`, `unlock_prestige`) were read by no
##   caller at all: Hold the Line's "borrow Standard's announcer voice", every mode's boss cadence,
##   and every mode's prestige gate were authored, inspected, and ignored.
## * a mode's spawn script — the actual encounter content — was five `match` arms in the same
##   file, and the campaign's fifteen-beat narration was a *second* int-keyed table in
##   `narrator.gd` keyed by the same wave numbers, with nothing checking the two agreed.
##
## Now every knob is an inspector field with a range, a missing or broken file is a startup error
## (ContentLoader), an unknown id is reported instead of laundered into Standard, and the fields
## that did nothing are gone rather than quietly kept.


## The objective kinds a mode can declare. This is the mode's *vocabulary*: which live state the
## objective director tracks and which line the HUD prints are behaviour in `GameMode` /
## `ObjectiveDirector`; what the target is (seconds, waves, relics) is data here.
const OBJECTIVE_CLEAR_WAVES := &"clear_waves"
const OBJECTIVE_SURVIVE_TIME := &"survive_time"
const OBJECTIVE_SLAY_BOSSES := &"slay_bosses"
const OBJECTIVE_DEFEND_POINT := &"defend_point"
const OBJECTIVE_COLLECT := &"collect"
const OBJECTIVES: Array[StringName] = [
	OBJECTIVE_CLEAR_WAVES, OBJECTIVE_SURVIVE_TIME, OBJECTIVE_SLAY_BOSSES,
	OBJECTIVE_DEFEND_POINT, OBJECTIVE_COLLECT,
]

@export var mode_id: StringName = &""
@export var display_name: String = ""
## One line for the run-setup card: what the mode asks of the player.
@export_multiline var blurb: String = ""
## What the announcer says as the run begins. Authored on the mode (not looked up from a
## narrator table through a second "narrator_id" indirection) because it is mode copy, and the
## indirection it replaces was never called: two modes pointed at Standard's line and got their
## own anyway.
@export_multiline var intro_line: String = ""
## Read on the victory announcement. It lives here because `Narrator.announce_victory()` used to be
## a `match mode_id` over four of the seven modes' endings, with the other three falling through to a
## shared default — so a new mode's victory could not be authored without editing the announcer.
@export_multiline var victory_line: String = ""
@export var objective: StringName = OBJECTIVE_CLEAR_WAVES

## --- payout ---
@export_range(0.05, 10.0, 0.01) var score_mult: float = 1.0
@export_range(0.05, 10.0, 0.01) var currency_mult: float = 1.0

## --- win condition ---
## Wave the run is won on; 0 = endless (Standard), where only death ends it.
@export_range(0, 200, 1) var max_waves: int = 0
## Clock target for timed objectives (Survival's 300s, Hold the Line's 240s); 0 = untimed.
@export_range(0.0, 3600.0, 1.0) var target_seconds: float = 0.0
## Relic quota for OBJECTIVE_COLLECT; only that objective reads it, so authoring it elsewhere is
## refused rather than ignored.
@export_range(0, 500, 1) var collect_target: int = 0

## --- run structure ---
## Waves between upgrade offers; 0 = this mode never interrupts a run for the armory.
@export_range(0, 20, 1) var upgrade_every: int = 1
## Only mode in the catalogue that pins a loadout (Challenge's single Gladius); empty = the
## player's unlocked arsenal, as usual.
@export var fixed_weapon: StringName = &""
## Mutators every wave of this mode carries, on top of whatever the wave itself declares.
@export var forced_mutators: Array[StringName] = []

## --- prestige escalation ---
## Whether the run's payout, mutator count and wave cap are re-read from the prestige ladder's
## challenge tiers (Challenge) instead of the values above.
@export var scales_with_prestige: bool = false
## Ordered pool a scaling mode draws from: tier N takes the first `mutator_count` ids, so
## escalating a run is harder *and* differently-shaped. Order is authored, like a mutator's
## roll_order, because it decides what a player at rank 2 fights.
@export var prestige_mutator_pool: Array[StringName] = []

## --- spawn queue (what walks in, per wave) ---
## Scripted waves: an exact archetype list (and, for a mode with a narrative arc, the beat that
## is read over it). Rows win over the planner; a row with no archetypes is narration only.
@export var wave_plans: Array[GameModeWavePlan] = []
## The planner is asked for `wave_number + planner_wave_offset` so a mode can start a run already
## escalated (Survival and Relic Hunt ask for wave+2, Hold the Line for wave+1).
@export_range(-20, 20, 1) var planner_wave_offset: int = 0
## Floor for that lookup: Survival never wants the gentle wave-1 pack, even at run start.
@export_range(1, 200, 1) var planner_wave_floor: int = 1
## Every Nth wave, append `every_n_append` (Hold the Line sends a heavy at the beacon every 3rd).
@export_range(0, 20, 1) var every_n_waves: int = 0
@export var every_n_append: Array[StringName] = []


## Whether the mode has anything to say about the queue, or should leave it to WavePlanner.
## Standard and Challenge answer false, which is exactly the empty array `spawn_queue()` used to
## `match` its way to.
func overrides_planner() -> bool:
	return not wave_plans.is_empty() or planner_wave_offset != 0 \
		or planner_wave_floor > 1 or every_n_waves > 0


func plan_for_wave(wave_number: int) -> GameModeWavePlan:
	for plan in wave_plans:
		if plan != null and plan.wave_number == wave_number:
			return plan
	return null


func has_beat_for_wave(wave_number: int) -> bool:
	var plan := plan_for_wave(wave_number)
	return plan != null and plan.has_beat()


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(mode_id).is_empty():
		problems.append("mode_id is empty (the file stem is a mode's id; both must be authored)")
	if display_name.is_empty():
		problems.append("%s: display_name is empty, so the run-setup card has no title" % String(mode_id))
	if blurb.is_empty():
		problems.append("%s: blurb is empty, so the card explains nothing about the mode" % String(mode_id))
	if intro_line.is_empty():
		problems.append("%s: intro_line is empty, so a run of this mode starts in silence" % String(mode_id))
	if victory_line.is_empty():
		problems.append("%s: victory_line is empty, so winning the mode announces nothing" % String(mode_id))
	if objective not in OBJECTIVES:
		problems.append("%s: objective '%s' is not one of %s" % [String(mode_id), String(objective), str(OBJECTIVES)])
	if not is_finite(score_mult) or not is_finite(currency_mult) or score_mult <= 0.0 or currency_mult <= 0.0:
		problems.append("%s: score_mult/currency_mult must be finite and > 0" % String(mode_id))
	if not is_finite(target_seconds) or target_seconds < 0.0:
		problems.append("%s: target_seconds must be finite and >= 0" % String(mode_id))
	_match_objective_to_its_target(problems)
	if upgrade_every > 1 and max_waves > 0 and upgrade_every > max_waves:
		problems.append("%s: upgrade_every %d never fires under a %d-wave cap"
				% [String(mode_id), upgrade_every, max_waves])
	if scales_with_prestige:
		_validate_prestige_scaling(problems)
	elif not prestige_mutator_pool.is_empty():
		problems.append("%s: prestige_mutator_pool is never drawn (scales_with_prestige is false)" % String(mode_id))
	_validate_queue(problems)
	return problems


## Each objective needs its own number to be a win condition. These pairings are the ones a
## mode could previously get wrong silently: a `collect` mode with quota 0 asked the director to
## bank 0 relics, and a timed mode with no clock showed "0:00 remaining" forever.
func _match_objective_to_its_target(problems: Array[String]) -> void:
	match objective:
		OBJECTIVE_COLLECT:
			if collect_target <= 0:
				problems.append("%s: objective collect needs collect_target > 0" % String(mode_id))
		OBJECTIVE_SURVIVE_TIME, OBJECTIVE_DEFEND_POINT:
			if target_seconds <= 0.0:
				problems.append("%s: a timed objective needs target_seconds > 0" % String(mode_id))
		OBJECTIVE_SLAY_BOSSES:
			if max_waves <= 0:
				problems.append("%s: 'slay bosses' needs a number of bosses (max_waves)" % String(mode_id))
		_:
			if collect_target > 0:
				problems.append("%s: collect_target %d is dead data under objective '%s'"
						% [String(mode_id), collect_target, String(objective)])


## A scaling mode's authored `forced_mutators` is its tier-0 signature; the pool is where the
## escalation draws from. Keeping the two in agreement is what stops the wave banner listing one
## pair and the run applying another.
func _validate_prestige_scaling(problems: Array[String]) -> void:
	if prestige_mutator_pool.is_empty():
		problems.append("%s: scales_with_prestige with an empty prestige_mutator_pool has nothing to escalate"
				% String(mode_id))
		return
	if forced_mutators.is_empty():
		problems.append("%s: a scaling mode must author its tier-0 signature in forced_mutators" % String(mode_id))
		return
	for i in range(forced_mutators.size()):
		if i >= prestige_mutator_pool.size() or forced_mutators[i] != prestige_mutator_pool[i]:
			problems.append("%s: forced_mutators must be the opening of prestige_mutator_pool (tier 0 draws by count)"
					% String(mode_id))
			return


func _validate_queue(problems: Array[String]) -> void:
	if every_n_waves == 1:
		problems.append("%s: every_n_waves 1 is not a spice rule, it is the base rule — put it in the planner"
				% String(mode_id))
	if (every_n_waves > 1) != (not every_n_append.is_empty()):
		problems.append("%s: every_n_waves (%d) and every_n_append (%d ids) must be authored together"
				% [String(mode_id), every_n_waves, every_n_append.size()])
	for archetype_id in every_n_append:
		if String(archetype_id).is_empty():
			problems.append("%s: empty archetype in every_n_append" % String(mode_id))
	var seen := {}
	for plan in wave_plans:
		if plan == null:
			problems.append("%s: null row in wave_plans" % String(mode_id))
			continue
		if seen.has(plan.wave_number):
			problems.append("%s: two wave plans for wave %d (the first would silently win)"
					% [String(mode_id), plan.wave_number])
		seen[plan.wave_number] = true
		if max_waves > 0 and plan.wave_number > max_waves:
			problems.append("%s: wave plan %d is past the %d-wave cap, so it can never spawn"
					% [String(mode_id), plan.wave_number, max_waves])
		for problem in plan.validate():
			problems.append("%s wave %d: %s" % [String(mode_id), plan.wave_number, problem])
