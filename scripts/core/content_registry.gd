extends Node
## Autoload: ContentRegistry
## Discovers, validates, caches, and exposes enemy / upgrade / arena / weapon /
## camera / audio / skill / status / pickup / wave definitions from res://data/**
## .tres resources. Every registry is tolerant: missing or invalid optional
## content produces diagnostics + fallback and never crashes startup. Adding
## content = drop a .tres in the right folder and (optionally) register a
## default; no core-script rewrites.

const DATA_ROOT := "res://data"

var _enemies: Dictionary = {}        # StringName -> EnemyConfig
var _upgrades: Dictionary = {}       # StringName -> UpgradeConfig
var _arenas: Dictionary = {}         # StringName -> ArenaConfig
var _cameras: Dictionary = {}        # StringName -> CameraProfile
var _weapons: Dictionary = {}        # StringName -> WeaponConfig
var _skills: Dictionary = {}         # StringName -> SkillConfig
var _status: Dictionary = {}         # StringName -> StatusEffectConfig
var _pickups: Dictionary = {}        # StringName -> PickupConfig
var _waves: Dictionary = {}          # int wave_number -> WaveConfig
var _audio_cues: Dictionary = {}     # StringName -> AudioStream
var _selected_arena: StringName = &"default_arena"
var _validation_errors: Array[String] = []
var _validation_dirty := true


func _ready() -> void:
	refresh_all()
	EventBus.report_info("ContentRegistry ready: %d enemies, %d upgrades, %d arenas, %d cameras, %d weapons, %d skills, %d status, %d pickups, %d waves" % [
		_enemies.size(), _upgrades.size(), _arenas.size(), _cameras.size(),
		_weapons.size(), _skills.size(), _status.size(), _pickups.size(), _waves.size()
	])


## Re-scan all data directories. Called at startup and available to tooling/tests.
func refresh_all() -> void:
	_validation_errors.clear()
	_load_typed(&"res://data/enemies", &"enemies")
	_load_typed(&"res://data/upgrades", &"upgrades")
	_load_typed(&"res://data/arenas", &"arenas")
	_load_typed(&"res://data/cameras", &"cameras")
	_load_typed(&"res://data/weapons", &"weapons")
	_load_typed(&"res://data/skills", &"skills")
	_load_typed(&"res://data/status", &"status")
	_load_typed(&"res://data/pickups", &"pickups")
	_load_typed(&"res://data/waves", &"waves")
	_load_audio()
	_validation_dirty = true


func _load_typed(dir_path: String, kind: StringName) -> void:
	var files := _list_resources(dir_path)
	for path in files:
		var res := ResourceLoader.load(path)
		if res == null:
			_validation_errors.append("Failed to load resource: %s" % path)
			continue
		match kind:
			&"enemies":
				_register_one(_enemies, res, path, &"enemy")
			&"upgrades":
				_register_one(_upgrades, res, path, &"upgrade")
			&"arenas":
				var arena := res as ArenaConfig
				if arena == null:
					_validation_errors.append("Not an ArenaConfig: %s" % path)
				else:
					_register_resource(_arenas, StringName(arena.arena_id), arena, path)
					if _selected_arena == &"" and arena.arena_id != &"":
						_selected_arena = arena.arena_id
			&"cameras":
				var cam := res as CameraProfile
				if cam == null:
					_validation_errors.append("Not a CameraProfile: %s" % path)
				else:
					_register_resource(_cameras, StringName(cam.profile_id), cam, path)
			&"weapons":
				var weapon := res as WeaponConfig
				if weapon == null:
					_validation_errors.append("Not a WeaponConfig: %s" % path)
				else:
					_register_resource(_weapons, StringName(weapon.weapon_id), weapon, path)
			&"skills":
				var skill := res as SkillConfig
				if skill == null:
					_validation_errors.append("Not a SkillConfig: %s" % path)
				else:
					_register_resource(_skills, StringName(skill.skill_id), skill, path)
			&"status":
				var effect := res as StatusEffectConfig
				if effect == null:
					_validation_errors.append("Not a StatusEffectConfig: %s" % path)
				else:
					_register_resource(_status, StringName(effect.effect_id), effect, path)
			&"pickups":
				var pickup := res as PickupConfig
				if pickup == null:
					_validation_errors.append("Not a PickupConfig: %s" % path)
				else:
					_register_resource(_pickups, StringName(pickup.pickup_id), pickup, path)
			&"waves":
				var wave := res as WaveConfig
				if wave == null:
					_validation_errors.append("Not a WaveConfig: %s" % path)
				elif _waves.has(wave.wave_number):
					_validation_errors.append("Duplicate wave_number %d: %s" % [wave.wave_number, path])
				else:
					if wave.has_method("validate"):
						var wave_problems: Array = wave.call("validate")
						for p in wave_problems:
							_validation_errors.append("%s: %s" % [path, p])
					_waves[wave.wave_number] = wave


func _register_one(table: Dictionary, res: Resource, path: String, kind: String) -> void:
	var id_value: Variant = res.get("archetype_id") if kind == "enemy" else res.get("upgrade_id")
	if id_value == null:
		_validation_errors.append("%s missing id: %s" % [kind, path])
		return
	var idn := StringName(String(id_value))
	_register_resource(table, idn, res, path)


func _register_resource(table: Dictionary, idn: StringName, res: Resource, path: String) -> void:
	if table.has(idn):
		_validation_errors.append("Duplicate id '%s' across content files" % String(idn))
		return
	if res.has_method("validate"):
		var problems: Array = res.call("validate")
		for p in problems:
			_validation_errors.append("%s: %s" % [path, p])
	table[idn] = res


func _load_audio() -> void:
	var files := _list_resources(&"res://data/audio")
	for path in files:
		var stream := ResourceLoader.load(path)
		if stream is AudioStream:
			var idn := StringName(path.get_file().get_basename())
			_audio_cues[idn] = stream
			AudioManager.register_cue(idn, stream)


func _list_resources(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir() and file.ends_with(".tres"):
			out.append(dir_path.path_join(file))
		file = dir.get_next()
	dir.list_dir_end()
	return out


# ---------------------- Lookup API ----------------------

func get_enemy(archetype_id: StringName) -> EnemyConfig:
	return _enemies.get(archetype_id)


func get_upgrade(upgrade_id: StringName) -> UpgradeConfig:
	return _upgrades.get(upgrade_id)


func get_arena(arena_id: StringName) -> ArenaConfig:
	return _arenas.get(arena_id)


func get_camera_profile(profile_id: StringName) -> CameraProfile:
	return _cameras.get(profile_id, _cameras.get(&"default"))


func get_all_enemy_ids() -> Array:
	return _enemies.keys()


func get_all_upgrades() -> Dictionary:
	return _upgrades


func get_weapon(weapon_id: StringName) -> WeaponConfig:
	return _weapons.get(weapon_id)


func get_all_weapons() -> Dictionary:
	return _weapons


func get_all_weapon_ids() -> Array:
	return _weapons.keys()


func get_skill(skill_id: StringName) -> SkillConfig:
	return _skills.get(skill_id)


func get_all_skills() -> Dictionary:
	return _skills


func get_all_skill_configs() -> Array:
	return _skills.values()


func get_status_effect(effect_id: StringName) -> StatusEffectConfig:
	return _status.get(effect_id)


func get_all_status_effects() -> Dictionary:
	return _status


func get_pickup(pickup_id: StringName) -> PickupConfig:
	return _pickups.get(pickup_id)


func get_all_pickups() -> Dictionary:
	return _pickups


func get_all_pickup_configs() -> Array:
	return _pickups.values()


## Authored wave override for `wave_number`, or null when generated waves apply.
func get_wave(wave_number: int) -> WaveConfig:
	return _waves.get(wave_number)


func has_authored_wave(wave_number: int) -> bool:
	return _waves.has(wave_number)


func get_all_waves() -> Dictionary:
	return _waves


func get_selected_arena_id() -> StringName:
	if not _arenas.has(_selected_arena):
		return &"default_arena"
	return _selected_arena


func select_arena(arena_id: StringName) -> bool:
	if not _arenas.has(arena_id):
		EventBus.report_warning("Cannot select unknown arena %s" % String(arena_id))
		return false
	_selected_arena = arena_id
	EventBus.report_info("Content selection changed to arena %s" % String(arena_id))
	return true


func get_camera_default() -> CameraProfile:
	return get_camera_profile(&"default")


func get_audio_cue(cue_id: StringName) -> AudioStream:
	return _audio_cues.get(cue_id)


func is_audio_present(cue_id: StringName) -> bool:
	return _audio_cues.has(cue_id)


# ---------------------- Validation ----------------------

## Re-validate all registered content. Returns false if any problems found.
func validate_all() -> bool:
	refresh_all()
	# Duplicate detection across enemies for the smoke test.
	var seen := {}
	for idn in _enemies:
		var key := String(idn)
		if seen.has(key):
			_validation_errors.append("Duplicate enemy archetype id: %s" % key)
		seen[key] = true
	if _validation_errors.is_empty():
		EventBus.report_info("ContentRegistry validation: OK")
		return true
	for e in _validation_errors:
		EventBus.report_error("Content validation: " + e)
	return false


func get_validation_errors() -> Array[String]:
	return _validation_errors


func get_debug_snapshot() -> Dictionary:
	return {
		"enemy_count": _enemies.size(),
		"upgrade_count": _upgrades.size(),
		"arena_count": _arenas.size(),
		"camera_count": _cameras.size(),
		"weapon_count": _weapons.size(),
		"skill_count": _skills.size(),
		"status_count": _status.size(),
		"pickup_count": _pickups.size(),
		"wave_count": _waves.size(),
		"audio_cue_count": _audio_cues.size(),
		"selected_arena": String(_selected_arena),
		"validation_errors": _validation_errors.size(),
	}
