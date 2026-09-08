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
	_validate_references(tables, errors)
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
	}


## Cross-resource references are validated after every directory is loaded. A
## malformed reference remains visible in the registry for diagnostics but is
## never silently treated as a valid build card/proc.
static func _validate_references(tables: Dictionary, errors: Array[String]) -> void:
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
					if wave.has_method("validate"):
						var wave_problems: Array = wave.call("validate")
						for p in wave_problems:
							errors.append("%s: %s" % [path, p])
					(tables[&"waves"] as Dictionary)[wave.wave_number] = wave


static func _register_one(table: Dictionary, res: Resource, path: String, kind: String, errors: Array[String]) -> void:
	var id_value: Variant = res.get("archetype_id") if kind == "enemy" else res.get("upgrade_id")
	if id_value == null:
		errors.append("%s missing id: %s" % [kind, path])
		return
	var idn := StringName(String(id_value))
	_register_resource(table, idn, res, path, errors)


static func _register_resource(table: Dictionary, idn: StringName, res: Resource, path: String, errors: Array[String]) -> void:
	if table.has(idn):
		errors.append("Duplicate id '%s' across content files" % String(idn))
		return
	if res.has_method("validate"):
		var problems: Array = res.call("validate")
		for p in problems:
			errors.append("%s: %s" % [path, p])
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
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir() and _has_extension(file, extensions):
			# Skip Godot's import sidecars; load() resolves the real resource.
			if not file.ends_with(".import") and not file.ends_with(".godot"):
				out.append(dir_path.path_join(file))
		file = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


static func _has_extension(file: String, extensions: Array) -> bool:
	for ext in extensions:
		if file.ends_with(String(ext)):
			return true
	return false

## Hardened: validate content path before load.
func _validated_content_path(p: String) -> bool:
    if p.is_empty() or not p.begins_with("res://"):
        return false
    return true

