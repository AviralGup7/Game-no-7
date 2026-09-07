extends Node
## Autoload: ContentRegistry
## Owns the live content tables and exposes enemy / upgrade / arena / weapon /
## camera / audio / skill / status / pickup / wave definitions. Scanning +
## typed registration moved to ContentLoader; this node adopts the loaded tables,
## keeps arena selection, and registers audio cues. Every registry is tolerant:
## missing or invalid optional content produces diagnostics + fallback and never
## crashes startup. Adding content = drop a .tres in the right folder and
## (optionally) register a default; no core-script rewrites.

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
	var loaded := ContentLoader.load_all()
	var tables: Dictionary = loaded["tables"]
	_enemies = tables[&"enemies"]
	_upgrades = tables[&"upgrades"]
	_arenas = tables[&"arenas"]
	_cameras = tables[&"cameras"]
	_weapons = tables[&"weapons"]
	_skills = tables[&"skills"]
	_status = tables[&"status"]
	_pickups = tables[&"pickups"]
	_waves = tables[&"waves"]
	_validation_errors = loaded["errors"]
	var first_arena: StringName = loaded.get("first_arena", &"")
	if _selected_arena == &"" and first_arena != &"":
		_selected_arena = first_arena
	_register_audio_cues(loaded["audio"])
	# Procedural fallback: synthesize any cue still missing so the game is
	# never silent (real audio drops in data/audio/ always take precedence).
	ProceduralSfx.ensure_registered()
	_validation_dirty = true


func _register_audio_cues(cues: Dictionary) -> void:
	_audio_cues.clear()
	for idn in cues:
		register_audio_cue(idn, cues[idn])


## Register one cue in both the lookup table and the AudioManager voices.
func register_audio_cue(cue_id: StringName, stream: AudioStream) -> void:
	if stream == null:
		return
	_audio_cues[cue_id] = stream
	AudioManager.register_cue(cue_id, stream)


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
		"skill_count": _skills.size(),
		"status_count": _status.size(),
		"pickup_count": _pickups.size(),
		"wave_count": _waves.size(),
		"audio_cue_count": _audio_cues.size(),
		"selected_arena": String(_selected_arena),
		"validation_errors": _validation_errors.size(),
	}
