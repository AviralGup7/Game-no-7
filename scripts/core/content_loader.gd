class_name ContentLoader
extends RefCounted

## Data-directory scanning + typed registration, extracted from ContentRegistry.
## Discovers `.tres` files under res://data/**, casts each to its config class,
## runs validate(), rejects duplicates, and collects every problem into an error
## list instead of crashing. Returns plain tables; the registry keeps ownership
## of the live dictionaries, arena selection, and audio-cue registration.
## Autoload-free (ResourceLoader/DirAccess only).


## Scan everything. Returns {"tables": {kind -> {id -> config}}, "waves": {...},
## "audio": {cue_id -> AudioStream}, "errors": Array[String], "first_arena": id}.
static func load_all() -> Dictionary:
	var errors: Array[String] = []
	var tables := {
		&"enemies": {},
		&"upgrades": {},
		&"arenas": {},
		&"cameras": {},
		&"weapons": {},
		&"skills": {},
		&"status": {},
		&"pickups": {},
		&"waves": {},
		&"hazards": {},
		&"hazard_modes": {},
		&"mutators": {},
		&"game_modes": {},
	}
	_load_typed(&"res://data/enemies", &"enemies", tables, errors)
	_load_typed(&"res://data/upgrades", &"upgrades", tables, errors)
	_load_typed(&"res://data/arenas", &"arenas", tables, errors)
	_load_typed(&"res://data/cameras", &"cameras", tables, errors)
	_load_typed(&"res://data/weapons", &"weapons", tables, errors)
	_load_typed(&"res://data/skills", &"skills", tables, errors)
	_load_typed(&"res://data/status", &"status", tables, errors)
	_load_typed(&"res://data/pickups", &"pickups", tables, errors)
	_load_typed(&"res://data/waves", &"waves", tables, errors)
	_load_typed(&"res://data/hazards", &"hazards", tables, errors)
	_load_typed(&"res://data/hazard_modes", &"hazard_modes", tables, errors)
	_load_typed(&"res://data/mutators", &"mutators", tables, errors)
	# After the hazard-mode overlays, whose configs ask `GameMode` whether a mode id is real. That
	# query no longer depends on this order — `GameMode._all_configs()` falls back to the folder while
	# the registry is still half-built — but keeping the loader's own order dependency-shaped is why
	# this line sits where it does, and a fallback that never has to run is better than one that must.
	_load_typed(&"res://data/game_modes", &"game_modes", tables, errors)
	var prestige_ladder := _load_prestige_ladder(errors)
	_validate_references(tables, errors, prestige_ladder)
	var audio := _load_audio_streams(errors)
	var first_arena := &""
	var arenas: Dictionary = tables[&"arenas"]
	if not arenas.is_empty():
		var keys: Array = arenas.keys()
		keys.sort()
		first_arena = StringName(String(keys[0]))
	return {
		"tables": tables,
		"waves": tables[&"waves"],
		"audio": audio,
		"errors": errors,
		"first_arena": first_arena,
		"prestige_ladder": prestige_ladder,
	}


## Cross-resource references are validated after every directory is loaded. A
## malformed reference remains visible in the registry for diagnostics but is
## never silently treated as a valid build card/proc.
static func _validate_references(tables: Dictionary, errors: Array[String], prestige_ladder: PrestigeLadderConfig = null) -> void:
	var statuses: Dictionary = tables[&"status"]
	for raw in (tables[&"weapons"] as Dictionary).values():
		var weapon := raw as WeaponConfig
		if weapon == null:
			continue
		for effect_id in weapon.on_hit_effects:
			if not statuses.has(effect_id):
				errors.append("weapon %s references unknown status %s" % [String(weapon.weapon_id), String(effect_id)])
	for raw in (tables[&"skills"] as Dictionary).values():
		var skill := raw as SkillConfig
		if skill == null:
			continue
		for effect_id in skill.victim_effects + skill.caster_effects:
			if not statuses.has(effect_id):
				errors.append("skill %s references unknown status %s" % [String(skill.skill_id), String(effect_id)])
	var upgrades: Dictionary = tables[&"upgrades"]
	for raw in upgrades.values():
		var upgrade := raw as UpgradeConfig
		if upgrade == null:
			continue
		for prereq in upgrade.prerequisites:
			if not upgrades.has(prereq):
				errors.append("upgrade %s references unknown prerequisite %s" % [String(upgrade.upgrade_id), String(prereq)])
		for exclusion in upgrade.exclusions:
			if not upgrades.has(exclusion):
				errors.append("upgrade %s references unknown exclusion %s" % [String(upgrade.upgrade_id), String(exclusion)])
	# The announcer's three lines, for shipped arenas only. `ArenaConfig.validate()` refuses to require
	# them (a hand-built probe arena is legal), so this is the place that knows the difference between a
	# fixture and content: a file in res://data/arenas/ that leaves the announcer with nothing to say at
	# wave 1, wave 5 or wave 10 is a hole in the run, not a testing convenience. Named per field,
	# because "the lore is empty" would not say which beat went quiet.
	for raw in (tables[&"arenas"] as Dictionary).values():
		var arena := raw as ArenaConfig
		if arena == null:
			continue
		if arena.lore_intro.is_empty():
			errors.append("arena %s authors no lore_intro; the run start has nothing to say"
					% String(arena.arena_id))
		if arena.lore_mid.is_empty():
			errors.append("arena %s authors no lore_mid; wave 5 has nothing to say" % String(arena.arena_id))
		if arena.lore_late.is_empty():
			errors.append("arena %s authors no lore_late; the tenth wave has nothing to say"
					% String(arena.arena_id))

	# Hazards: the status a disc stamps has to exist, and a throttled field must re-stamp
	# it before it lapses (otherwise the pool "blinks" the slow on and off, which reads as
	# a bug in a game where kiting through hazards is a real tactic). A hazard config with
	# no authored status is a different kind of problem, so this table being empty is too.
	var hazards: Dictionary = tables[&"hazards"]
	if hazards.is_empty():
		errors.append("no HazardConfig resources under res://data/hazards — arenas cannot build a layout")
	for raw in hazards.values():
		var hazard := raw as HazardConfig
		if hazard == null:
			continue
		if not hazard.has_status():
			continue
		if not statuses.has(hazard.status_effect_id):
			errors.append("hazard %s references unknown status %s" % [String(hazard.hazard_id), String(hazard.status_effect_id)])
			continue
		var effect: StatusEffectConfig = statuses.get(hazard.status_effect_id)
		if effect != null and hazard.victim_cooldown > 0.0 and not effect.is_permanent() \
				and effect.duration <= hazard.victim_cooldown:
			errors.append("hazard %s re-stamps %s every %.2fs but the effect only lasts %.2fs" % [
				String(hazard.hazard_id), String(hazard.status_effect_id), hazard.victim_cooldown, effect.duration,
			])
	# Wave mutators. This table used to be a `match` inside WaveMutators that returned a NEUTRAL
	# definition for any id it did not recognise, so every authored reference below was a way to
	# ship a banner line that changed nothing. They are startup errors now.
	var mutators: Dictionary = tables[&"mutators"]
	if mutators.is_empty():
		errors.append("no WaveMutatorConfig resources under res://data/mutators — waves cannot resolve modifiers")
	var roll_orders := {}
	for raw in mutators.values():
		var mutator := raw as WaveMutatorConfig
		if mutator == null:
			continue
		if mutator.has_status() and not statuses.has(mutator.status_effect_id):
			errors.append("mutator %s references unknown status %s" % [
				String(mutator.mutator_id), String(mutator.status_effect_id),
			])
		if mutator.roll_order in roll_orders:
			# Ties are resolved by id, so a collision is not undefined behaviour — it silently
			# reshuffles the daily challenge's pool. That is still an authoring mistake.
			errors.append("mutators %s and %s both claim roll_order %d (the daily pool order is authored)" % [
				String(roll_orders[mutator.roll_order]), String(mutator.mutator_id), mutator.roll_order,
			])
		else:
			roll_orders[mutator.roll_order] = mutator.mutator_id
	for raw in (tables[&"waves"] as Dictionary).values():
		var wave := raw as WaveConfig
		if wave == null:
			continue
		for mutator_id in wave.arena_modifier_ids:
			if not mutators.has(mutator_id):
				errors.append("wave %d declares unknown mutator %s" % [
					wave.wave_number, String(mutator_id),
				])
	_validate_game_modes(tables, mutators, prestige_ladder, errors)


## The run-definition cross-checks. Each of these was previously *assumed* across two or three
## files with nothing enforcing it: a mode's forced mutators and its prestige pool had to name real
## mutators, a tier's mutator_count had to fit inside the pool it draws from, tier 0 had to agree
## with the mode's own opening payout, the ladder's top rung had to be reachable at the ladder's top
## rank, and a scripted wave had to name an archetype the enemy folder actually ships. A `match` arm
## over `&"warlord"` cannot be checked by anyone but the reader.
static func _validate_game_modes(tables: Dictionary, mutators: Dictionary,
		ladder: PrestigeLadderConfig, errors: Array[String]) -> void:
	var modes: Dictionary = tables[&"game_modes"]
	if modes.is_empty():
		errors.append("no GameModeConfig resources under res://data/game_modes — the run setup has no modes")
		return
	var enemies: Dictionary = tables[&"enemies"]
	var weapons: Dictionary = tables[&"weapons"]
	for raw in modes.values():
		var mode := raw as GameModeConfig
		if mode == null:
			continue
		for mutator_id in mode.forced_mutators:
			if not mutators.has(mutator_id):
				errors.append("game mode %s forces unknown mutator %s" % [String(mode.mode_id), String(mutator_id)])
		for mutator_id in mode.prestige_mutator_pool:
			if not mutators.has(mutator_id):
				errors.append("game mode %s pools unknown mutator %s" % [String(mode.mode_id), String(mutator_id)])
		if mode.fixed_weapon != &"" and not weapons.has(mode.fixed_weapon):
			errors.append("game mode %s pins fixed_weapon %s, which is not an authored weapon"
					% [String(mode.mode_id), String(mode.fixed_weapon)])
		for archetype_id in mode.every_n_append:
			if not enemies.has(archetype_id):
				errors.append("game mode %s appends unknown archetype %s every %d waves"
						% [String(mode.mode_id), String(archetype_id), mode.every_n_waves])
		for plan in mode.wave_plans:
			if plan == null:
				continue
			for archetype_id in plan.archetypes:
				if not enemies.has(archetype_id):
					errors.append("game mode %s wave %d spawns unknown archetype %s"
							% [String(mode.mode_id), plan.wave_number, String(archetype_id)])
		if mode.scales_with_prestige:
			_validate_scaled_mode(mode, ladder, errors)


static func _validate_scaled_mode(mode: GameModeConfig, ladder: PrestigeLadderConfig,
		errors: Array[String]) -> void:
	if ladder == null:
		errors.append("game mode %s scales with prestige but res://data/prestige/ladder.tres is missing"
				% String(mode.mode_id))
		return
	var pool_size := mode.prestige_mutator_pool.size()
	for tier in ladder.challenge_tiers:
		if tier == null:
			continue
		if tier.mutator_count > pool_size:
			errors.append("challenge tier '%s' wants %d mutators but mode %s pools %d"
					% [tier.label, tier.mutator_count, String(mode.mode_id), pool_size])
	var first := ladder.challenge_tiers[0] if not ladder.challenge_tiers.is_empty() else null
	if first == null:
		errors.append("game mode %s scales with prestige but the ladder has no tier for rank 0"
				% String(mode.mode_id))
		return
	# Tier 0 *is* the mode's base row: the run-setup card reads the mode's authored numbers and a
	# Challenge run folds the tier's, so the two must say the same thing or the card lies.
	if not is_equal_approx(first.score_mult, mode.score_mult) \
			or not is_equal_approx(first.currency_mult, mode.currency_mult):
		errors.append("challenge tier 0 pays x%.2f/x%.2f but mode %s authors x%.2f/x%.2f"
				% [first.score_mult, first.currency_mult, String(mode.mode_id), mode.score_mult,
					mode.currency_mult])
	if first.mutator_count != mode.forced_mutators.size():
		errors.append("challenge tier 0 takes %d mutators but mode %s authors %d in forced_mutators"
				% [first.mutator_count, String(mode.mode_id), mode.forced_mutators.size()])
	if first.max_waves != mode.max_waves:
		errors.append("challenge tier 0 caps at %d waves but mode %s authors max_waves %d"
				% [first.max_waves, String(mode.mode_id), mode.max_waves])
	if ladder.max_rank > 0 and ladder.challenge_tiers[ladder.challenge_tiers.size() - 1].unlock_rank > ladder.max_rank:
		errors.append("the top challenge tier unlocks at prestige %d, past the ladder's max_rank %d"
				% [ladder.challenge_tiers[ladder.challenge_tiers.size() - 1].unlock_rank, ladder.max_rank])


## One ladder for the whole game: it is a sequence (cost curve, dense titles, ordered rungs), so it
## is a single file rather than a folder of ids.
static func _load_prestige_ladder(errors: Array[String]) -> PrestigeLadderConfig:
	var path := "res://data/prestige/ladder.tres"
	if not ResourceLoader.exists(path):
		errors.append("Missing prestige ladder: %s (the armory cannot price prestige without it)" % path)
		return null
	var ladder := ResourceLoader.load(path) as PrestigeLadderConfig
	if ladder == null:
		errors.append("Not a PrestigeLadderConfig: %s" % path)
		return null
	for problem in ladder.validate():
		errors.append("%s: %s" % [path, problem])
	return ladder


static func _load_typed(dir_path: String, kind: StringName, tables: Dictionary, errors: Array[String]) -> void:
	var files := _list_resources(dir_path)
	for path in files:
		var res := ResourceLoader.load(path)
		if res == null:
			errors.append("Failed to load resource: %s" % path)
			continue
		match kind:
			&"enemies":
				_register_one(tables[&"enemies"], res, path, &"enemy", errors)
			&"upgrades":
				_register_one(tables[&"upgrades"], res, path, &"upgrade", errors)
			&"arenas":
				var arena := res as ArenaConfig
				if arena == null:
					errors.append("Not an ArenaConfig: %s" % path)
				else:
					_register_resource(tables[&"arenas"], StringName(arena.arena_id), arena, path, errors)
			&"cameras":
				var cam := res as CameraProfile
				if cam == null:
					errors.append("Not a CameraProfile: %s" % path)
				else:
					_register_resource(tables[&"cameras"], StringName(cam.profile_id), cam, path, errors)
			&"weapons":
				var weapon := res as WeaponConfig
				if weapon == null:
					errors.append("Not a WeaponConfig: %s" % path)
				else:
					_register_resource(tables[&"weapons"], StringName(weapon.weapon_id), weapon, path, errors)
			&"skills":
				var skill := res as SkillConfig
				if skill == null:
					errors.append("Not a SkillConfig: %s" % path)
				else:
					_register_resource(tables[&"skills"], StringName(skill.skill_id), skill, path, errors)
			&"status":
				var effect := res as StatusEffectConfig
				if effect == null:
					errors.append("Not a StatusEffectConfig: %s" % path)
				else:
					_register_resource(tables[&"status"], StringName(effect.effect_id), effect, path, errors)
			&"mutators":
				var mutator := res as WaveMutatorConfig
				if mutator == null:
					errors.append("Not a WaveMutatorConfig: %s" % path)
				else:
					_register_resource(tables[&"mutators"], StringName(mutator.mutator_id), mutator, path, errors)
			&"game_modes":
				var mode := res as GameModeConfig
				if mode == null:
					errors.append("Not a GameModeConfig: %s" % path)
				else:
					_register_resource(tables[&"game_modes"], StringName(mode.mode_id), mode, path, errors)
			&"hazards":
				var hazard := res as HazardConfig
				if hazard == null:
					errors.append("Not a HazardConfig: %s" % path)
				else:
					_register_resource(tables[&"hazards"], StringName(hazard.hazard_id), hazard, path, errors)
			&"hazard_modes":
				var hazard_mode := res as HazardModeLayout
				if hazard_mode == null:
					errors.append("Not a HazardModeLayout: %s" % path)
				else:
					_register_resource(tables[&"hazard_modes"], StringName(hazard_mode.mode_id), hazard_mode, path, errors)
			&"pickups":
				var pickup := res as PickupConfig
				if pickup == null:
					errors.append("Not a PickupConfig: %s" % path)
				else:
					_register_resource(tables[&"pickups"], StringName(pickup.pickup_id), pickup, path, errors)
			&"waves":
				var wave := res as WaveConfig
				if wave == null:
					errors.append("Not a WaveConfig: %s" % path)
				elif (tables[&"waves"] as Dictionary).has(wave.wave_number):
					errors.append("Duplicate wave_number %d: %s" % [wave.wave_number, path])
				else:
					for problem in wave.validate():
						errors.append("%s: %s" % [path, problem])
					(tables[&"waves"] as Dictionary)[wave.wave_number] = wave


## Typed id extraction: enemy configs carry archetype_id, upgrades upgrade_id.
## A resource of the wrong type in a content directory is a hard authoring error;
## an empty id is reported by each config's own validate().
static func _register_one(table: Dictionary, res: Resource, path: String, kind: String, errors: Array[String]) -> void:
	var idn := &""
	if kind == &"enemy":
		var enemy_cfg := res as EnemyConfig
		if enemy_cfg == null:
			errors.append("Not an EnemyConfig: %s" % path)
			return
		idn = enemy_cfg.archetype_id
	else:
		var upgrade_cfg := res as UpgradeConfig
		if upgrade_cfg == null:
			errors.append("Not an UpgradeConfig: %s" % path)
			return
		idn = upgrade_cfg.upgrade_id
	_register_resource(table, idn, res, path, errors)


static func _register_resource(table: Dictionary, idn: StringName, res: Resource, path: String, errors: Array[String]) -> void:
	if table.has(idn):
		errors.append("Duplicate id '%s' across content files" % String(idn))
		return
	var cfg := res as ValidatedConfig
	if cfg != null:
		for problem in cfg.validate():
			errors.append("%s: %s" % [path, problem])
	table[idn] = res


## Load audio streams keyed by file base name (registration with AudioManager stays
## in the registry so this loader never touches autoloads).
static func _load_audio_streams(errors: Array[String]) -> Dictionary:
	var out: Dictionary = {}
	var files := _list_resources(&"res://data/audio", AUDIO_EXTENSIONS)
	for path in files:
		var stream := ResourceLoader.load(path)
		if stream is AudioStream:
			var idn := StringName(path.get_file().get_basename())
			out[idn] = stream
		elif stream == null:
			errors.append("Failed to load audio: %s" % path)
	return out


## Audio drops accept raw sound files too (the documented .ogg workflow):
## anything Godot imports as an AudioStream is a valid cue.
const AUDIO_EXTENSIONS := [".tres", ".res", ".ogg", ".wav", ".mp3"]


static func _list_resources(dir_path: String, extensions: Array = [".tres"]) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	_recursive_list(dir_path, extensions, out)
	out.sort()
	return out


static func _recursive_list(dir_path: String, extensions: Array, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		var full := dir_path.path_join(file)
		if dir.current_is_dir():
			# Recurse into subdirectories (e.g. data/enemies/bosses/) — flat directories
			# remain supported, but future organization does not silently stop discovery.
			if not file.begins_with("."):
				_recursive_list(full, extensions, out)
		elif _has_extension(file, extensions):
			# Skip Godot's import sidecars; load() resolves the real resource.
			var clean_file := file.trim_suffix(".remap")
			if not clean_file.ends_with(".import") and not clean_file.ends_with(".godot"):
				var clean_full := dir_path.path_join(clean_file)
				if clean_full not in out:
					out.append(clean_full)
		file = dir.get_next()
	dir.list_dir_end()


static func _has_extension(file: String, extensions: Array) -> bool:
	var clean := file.trim_suffix(".remap")
	for ext in extensions:
		if clean.ends_with(String(ext)):
			return true
	return false
