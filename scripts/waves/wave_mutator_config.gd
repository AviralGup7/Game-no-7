class_name WaveMutatorConfig
extends ValidatedConfig

## One wave mutator: a rule twist the arena applies to a wave (faster horde, armored foes,
## burning air). Authored under res://data/mutators/ and registered by ContentLoader, so it is
## validated at load like every other content type.
##
## It used to be a `match mutator_id` in `wave_mutators.gd` returning a fresh Dictionary per
## call, with a final line that returned a *neutral* Dictionary for any id it did not recognise.
## Two things followed from that shape. A key spelled differently in one branch (`currency_mult`
## appears in exactly one mutator) was answered by whatever `.get(key, default)` the consumer
## passed, so a typo was a silently neutral multiplier rather than an error. And a knob that no
## consumer happened to read cost nothing to ship: `player_damage_mult`, `currency_mult`,
## `score_mult` and `burn_tick` were all computed, clamped, folded — and consumed by nobody, so
## three of the seven shipped mutators advertised an effect on their banner line that never
## happened. Fields on a type are read or they do not compile-check; that is the whole point.
##
## Stacking rules are declared here, not written per key in the combiner: see `FOLD`, which is
## the one place that says how every knob combines (multiplicative stats, additive chances, max
## for one-shot flags). The rule is per-field because "how do two of these stack" has no generic
## answer — a designer must say, and the answer has to live next to the number it describes.

const SEVERITY_MINOR := &"minor"
const SEVERITY_MAJOR := &"major"
const VALID_SEVERITIES := [SEVERITY_MINOR, SEVERITY_MAJOR]

const STACK_MULTIPLY := &"multiply"
const STACK_ADD := &"add"
const STACK_MAX := &"max"

## Every numeric field, with how it folds across simultaneous mutators and how the result is
## bounded afterwards. `WaveMutators.combine` iterates THIS table, so a new field cannot be
## authored without saying how it stacks — which is how `currency_mult` was lost the first time
## (it existed in one definition, and `combine` had nine hand-written lines that did not mention
## it). `WaveModifiers.FOLD_FIELDS` is the completeness check that keeps the two in step.
const FOLD := {
	"hp_mult": STACK_MULTIPLY,
	"damage_mult": STACK_MULTIPLY,
	"speed_mult": STACK_MULTIPLY,
	"score_mult": STACK_MULTIPLY,
	"currency_mult": STACK_MULTIPLY,
	"player_damage_mult": STACK_MULTIPLY,
	"elite_bonus": STACK_ADD,
	"explode_chance": STACK_MAX,
}
## Bounds applied once, after folding, to whatever set of mutators is active. A multiplier that
## reaches 0 turns an enemy into a ghost that cannot be killed or hurt; a negative elite chance
## would make elites impossible instead of rare.
const MULT_FLOOR := 0.01
const MULT_CEIL := 8.0
const ELITE_BONUS_MAX := 0.5
const CHANCE_MAX := 1.0

@export var mutator_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Drives the wave banner's urgency (a major twist interrupts the queue) and nothing else: it is
## presentation, so it is deliberately not a gameplay knob.
@export var severity: StringName = SEVERITY_MINOR
## Position in the deterministic roll order. Part of a published contract: the daily challenge
## draws by popping indices out of `WaveMutators.ordered_ids()`, so re-numbering these changes
## which pair a given date offers (the python suite pins the shipped order). Unique per mutator.
@export_range(0, 64) var roll_order: int = 0
## 1 = can appear on any wave. Glass Cannon used to hard-code "wave 6+" inside
## `WaveMutators.roll_for_wave` with a comment explaining why; now the gate is authored and the
## roller reads it, so a designer can retune it without touching the selection algorithm.
@export_range(1, 1000) var min_wave: int = 1

@export_range(0.05, 8.0, 0.05) var hp_mult: float = 1.0
@export_range(0.05, 8.0, 0.05) var damage_mult: float = 1.0
@export_range(0.05, 8.0, 0.05) var speed_mult: float = 1.0
## Kill value and meta-currency, folded into RunScorekeeper's multiplier alongside upgrades,
## mode and prestige (both were dead here before this field existed on a type).
@export_range(0.1, 8.0, 0.05) var score_mult: float = 1.0
@export_range(0.1, 8.0, 0.05) var currency_mult: float = 1.0
## The player's outgoing damage. Named from the player's side ("everyone hits harder, including
## you") because that is the only direction it can move: enemy incoming damage is `hp_mult`'s
## business, and the two must not be confused for a balance pass.
@export_range(0.1, 8.0, 0.05) var player_damage_mult: float = 1.0
## Added across mutators, then clamped: it rides on top of the wave's own elite chance.
@export_range(0.0, 0.5, 0.01) var elite_bonus: float = 0.0
## The strongest mutator wins rather than the sum, so two "sometimes explodes" mutators cannot
## stack into an always-exploding horde.
@export_range(0.0, 1.0, 0.01) var explode_chance: float = 0.0
## Optional status the mutator stamps on its targets (Ember Winds' burning air). Resolved through
## the status table by ContentLoader's reference check, so an id that no longer exists is a
## startup error rather than an arena with no fire.
@export var status_effect_id: StringName = &""
@export_range(1, 5) var status_stacks: int = 1
const TARGET_NONE := &"none"
const TARGET_ENEMIES := &"enemies"
const TARGET_PLAYER := &"player"
const TARGET_ALL := &"all"
const VALID_TARGETS := [TARGET_NONE, TARGET_ENEMIES, TARGET_PLAYER, TARGET_ALL]
@export var status_targets: StringName = TARGET_ALL


func has_status() -> bool:
	return status_effect_id != &"" and status_targets != TARGET_NONE


## Who gets stamped (the player is re-stamped as the wave arrives, not once at wave start, so a
## spawn trickle keeps the air lit rather than lighting it for four seconds and forgetting).
## `status_targets` is a StringName id, so these are `==` tests with ALL
## spelled out — NOT `in`, which on two strings means "substring", and "&"enemies" in &"all"" is
## false: an `all` mutator would have stamped nobody and still validated clean.
func status_targets_enemies() -> bool:
	return status_targets == TARGET_ENEMIES or status_targets == TARGET_ALL


func status_targets_player() -> bool:
	return status_targets == TARGET_PLAYER or status_targets == TARGET_ALL


func is_neutral() -> bool:
	for field in FOLD.keys():
		if absf(float(get(field)) - (0.0 if field == "elite_bonus" or field == "explode_chance" else 1.0)) > 0.0001:
			return false
	return not has_status()


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(mutator_id).is_empty():
		problems.append("mutator_id is empty")
	elif not String(resource_path).is_empty() and String(mutator_id) != resource_path.get_file().get_basename():
		problems.append("mutator_id '%s' does not match the file name" % String(mutator_id))
	if String(display_name).is_empty():
		problems.append("mutator %s has no display_name (the wave banner would print an empty id)" % String(mutator_id))
	if String(description).is_empty():
		problems.append("mutator %s has no description" % String(mutator_id))
	if severity not in VALID_SEVERITIES:
		problems.append("unknown severity '%s' (the banner escalation rule knows only minor/major)" % String(severity))
	if status_targets not in VALID_TARGETS:
		problems.append("unknown status_targets '%s'" % String(status_targets))
	if status_effect_id != &"" and status_targets == TARGET_NONE:
		problems.append("mutator %s names a status but targets nobody" % String(mutator_id))
	if min_wave < 1:
		problems.append("min_wave must be >= 1")
	if roll_order < 0 or roll_order > 64:
		problems.append("roll_order must be in 0..64 (it indexes the deterministic roll pool)")
	for field in FOLD.keys():
		var value := float(get(field))
		if not is_finite(value):
			problems.append("%s is not finite" % field)
		elif value < 0.0:
			problems.append("%s cannot be negative (invert a multiplier with a fraction instead)" % field)
		elif field.ends_with("_mult") and value < 0.05:
			problems.append("%s below 0.05 would erase the stat it scales" % field)
	if has_status() and status_stacks < 1:
		problems.append("a status-carrying mutator needs at least one stack")
	if is_neutral():
		# A mutator that changes nothing is not a mild mutator. It is a banner line, a
		# `wave_mutator_applied` signal and a roll that displaced a real one.
		problems.append("mutator %s is completely neutral: it would announce itself and do nothing"
				% String(mutator_id))
	return problems
