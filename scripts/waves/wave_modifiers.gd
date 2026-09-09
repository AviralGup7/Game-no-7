class_name WaveModifiers
extends RefCounted

## The one wave's folded rule set: how much tougher, faster, richer and more volatile this
## wave is, and what it stamps on everything that spawns. Produced once per wave by
## `WaveManager` (plan scalars → director nudge → mutators, in that order) and handed to
## `SpawnManager`, `RunScorekeeper` and `WeaponManager` as this type.
##
## It replaces three Dictionary hand-offs that had to agree on a key vocabulary nobody checked:
## `WaveMutators.combine()`'s output, `DifficultyDirector.next_wave_multipliers()`'s output, and
## `SpawnManager._wave_mods`/`_difficulty`. Between them, five authored knobs were read by
## nobody (`score_mult`, `currency_mult`, `player_damage_mult`, `burn_tick`, the director's own
## score nudge) and `set_wave_modifiers` silently ignored any key outside its four-name list —
## "missing keys default to neutral, unknown keys are ignored" was the *documented* behaviour,
## which is another way of saying a wiring mistake was unobservable. A field either has a reader
## or `tests/python/test_regress_wave_mutators.py` fails: every field in this type is read by at
## least one consumer, which is the one thing the Dictionary shape could not say.
##
## Clamping lives here rather than in each consumer, so every reader is protected by the same
## rule instead of re-inventing (or forgetting) it.

## Every field that folds, in the order `clamp_bounds` bounds them. `WaveMutatorConfig.FOLD` says
## *how* each one stacks; this list says which ones exist, and the python suite asserts the two
## cover exactly the same names.
const FOLD_FIELDS := ["hp_mult", "damage_mult", "speed_mult", "score_mult", "currency_mult",
	"player_damage_mult", "elite_bonus", "explode_chance"]
## The director's spawn-count nudge is bounded here as well, so a folded set can never ask the
## planner for more extra enemies than the only producer can ever grant.
const COUNT_BONUS_MAX := 2

var hp_mult: float = 1.0
var damage_mult: float = 1.0
var speed_mult: float = 1.0
var score_mult: float = 1.0
var currency_mult: float = 1.0
var player_damage_mult: float = 1.0
var elite_bonus: float = 0.0
var explode_chance: float = 0.0
## Spawn-count adjustment from the DifficultyDirector only (a mutator never changes counts, so
## it is not in FOLD_FIELDS) — kept here because it is the sixth thing the wave folds.
var count_bonus: int = 0
## Highest severity in the set: the wave banner interrupts the announcement queue on "major".
var severity: StringName = WaveMutatorConfig.SEVERITY_MINOR
## The ids that produced this set, in resolution order, for the banner and the run mirror.
var mutator_ids: Array[StringName] = []
## The status a mutator set carries (Ember Winds' burning air), resolved once per wave instead of
## per spawn: `status_effect_id` is authored, `status_effect` is what the registry had for it.
## A mutator whose status id does not resolve is reported by `WaveMutators.combine` — never folded
## into "this mutator is mild".
var status_effect_id: StringName = &""
var status_effect: StatusEffectConfig = null
var status_stacks: int = 1
var status_targets_enemies: bool = false
var status_targets_player: bool = false


static func neutral() -> WaveModifiers:
	return WaveModifiers.new()


func has_mutators() -> bool:
	return not mutator_ids.is_empty()


func is_neutral() -> bool:
	if not mutator_ids.is_empty() or count_bonus != 0 or status_effect_id != &"":
		return false
	for field in FOLD_FIELDS:
		var want := 0.0 if field == "elite_bonus" or field == "explode_chance" else 1.0
		if absf(float(get(field)) - want) > 0.0001:
			return false
	return true


## Fold one mutator, using the stacking rule it declares per field. Multiply for stats, add for
## chances that are meant to accumulate, max for one-shot flags. Order does not matter: every
## field is folded independently, which is what makes a wave's set safe to sort/de-duplicate in
## `WaveMutators.resolve_for_wave`.
func fold_mutator(cfg: WaveMutatorConfig) -> void:
	if cfg == null:
		return
	mutator_ids.append(cfg.mutator_id)
	for field in cfg.FOLD.keys():
		match cfg.FOLD[field]:
			WaveMutatorConfig.STACK_MULTIPLY:
				set(field, float(get(field)) * float(cfg.get(field)))
			WaveMutatorConfig.STACK_ADD:
				set(field, float(get(field)) + float(cfg.get(field)))
			WaveMutatorConfig.STACK_MAX:
				set(field, maxf(float(get(field)), float(cfg.get(field))))
			_:
				push_error("WaveModifiers: unknown stack rule on %s.%s" % [String(cfg.mutator_id), String(field)])
	if cfg.severity == WaveMutatorConfig.SEVERITY_MAJOR:
		severity = WaveMutatorConfig.SEVERITY_MAJOR
	if cfg.has_status():
		if status_effect_id == &"":
			status_effect_id = cfg.status_effect_id
		status_stacks = maxi(status_stacks, cfg.status_stacks)
		status_targets_enemies = status_targets_enemies or cfg.status_targets_enemies()
		status_targets_player = status_targets_player or cfg.status_targets_player()


## Fold the adaptive director's contribution. It arrives as the same type a mutator produces so
## the two halves of the wave's rule set are added by identical arithmetic (the director used to
## hand over a Dictionary whose `score_mult` and `count_bonus` WaveManager simply never read).
func fold_director(nudge: WaveModifiers) -> void:
	if nudge == null:
		return
	hp_mult *= nudge.hp_mult
	damage_mult *= nudge.damage_mult
	speed_mult *= nudge.speed_mult
	score_mult *= nudge.score_mult
	elite_bonus += nudge.elite_bonus
	count_bonus += nudge.count_bonus


## Clamp once, after everything is folded. A multiplier of 0 (or a negative one from a bad nudge)
## turns an enemy into something that cannot be hurt or killed, and an elite chance above its
## documented cap makes every spawn elite.
##
## A non-finite value is the interesting case: it cannot be clamped meaningfully, and silently
## replacing it with a neutral 1.0 would hide whoever produced it — the exact "reported as
## success" failure this whole subsystem used to have. So it is reported, then lands on the bound
## its sign implies (+INF is as strong as allowed, -INF as weak as allowed); NaN has no sign, so it
## lands neutral, which is the only answer that cannot hurt the player or the wave.
func clamp_bounds() -> void:
	for field in FOLD_FIELDS:
		var value := float(get(field))
		if not is_finite(value):
			push_error("WaveModifiers: %s is not finite before clamping" % field)
			var is_chance := field == "elite_bonus" or field == "explode_chance"
			if value > 0.0:
				set(field, WaveMutatorConfig.CHANCE_MAX if is_chance else WaveMutatorConfig.MULT_CEIL)
			elif value < 0.0:
				set(field, 0.0 if is_chance else WaveMutatorConfig.MULT_FLOOR)
			else:
				set(field, 0.0 if is_chance else 1.0)
			continue
		if field.ends_with("_mult"):
			set(field, clampf(value, WaveMutatorConfig.MULT_FLOOR, WaveMutatorConfig.MULT_CEIL))
		elif field == "elite_bonus":
			set(field, clampf(value, 0.0, WaveMutatorConfig.ELITE_BONUS_MAX))
		else:
			set(field, clampf(value, 0.0, WaveMutatorConfig.CHANCE_MAX))
	count_bonus = clampi(count_bonus, -COUNT_BONUS_MAX, COUNT_BONUS_MAX)


## The plan's own per-wave scalars, folded in first. This is the one place in the wave pipeline
## that still takes a Dictionary, because `WavePlanner.calculate_difficulty_scalars()` is a
## published, test-pinned scalar function (`tests/unit/test_waves.gd` reads its keys); converting
## the planner is a separate change. Multiplying here rather than at the call site keeps
## "plan, then director, then mutators" a single documented order.
func apply_plan_scalars(scalars: Dictionary) -> void:
	hp_mult *= float(scalars.get("hp", 1.0))
	damage_mult *= float(scalars.get("damage", 1.0))
	speed_mult *= float(scalars.get("speed", 1.0))


## Final multipliers for an enemy entering the arena. `extra_*` is where a caller that already has
## its own factors (the elite affix set) folds them in, so the record stays the only source of the
## wave half and `EnemyBase.apply_difficulty` keeps being fed three plain floats. Note that the
## enemy floors each of those three scales at 1.0 in `apply_difficulty` — a below-one value is a
## deliberate `@export_range` on the mutator (Swift Horde's 0.85) but reads on the entity as "not
## tougher", never as "weaker than its config". Kept as is: it is combat balance, and the floor
## belongs to the entity, not to the fold. This is what the fold's own tests assert against.
func enemy_scaling(extra_hp: float = 1.0, extra_damage: float = 1.0, extra_speed: float = 1.0) -> Vector3:
	return Vector3(hp_mult * extra_hp, damage_mult * extra_damage, speed_mult * extra_speed)


## Only the debug snapshot and the save/replay inspector read this. The gameplay path never
## does: readers go through fields, which is the difference between this and what it replaced.
func debug_dictionary() -> Dictionary:
	var out := {
		"hp_mult": hp_mult, "damage_mult": damage_mult, "speed_mult": speed_mult,
		"score_mult": score_mult, "currency_mult": currency_mult,
		"player_damage_mult": player_damage_mult, "elite_bonus": elite_bonus,
		"explode_chance": explode_chance, "count_bonus": count_bonus,
		"severity": String(severity), "mutators": mutator_ids.size(),
	}
	if status_effect != null:
		out["status"] = String(status_effect.effect_id)
		out["status_stacks"] = status_stacks
	return out
