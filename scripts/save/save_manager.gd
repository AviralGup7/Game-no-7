extends Node
## Autoload: SaveManager
## Versioned local persistence. Owns the live store, debounced atomic flush, and
## load/validate/migrate/backup/corruption recovery. The pure schema (defaults,
## validation, migration) lives in SaveSchema; this node delegates to it so the
## schema stays unit-testable without the autoload.

const SAVE_PATH := "user://last_stand_save.json"
const BACKUP_PATH := "user://last_stand_save.backup.json"
const SCHEMA_VERSION := SaveSchema.SCHEMA_VERSION
const SAVE_DEBOUNCE_MSEC := 1200
const MAX_VALID_SAVE_BYTES := 1 << 20  # 1 MiB safety cap

var _save := SaveSchema.default_save()
var _dirty := false
var _settings := SettingsData.new()
var _loaded_from_disk := false
var _debounce: Timer = null


func _ready() -> void:
	# Persistence must keep working while the tree is paused (the pause menu is
	# exactly where players change settings / buy armory ranks).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_debounce = Timer.new()
	_debounce.process_mode = Node.PROCESS_MODE_ALWAYS
	_debounce.one_shot = true
	_debounce.wait_time = SAVE_DEBOUNCE_MSEC / 1000.0
	_debounce.timeout.connect(_flush_save)
	add_child(_debounce)
	_load_from_disk()


func _notification(what: int) -> void:
	# Never lose a debounced write (best scores, armory, achievements). On Android
	# the app is normally backgrounded/killed without a CLOSE_REQUEST, so also flush
	# on focus loss and on the engine's predelete/exit paths.
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST, \
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, \
		NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_EXIT_TREE:
			_flush_save()


## Pure validator/migrator entry point (delegates to SaveSchema; kept here so
## headless tests can load this script by path and call it directly).
static func normalize_save(raw_data: Variant) -> Dictionary:
	return SaveSchema.normalize_save(raw_data)


## Instance convenience: returns the normalized save and adopts settings.
func validate_save_data(raw_data: Variant) -> Dictionary:
	var out := SaveSchema.normalize_save(raw_data)
	_settings.from_dict(out.settings)
	out.settings = _settings.to_dict()
	return out


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
	if bool(summary.get("victory", false)):
		ls.victories = int(ls.get("victories", 0)) + 1
	ls.bosses_slain = int(ls.get("bosses_slain", 0)) + int(summary.get("bosses_slain", 0))
	# Persist only the normalized, id-based build mirror. ProgressionComponent,
	# WeaponManager and SkillController remain the live runtime authorities.
	var build_value: Variant = summary.get("build", {})
	var normalized_build := SaveSchema.normalize_save({"last_run_build": build_value})
	_save.last_run_build = normalized_build.get("last_run_build", SaveSchema.default_run_build())
	mark_dirty()


## Read the last normalized build summary without exposing live runtime objects.
func get_last_run_build() -> Dictionary:
	return (_save.get("last_run_build", SaveSchema.default_run_build()) as Dictionary).duplicate(true)


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


func get_prestige_rank() -> int:
	return clampi(int(_save.get("prestige_rank", 0)), 0, Prestige.MAX_PRESTIGE)


func set_prestige_rank(rank: int) -> void:
	_save.prestige_rank = clampi(rank, 0, Prestige.MAX_PRESTIGE)
	mark_dirty()


func unlock_cosmetic(cosmetic_id: String) -> void:
	var list: Array = _save.progression.unlocked_cosmetics
	if cosmetic_id not in list:
		list.append(cosmetic_id)
		mark_dirty()


func get_unlocked_cosmetics() -> Array:
	return (_save.progression.get("unlocked_cosmetics", []) as Array).duplicate()


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
	if ok:
		_dirty = false
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
	# Older saves normalized by SaveSchema always have this field, but keep the
	# instance resilient if a caller supplied a hand-built dictionary.
	if not _save.has("last_run_build"):
		_save.last_run_build = SaveSchema.default_run_build()
	_settings.from_dict(_save.settings)
	_save.settings = _settings.to_dict()

## Hardened: validate currency before persisting.
func _validated_currency(v: int) -> int:
	if v < 0:
		return 0
	if v > 999999999:
		return 999999999
	return v

## Hardened: validate save dict.
func _validated_save_dict(d: Dictionary) -> Dictionary:
	if d == null or d.is_empty():
		return {}
	var out: Dictionary = {}
	for k in d.keys():
		var v:Variant = d[k]
		if v is float and not is_finite(float(v)):
			continue
		if k is String and str(k).is_empty():
			continue
		out[k] = v
	return out

## Hardened: clamp save version.
func _validated_save_version(v: int) -> int:
	if v < 1:
		return 1
	if v > 100:
		return 100
	return v

