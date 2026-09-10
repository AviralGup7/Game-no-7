class_name WaveMutators
extends RefCounted

## Selection + resolution for wave mutators. The *definitions* are authored data now
## (`res://data/mutators/<id>.tres`, `WaveMutatorConfig`); this file is the part that has to stay
## code: which mutator a generated wave gets, in what order, deterministically, and how a set
## combines into one `WaveModifiers`.
##
## It used to hold both. `definition(mutator_id)` was a `match` over seven hand-written
## Dictionaries, `combine()` folded nine keys by name, and the last line of `definition()`
## returned a neutral Dictionary for any id it did not recognise — so an unknown mutator was not
## an error, it was a wave that announced a modifier and applied nothing. Nothing here knows a
## mutator's numbers any more, and `tests/python/test_regress_wave_mutators.py` fails if a number
## comes back.
##
## Selection is deterministic in (seed, wave) and the *order* of `ordered_ids()` is part of that
## contract: `DailyChallenge.mutators_for_stamp()` draws by popping indices out of this list, so
## the roll_order values in the data (not the loader's file order) decide the day's pair.

## Folder scan for the no-registry path, cached: `roll_for_wave` runs at every wave start, and in
## the harness (which has no autoloads) the alternative is re-listing `res://data/mutators` and
## re-resolving seven `.tres` per roll. Authored content does not change inside a session, and a
## live game never reaches this path — ContentRegistry answers first.
static var _disk_configs: Array[WaveMutatorConfig] = []
static var _disk_scanned := false

const MIN_ROLL_WAVE := 4
## The +100 wave offset is a second, independent draw for the director's "spice" extra mutator;
## keeping it in code (not data) because it is an algorithm detail of this roller.
const SPICE_WAVE_OFFSET := 100


## Every registered mutator id, in roll order (ties broken by id so two configs authored with
## the same order still resolve the same way on every machine).
static func ordered_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for cfg in _sorted_configs():
		ids.append(cfg.mutator_id)
	return ids


static func is_known(mutator_id: StringName) -> bool:
	return resolve(mutator_id) != null


## Registry first, disk second: the same rule the arena and hazard systems follow, so an id
## resolves identically in a live run and in the headless harness (which boots without a content
## registry). Null is reported by callers that needed it, never replaced by a neutral stand-in.
static func resolve(mutator_id: StringName) -> WaveMutatorConfig:
	if ContentRegistry != null:
		var registered: WaveMutatorConfig = ContentRegistry.get_wave_mutator(mutator_id)
		if registered != null:
			return registered
	var path := "res://data/mutators/%s.tres" % String(mutator_id)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as WaveMutatorConfig


## Fold a set of mutator ids onto a fresh neutral record. Kept because it is the shape callers
## (and the director tests) want when there is no wave context to fold into.
static func combine(mutator_ids: Array) -> WaveModifiers:
	return fold_into(WaveModifiers.neutral(), mutator_ids)


## Fold a set of mutator ids INTO an existing record. This is the entry point WaveManager uses, so
## the order of the three sources (plan scalars, then director, then mutators) is decided by the
## caller who owns the wave rather than buried in whichever helper happened to be called second —
## and the fold itself is one loop over each mutator's declared stacking rules, with no key names
## repeated here. Unknown ids are dropped (and reported): a wave must not be silently neutered by
## one stale id in a WaveConfig, but it must not stop either. Duplicates are resolved in
## `resolve_for_wave`, so each id folds once.
static func fold_into(mods: WaveModifiers, mutator_ids: Array) -> WaveModifiers:
	if mods == null:
		mods = WaveModifiers.neutral()
	for raw in mutator_ids:
		var cfg := resolve(StringName(String(raw)))
		if cfg == null:
			push_warning("WaveMutators: unknown mutator id '%s' in a wave's set" % String(raw))
			continue
		mods.fold_mutator(cfg)
	if mods.status_effect_id != &"":
		mods.status_effect = resolve_status(mods.status_effect_id)
		if mods.status_effect == null:
			push_warning("WaveMutators: a mutator names status '%s', which is not registered"
					% String(mods.status_effect_id))
	mods.clamp_bounds()
	return mods


## Statuses resolve through the same registry-or-disk rule, because the mutator's whole effect is
## the status: a missing one must never read as "the mutator is just mild".
static func resolve_status(effect_id: StringName) -> StatusEffectConfig:
	if effect_id == &"":
		return null
	if ContentRegistry != null:
		var registered: StatusEffectConfig = ContentRegistry.get_status_effect(effect_id)
		if registered != null:
			return registered
	var path := "res://data/status/%s.tres" % String(effect_id)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as StatusEffectConfig


## Deterministic mutator pick for generated waves: none before wave 4, one from wave 4, a second
## from wave 8. Authored waves declare their own instead. The wave floor each mutator honours is
## `WaveMutatorConfig.min_wave` (Glass Cannon's "wave 6+" used to be an `if wave < 6` here with a
## comment explaining it).
static func roll_for_wave(wave: int, rng_seed: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if wave < MIN_ROLL_WAVE:
		return out
	var rng := RngService.make_generator(rng_seed, RngService.STREAM_WAVES + wave * 7)
	var pool: Array = _roll_pool(wave)
	if pool.is_empty():
		return out
	out.append(pool[rng.randi_range(0, pool.size() - 1)])
	if wave >= 8 and pool.size() > 1:
		pool.erase(out[0])
		out.append(pool[rng.randi_range(0, pool.size() - 1)])
	return out


## Resolve the active set for a wave: authored declarations win; generated waves roll (skipped on
## a director breather, spiced with an extra on a hot streak). Unknown ids are dropped, duplicates
## collapsed. Pure in (declared, wave, seed).
static func resolve_for_wave(declared: Array, wave: int, rng_seed: int, breather: bool, spice: bool) -> Array[StringName]:
	var out: Array[StringName] = []
	var pool: Array = declared.duplicate()
	if pool.is_empty():
		if breather:
			return out
		for m in roll_for_wave(wave, rng_seed):
			pool.append(m)
		if spice and pool.size() < 2:
			var extra := roll_for_wave(wave + SPICE_WAVE_OFFSET, rng_seed)
			for extra_id in extra:
				if extra_id not in pool:
					pool.append(extra_id)
					break
	for raw in pool:
		var id := StringName(String(raw))
		if not is_known(id):
			# Reported, then dropped. A WaveConfig that names a mutator nobody shipped used to be
			# indistinguishable from a wave with no mutators; ContentLoader's reference check makes
			# the authored case a startup error, so this branch is for code-built waves.
			push_warning("WaveMutators: wave %d declares unknown mutator '%s'" % [wave, String(id)])
			continue
		if id not in out:
			out.append(id)
	return out


## Human-readable name for one mutator id (falls back to the raw id, which is what a modder's own
## config would want to see rather than an empty banner).
static func display_name(mutator_id: StringName) -> String:
	var cfg := resolve(mutator_id)
	return cfg.display_name if cfg != null else String(mutator_id)


## What a mutator does, in its author's words. The wave banner only has room for names, so this is
## for the panels that list a run's rules (the daily card's tooltip). Like `display_name`, an
## unknown id answers with its id rather than an empty string: a tooltip that vanishes because a
## mutator was renamed reads as a UI bug, not as missing data.
static func description(mutator_id: StringName) -> String:
	var cfg := resolve(mutator_id)
	return cfg.description if cfg != null else ""


static func banner_text(mutator_ids: Array) -> String:
	if mutator_ids.is_empty():
		return ""
	var names: PackedStringArray = []
	for raw in mutator_ids:
		names.append(display_name(StringName(String(raw))))
	return "Mutators: " + ", ".join(names)


## Ids eligible for this wave, in roll order, honouring each mutator's own floor.
static func _roll_pool(wave: int) -> Array:
	var pool: Array = []
	for cfg in _sorted_configs():
		if wave >= cfg.min_wave:
			pool.append(cfg.mutator_id)
	return pool


static func _all_configs() -> Array[WaveMutatorConfig]:
	var out: Array[WaveMutatorConfig] = []
	if ContentRegistry != null:
		for res in ContentRegistry.get_all_wave_mutators().values():
			if res is WaveMutatorConfig:
				out.append(res)
		if not out.is_empty():
			return out
		# An empty registry is not an answer, it is a moment: `ContentLoader` validates each file it has
		# read *before* it registers the table that file belongs to, so a config asking "is
		# `glass_cannon` a real mutator" can arrive mid-load with the autoload present and nothing in it.
		# `GameMode` carries the same rule for the same reason -- it is written out in both files rather
		# than lifted into a helper, because a resolver that reaches for a shared one hides which content
		# folder it is falling back to, and that is the fact a reader needs.
	# Headless harness / tooling without a registry, or a loader that has not registered yet: read the
	# folder directly so the same ids still resolve. Sorted by (roll_order, id) below, so listing order
	# cannot leak in.
	if not _disk_scanned:
		var dir := DirAccess.open("res://data/mutators")
		if dir != null:
			dir.list_dir_begin()
			var fname := dir.get_next()
			while not fname.is_empty():
				if fname.ends_with(".tres"):
					var cfg := load("res://data/mutators/%s" % fname) as WaveMutatorConfig
					if cfg != null:
						_disk_configs.append(cfg)
				fname = dir.get_next()
			dir.list_dir_end()
		# Cache only a scan that found something: the first call can land mid-load, and a cached empty
		# answer would outlive the reason it was empty.
		if not _disk_configs.is_empty():
			_disk_scanned = true
	return _disk_configs.duplicate()


## Sorted by (roll_order, id). The sort key is a packed string rather than a Callable so the
## order is the same in the editor, in a headless run and in an export, and ties cannot be broken
## by registration order (which is what a Dictionary-of-tables used to inherit from the loader).
static func _sorted_configs() -> Array[WaveMutatorConfig]:
	var configs := _all_configs()
	var keyed: Array[String] = []
	for i in range(configs.size()):
		keyed.append("%03d|%s|%d" % [configs[i].roll_order, String(configs[i].mutator_id), i])
	keyed.sort()
	var out: Array[WaveMutatorConfig] = []
	for entry in keyed:
		out.append(configs[int(entry.get_slice("|", 2))])
	return out
