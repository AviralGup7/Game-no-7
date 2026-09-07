extends Node
## Autoload: SaveManager
## Versioned local persistence. Owns load/validate/migrate/backup/corruption recovery
## of the user save. Never writes during every frame or every score change: changes
## mark the store dirty and a debounced flush writes atomically at explicit points.
## Schema 3 adds tutorial completion, achievements, and the meta-progression wallet.

const SAVE_PATH := "user://last_stand_save.json"
const BACKUP_PATH := "user://last_stand_save.backup.json"
const SCHEMA_VERSION := 3
const SAVE_DEBOUNCE_MSEC := 1200
const MAX_VALID_SAVE_BYTES := 1 << 20  # 1 MiB safety cap

var _save := _default_save_static()
var _dirty := false
var _settings := SettingsData.new()
var _loaded_from_disk := false
var _debounce: Timer = null


func _ready() -> void:
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = SAVE_DEBOUNCE_MSEC / 1000.0
	_debounce.timeout.connect(_flush_save)
	add_child(_debounce)
	_load_from_disk()


# ---------------------------- Public query API ----------------------------

func get_best_score() -> int:
	return _save.best_score


func get_best_wave() -> int:
	return _save.best_wave


func get_settings() -> SettingsData:
	return _settings


func has_loaded() -> bool:
	return _loaded_from_disk


func get_save_dict() -> Dictionary:
	return _save


## Record a completed run: refresh best score/wave and lifetime statistics.
func record_run_completed(summary: Dictionary) -> void:
	var score := int(summary.get("score", 0))
	var wave := int(summary.get("current_wave", 0))
	if score > _save.best_score:
		_save.best_score = score
	if wave > _save.best_wave:
		_save.best_wave = wave
	var ls: Dictionary = _save.lifetime_statistics
	ls.total_runs = int(ls.total_runs) + 1
	ls.total_kills = int(ls.total_kills) + int(summary.get("kills", 0))
	ls.total_time_seconds = float(ls.total_time_seconds) + float(summary.get("elapsed_seconds", 0.0))
	ls.highest_combo = maxi(int(ls.highest_combo), int(summary.get("best_combo", 0)))
	mark_dirty()


## Apply runtime settings back into the store and mark dirty.
func persist_settings() -> void:
	_save.settings = _settings.to_dict()
	mark_dirty()


## Replace the live settings object (settings UI apply path) + persist + notify.
func save_settings(settings: SettingsData) -> void:
	if settings == null:
		return
	_settings = settings
	persist_settings()
	EventBus.settings_changed.emit(_settings)


func reset_settings() -> void:
	_settings = SettingsData.new()
	persist_settings()
	EventBus.settings_changed.emit(_settings)


func unlock_upgrade(upgrade_id: String) -> void:
	var list: Array = _save.progression.unlocked_upgrades
	if upgrade_id not in list:
		list.append(upgrade_id)
		mark_dirty()


func unlock_arena(arena_id: String) -> void:
	var list: Array = _save.progression.unlocked_arenas
	if arena_id not in list:
		list.append(arena_id)
		mark_dirty()


# ---------------------------- Tutorial / achievements / meta ----------------------------

func is_tutorial_completed() -> bool:
	return bool(_save.get("tutorial_completed", false))


func set_tutorial_completed(completed: bool = true) -> void:
	_save.tutorial_completed = completed
	mark_dirty()


func get_unlocked_achievements() -> Array:
	return (_save.get("achievements", []) as Array).duplicate()


func unlock_achievement(achievement_id: StringName) -> bool:
	var list: Array = _save.achievements
	var key := String(achievement_id)
	if key in list:
		return false
	list.append(key)
	mark_dirty()
	return true


func get_meta_wallet() -> int:
	return maxi(int(_save.get("meta_wallet", 0)), 0)


func set_meta_wallet(balance: int) -> void:
	_save.meta_wallet = maxi(balance, 0)
	mark_dirty()


func get_meta_ranks() -> Dictionary:
	return (_save.get("meta_ranks", {}) as Dictionary).duplicate()


func set_meta_ranks(ranks: Dictionary) -> void:
	var clean: Dictionary = {}
	for key in ranks:
		clean[String(key)] = maxi(int(ranks[key]), 0)
	_save.meta_ranks = clean
	mark_dirty()


func mark_dirty() -> void:
	_dirty = true
	if _debounce != null:
		_debounce.start()


func request_save() -> bool:
	if _dirty:
		return _flush_save()
	return true


## Immediate flush (armory purchases, achievement unlocks, app pause).
func save_now() -> bool:
	return _flush_save()


# ---------------------------- Persistence ----------------------------

func _load_from_disk() -> void:
	var raw: Variant = _read_raw(SAVE_PATH)
	if raw == null:
		raw = _read_raw(BACKUP_PATH)
		if raw != null:
			EventBus.report_info("Recovered save from backup after primary was unreadable")
	var data := validate_save_data(raw)
	_apply_validated(data)
	# Emit a settings_changed on load so live systems adopt persisted settings.
	EventBus.settings_changed.emit(_settings)
	_loaded_from_disk = true


func _flush_save() -> bool:
	if not _dirty:
		return true
	# Write backup of the previous good file first (destructive-recovery safety).
	var previous: Variant = _read_raw(SAVE_PATH)
	if previous != null:
		_write_raw(BACKUP_PATH, JSON.stringify(previous))
	var ok := _write_raw(SAVE_PATH, JSON.stringify(_save))
	_dirty = false
	if ok:
		EventBus.save_completed.emit()
	else:
		EventBus.save_failed.emit(&"write_failed")
	return ok


func _read_raw(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	if file.get_length() > MAX_VALID_SAVE_BYTES:
		EventBus.report_warning("Save file too large; treating as corrupt: %s" % path)
		return null
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	return parsed


func _write_raw(path: String, contents: String) -> bool:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(contents)
	file.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if err != OK and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		err = DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	return err == OK


func _apply_validated(data: Dictionary) -> void:
	_save = data
	_settings.from_dict(_save.settings)
	_save.settings = _settings.to_dict()


# ---------------------------- Pure validation ----------------------------

## Pure, headless-testable validator/migrator. Accepts any Variant (raw JSON, null,
## dict with wrong shape) and returns a fully-valid, normalized save Dictionary.
## It never throws and never touches autoloads/disk, so unit tests can load this
## script by path and call it directly.
static func normalize_save(raw_data: Variant) -> Dictionary:
	var out := _default_save_static()
	if raw_data == null or not raw_data is Dictionary:
		return out
	var data: Dictionary = raw_data
	var version := _int_or(_dict_get(data, "schema_version", SCHEMA_VERSION), SCHEMA_VERSION)
	if version > SCHEMA_VERSION:
		# Newer schema: keep what we understand, discard the rest rather than crash.
		pass
	if version < SCHEMA_VERSION:
		data = _migrate_static(data, version)
	out.schema_version = SCHEMA_VERSION
	out.best_score = maxi(0, _int_or(_dict_get(data, "best_score", 0), 0))
	out.best_wave = maxi(0, _int_or(_dict_get(data, "best_wave", 0), 0))
	out.tutorial_completed = bool(_dict_get(data, "tutorial_completed", false))
	out.achievements = _string_list(_dict_get(data, "achievements", []))
	out.meta_wallet = maxi(0, _int_or(_dict_get(data, "meta_wallet", 0), 0))
	out.meta_ranks = _string_int_map(_dict_get(data, "meta_ranks", {}))
	if data.has("lifetime_statistics") and data.lifetime_statistics is Dictionary:
		var src: Dictionary = data.lifetime_statistics
		var ls: Dictionary = out.lifetime_statistics
		ls.total_runs = maxi(0, _int_or(_dict_get(src, "total_runs", 0), 0))
		ls.total_kills = maxi(0, _int_or(_dict_get(src, "total_kills", 0), 0))
		ls.total_time_seconds = maxf(0.0, _float_or(_dict_get(src, "total_time_seconds", 0.0), 0.0))
		ls.highest_combo = maxi(0, _int_or(_dict_get(src, "highest_combo", 0), 0))
		out.lifetime_statistics = ls
	if data.has("settings") and data.settings is Dictionary:
		var sd := SettingsData.new()
		sd.from_dict(data.settings)
		out.settings = sd.to_dict()
	if data.has("progression") and data.progression is Dictionary:
		var prog: Dictionary = data.progression
		var unlocked := _string_list(_dict_get(prog, "unlocked_upgrades", []))
		var arenas := _string_list(_dict_get(prog, "unlocked_arenas", ["default_arena"]))
		if "default_arena" not in arenas:
			arenas.append("default_arena")
		var cosmetics := _string_list(_dict_get(prog, "unlocked_cosmetics", []))
		out.progression = {
			"unlocked_upgrades": unlocked,
			"unlocked_arenas": arenas,
			"unlocked_cosmetics": cosmetics,
		}
	return out


## Instance convenience: returns the normalized save and adopts settings.
func validate_save_data(raw_data: Variant) -> Dictionary:
	var out := normalize_save(raw_data)
	_settings.from_dict(out.settings)
	out.settings = _settings.to_dict()
	return out


static func _migrate_static(data: Dictionary, from_version: int) -> Dictionary:
	if from_version <= 2:
		# v1/v2 -> v3: new keys (tutorial/achievements/meta) take safe defaults;
		# no structural rewrite required.
		pass
	return data


static func _default_save_static() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"best_score": 0,
		"best_wave": 0,
		"tutorial_completed": false,
		"achievements": [],
		"meta_wallet": 0,
		"meta_ranks": {},
		"lifetime_statistics": {
			"total_runs": 0,
			"total_kills": 0,
			"total_time_seconds": 0.0,
			"highest_combo": 0,
		},
		"settings": SettingsData.new().to_dict(),
		"progression": {
			"unlocked_upgrades": [],
			"unlocked_arenas": ["default_arena"],
			"unlocked_cosmetics": [],
		},
	}


static func _dict_get(data: Dictionary, key: String, fallback: Variant) -> Variant:
	return data.get(key, fallback)


static func _int_or(value: Variant, fallback: int) -> int:
	if value is float or value is int:
		return int(value)
	return fallback


static func _float_or(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		return float(value)
	return fallback


static func _string_list(value: Variant) -> Array:
	var out: Array = []
	if value is Array:
		for item in value:
			out.append(String(item))
	return out


static func _string_int_map(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if value is Dictionary:
		for key in value:
			var v: Variant = value[key]
			if v is float or v is int:
				out[String(key)] = maxi(int(v), 0)
	return out
