class_name DebugErrorHandlerService
extends Node
## Autoload: DebugErrorHandler (declared directly after EventBus in project.godot).
##
## Debug-mode error trap for on-device (APK) debugging. When the debug flag is
## ON, any error reported through EventBus (the codebase's canonical failure
## channel — world build, arena, player spawn, waves, saves) freezes the tree
## instead of crashing and presents a copyable report with message, stack
## trace, device/game context, and the recent-log tail. When OFF, the game
## behaves exactly as before; errors are still appended to the session log.
##
## What this can and cannot catch, honestly:
## - Authored failure points (EventBus.report_error) -> freeze + report. This is
##   every critical boot/run system in the game.
## - Hard native crashes (segfault, OOM kill, force-stop) cannot be intercepted
##   from GDScript. For those, every boot checks the previous session's exit
##   flag and keeps its recovered log tail one click away in Settings > Debug.
##   (Android background kills also count as unclean — a hint, not proof.)
## - Headless runs (--headless, CI) never freeze: there is no screen to read
##   the report on. They still log and still write crash files.
##
## Autoload-order contract: this singleton reads EventBus signals only, and it
## persists its own flag in user://debug_mode.cfg (never SaveManager), so it can
## sit second and capture boot errors from every later singleton. Error handling
## itself must never emit diagnostics: all I/O failures here use push_warning
## directly, which cannot re-enter _on_diagnostic.

signal debug_mode_changed(enabled: bool)
signal error_captured(report_count: int)

const CONFIG_PATH := "user://debug_mode.cfg"
const CONFIG_SECTION := "debug"
const CONFIG_KEY := "debug_mode"
const LOG_DIR := "user://logs"
const SESSION_LOG := "user://logs/session.log"
const PREVIOUS_LOG := "user://logs/session.previous.log"
const SESSION_STATE := "user://logs/session.json"
const MAX_SESSION_LOG_BYTES := 262144
const MAX_CRASH_FILES := 5
const LOG_TAIL_LINES := 60
const MAX_REPORTS := 10
const CMDLINE_ENABLE := "--debug-mode"
const CMDLINE_NO_FREEZE := "--no-debug-freeze"

var _debug_mode := false
var _buffer := DebugLogBuffer.new()
var _reports: Array[String] = []
var _pending: Array[Dictionary] = []
var _current := 0
var _overlay: DebugErrorOverlay
var _frozen := false
var _fallback_pause := false
var _draining := false
var _previous_unclean := false
var _previous_tail := PackedStringArray()
var _no_freeze := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_log_dir()
	_load_config()
	_apply_cmdline_overrides()
	_rotate_session_log()
	_previous_unclean = _read_previous_unclean()
	_previous_tail = _read_log_tail(PREVIOUS_LOG, LOG_TAIL_LINES)
	_write_session_state(false)
	EventBus.diagnostic.connect(_on_diagnostic)
	EventBus.game_state_changed.connect(_on_state_changed)
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_ended.connect(_on_run_ended)
	EventBus.wave_started.connect(_on_wave_started)
	_overlay = DebugErrorOverlay.new()
	add_child(_overlay)
	_overlay.copy_requested.connect(_on_copy_requested)
	_overlay.save_requested.connect(_on_save_requested)
	_overlay.prev_requested.connect(show_previous_report)
	_overlay.next_requested.connect(show_next_report)
	_overlay.resume_requested.connect(resume)
	_overlay.restart_requested.connect(_on_restart_requested)
	_overlay.menu_requested.connect(_on_menu_requested)
	_log("info", "DebugErrorHandler ready (debug_mode=%s)" % ("ON" if _debug_mode else "OFF"))


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_OS_MEMORY_WARNING:
			_log("warning", "OS memory warning (static=%d MB)" % _megabytes(Performance.get_monitor(Performance.MEMORY_STATIC)))
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_EXIT_TREE:
			# The only paths that mark a clean exit. A crash, force-stop, or OS
			# background kill skips them, and the next boot notices.
			_write_session_state(true)


## ---------- Public flag API (used by the menu + settings toggles) ----------

func is_debug_mode() -> bool:
	return _debug_mode


func set_debug_mode(enabled: bool) -> void:
	if _debug_mode == enabled:
		return
	_debug_mode = enabled
	_save_config()
	_log("info", "Debug mode %s" % ("ENABLED" if enabled else "DISABLED"))
	debug_mode_changed.emit(enabled)


func toggle_debug_mode() -> bool:
	set_debug_mode(not _debug_mode)
	return _debug_mode


func has_reports() -> bool:
	return not _reports.is_empty()


func report_count() -> int:
	return _reports.size()


func had_unclean_previous_session() -> bool:
	return _previous_unclean


## ---------- Capture entry points ----------

## Manual capture entry for authored guards and the Settings self-test button.
## Honors the debug flag: when OFF the message is only logged to the session file.
func capture_error(message: String, stack: Array = [], extra: Dictionary = {}) -> void:
	_log("error", message)
	if not _debug_mode:
		return
	var frames: Array = stack if not stack.is_empty() else _capture_stack(2)
	var item := {"message": message, "stack": frames, "extra": extra}
	_pending.append(item)
	_drain_pending.call_deferred()


## Self-test: proves the whole pipeline (freeze + report + copy) on device.
func capture_test_error() -> void:
	if not _debug_mode:
		_log("warning", "Test error ignored: debug mode is OFF")
		return
	capture_error("Manual test error (Settings > Debug > Trigger test error)", [], {"self_test": true})


func _on_diagnostic(message: String, severity: StringName) -> void:
	# Every diagnostic is preserved to the buffer + session file either way, so a
	# later hard crash still leaves a trail. Only errors freeze, and only in
	# debug mode. Presenting is deferred: this runs synchronously inside the
	# reporter's call stack, but the stack snapshot must be taken right here.
	_log(String(severity), message)
	if severity != &"error" or not _debug_mode:
		return
	var item := {
		"message": message,
		"stack": _capture_stack(2),
		"extra": {"source": "eventbus"},
	}
	_pending.append(item)
	_drain_pending.call_deferred()


## Snapshot the live call stack, dropping this helper + its direct caller so
## frame #0 is the code that reported the error.
func _capture_stack(frames_to_drop: int) -> Array:
	var frames := get_stack()
	if frames_to_drop <= 0:
		return frames
	return frames.slice(mini(frames_to_drop, frames.size()))


## Low-frequency breadcrumbs so a report shows what the game was doing.
func _on_state_changed(previous: StringName, current: StringName) -> void:
	_log("info", "state %s -> %s" % [String(previous), String(current)])


func _on_run_started(run_id: int, run_seed: int) -> void:
	_log("info", "run started id=%d seed=%d" % [run_id, run_seed])


func _on_run_ended(score: int, wave: int, _best_score: int) -> void:
	_log("info", "run ended score=%d wave=%d" % [score, wave])


func _on_wave_started(wave_number: int, planned_count: int) -> void:
	_log("info", "wave %d started (%d planned)" % [wave_number, planned_count])


## ---------- Present / freeze / resume ----------

func _drain_pending() -> void:
	if _draining:
		return
	_draining = true
	while not _pending.is_empty():
		var item: Dictionary = _pending.pop_front()
		_present(item)
	_draining = false


func _present(item: Dictionary) -> void:
	var message := str(item.get("message", "(no message)"))
	var stack: Array = item.get("stack", [])
	var extra: Dictionary = item.get("extra", {})
	var log_lines: PackedStringArray = item.get("log", _buffer.tail(LOG_TAIL_LINES))
	var report := ErrorReport.build(_report_title(extra), message, stack, _gather_context(extra), log_lines)
	_reports.append(report)
	while _reports.size() > MAX_REPORTS:
		_reports.pop_front()
	_current = _reports.size() - 1
	_write_crash_file(report)
	error_captured.emit(_reports.size())
	_freeze()
	if _overlay != null:
		_overlay.show_report(report, _current, _reports.size())


func _report_title(extra: Dictionary) -> String:
	if bool(extra.get("self_test", false)):
		return "Self-test error (debug pipeline check)"
	if String(extra.get("source", "")) == "previous_session":
		return "Previous session ended unexpectedly (recovered log)"
	return "Runtime error captured before it could crash the game"


## Freeze the simulation. Headless/CI runs and --no-debug-freeze skip the pause
## (there is no screen to read the report on) but still log + write crash files.
func _freeze() -> void:
	if _frozen or _no_freeze:
		return
	if DisplayServer.get_name() == "headless":
		return
	var tree := get_tree()
	if tree == null:
		return
	_fallback_pause = tree.paused
	tree.paused = true
	_frozen = true


## Hide the overlay and restore the pre-freeze pause state. Kept reports stay
## available through Settings > Debug > View last report.
func resume() -> void:
	if _overlay != null:
		_overlay.hide_overlay()
	if not _frozen:
		return
	_frozen = false
	var tree := get_tree()
	if tree == null:
		return
	# GameRoot owns the canonical pause flag; the player may have (un)paused via
	# the Android Back button behind this overlay, so re-read it instead of
	# trusting the value captured at freeze time.
	tree.paused = GameRoot.is_paused() if GameRoot != null else _fallback_pause


func show_previous_report() -> void:
	_show_at(_current - 1)


func show_next_report() -> void:
	_show_at(_current + 1)


func _show_at(index: int) -> void:
	if _reports.is_empty() or _overlay == null:
		return
	_current = clampi(index, 0, _reports.size() - 1)
	_overlay.show_report(_reports[_current], _current, _reports.size())


## Re-open the newest captured report (Settings > Debug). Freezes while visible:
## the overlay is only ever shown on a frozen tree.
func show_last_report() -> void:
	if _reports.is_empty():
		return
	_current = _reports.size() - 1
	_freeze()
	if _overlay != null:
		_overlay.show_report(_reports[_current], _current, _reports.size())


## Present the previous session's recovered log tail like a fresh capture (kept
## separate from live reports by its title).
func show_previous_session_report() -> void:
	if _previous_tail.is_empty():
		return
	var item := {
		"message": "The previous session did not exit cleanly (crash, force-stop, or an OS background kill). Log tail recovered from disk.",
		"stack": [],
		"log": _previous_tail,
		"extra": {"source": "previous_session"},
	}
	_pending.append(item)
	_drain_pending.call_deferred()


## ---------- Copy / save ----------

func _on_copy_requested() -> void:
	# Deferred past input processing: when the report text has focus, the
	# TextEdit's own Ctrl+C (selection copy) runs during GUI input, and this
	# whole-report copy must be the last writer to the clipboard.
	_copy_and_report.call_deferred()


func _copy_and_report() -> void:
	if _reports.is_empty():
		return
	if copy_current_report():
		_feedback_to_overlay("COPIED ✓  (%s — paste it into your bug report)" % _kilobytes(_reports[_current]))
	else:
		_feedback_to_overlay("COPY FAILED — long-press the text above to select and copy it manually.")


func _feedback_to_overlay(message: String) -> void:
	if _overlay != null:
		_overlay.show_feedback(message)


## Copy the visible report to the OS clipboard. Returns false when the
## round-trip read-back disagrees (some Android keyboards block clipboard reads).
func copy_current_report() -> bool:
	if _reports.is_empty():
		return false
	var text := _reports[_current]
	DisplayServer.clipboard_set(text)
	return DisplayServer.clipboard_get() == text


func _on_save_requested() -> void:
	var path := save_current_report()
	if path.is_empty():
		_feedback_to_overlay("SAVE FAILED — storage may be unavailable.")
	else:
		_feedback_to_overlay("SAVED ✓  " + path)


## Write the visible report to its own file. Returns the path, or "" on failure.
## (Every capture is already auto-saved as a crash_*.log file; this is the
## explicit, user-confirmed copy.)
func save_current_report() -> String:
	if _reports.is_empty():
		return ""
	var path := "%s/report_%s.txt" % [LOG_DIR, ErrorReport.filename_stamp()]
	if _write_text_file(path, _reports[_current]):
		return path
	return ""


func _kilobytes(text: String) -> String:
	var kb := float(text.to_utf8_buffer().size()) / 1024.0
	return "%.1f KB" % kb


func _on_restart_requested() -> void:
	resume()
	if GameRoot != null:
		GameRoot.request_restart.call_deferred()


func _on_menu_requested() -> void:
	resume()
	if GameRoot != null:
		GameRoot.request_main_menu.call_deferred()


## ---------- Report context (reads only — must never report an error itself) ----------

func _gather_context(extra: Dictionary) -> Dictionary:
	var context := {}
	context["trigger"] = str(extra.get("source", "manual"))
	context["app_version"] = str(ProjectSettings.get_setting("application/config/version", "unknown"))
	var version := Engine.get_version_info()
	context["engine"] = "%s.%s.%s-%s" % [str(version.get("major", "?")), str(version.get("minor", "?")), str(version.get("patch", "?")), str(version.get("status", "?"))]
	context["debug_build"] = OS.is_debug_build()
	context["os"] = "%s %s" % [OS.get_name(), OS.get_version()]
	var model := OS.get_model_name()
	context["device_model"] = model if not model.is_empty() else "n/a"
	context["locale"] = OS.get_locale()
	context["display_server"] = DisplayServer.get_name()
	context["processors"] = OS.get_processor_count()
	context["memory_mb"] = "static=%d dynamic=%d" % [_megabytes(Performance.get_monitor(Performance.MEMORY_STATIC)), _megabytes(Performance.get_monitor(Performance.MEMORY_DYNAMIC))]
	context["fps"] = int(Performance.get_monitor(Performance.TIME_FPS))
	context["viewport"] = _viewport_size_text()
	context["scene"] = _current_scene_text()
	context["tree_paused"] = _tree_paused()
	context["game_state"] = _game_state_text()
	_merge_run_context(context)
	return context


func _megabytes(bytes_value: float) -> int:
	return int(bytes_value / 1048576.0)


func _viewport_size_text() -> String:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return "n/a"
	return str(tree.root.size)


func _current_scene_text() -> String:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return "none"
	var path := tree.current_scene.scene_file_path
	return path if not path.is_empty() else tree.current_scene.name


func _tree_paused() -> bool:
	var tree := get_tree()
	return tree.paused if tree != null else false


func _game_state_text() -> String:
	if GameRoot == null:
		return "unavailable"
	return String(GameRoot.get_current_state())


func _merge_run_context(context: Dictionary) -> void:
	if GameRoot == null:
		context["run"] = "unavailable"
		return
	var run := GameRoot.get_run()
	if run == null:
		context["run"] = "no active run"
		return
	var summary := run.summary()
	context["run_id"] = str(summary.get("run_id", "?"))
	context["run_mode"] = str(summary.get("mode_id", "?"))
	context["run_wave"] = str(summary.get("current_wave", "?"))
	context["run_score"] = str(summary.get("score", "?"))
	context["run_elapsed_s"] = str(snappedf(float(summary.get("elapsed_seconds", 0.0)), 0.1))
	context["run_victory"] = str(bool(summary.get("victory", false)))
	context["run_player_alive"] = str(bool(summary.get("player_alive", true)))


## ---------- Flag persistence (own file: must not depend on SaveManager) ----------

func _load_config() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		_debug_mode = false
		return
	_debug_mode = bool(config.get_value(CONFIG_SECTION, CONFIG_KEY, false))


func _save_config() -> void:
	var config := ConfigFile.new()
	config.set_value(CONFIG_SECTION, CONFIG_KEY, _debug_mode)
	if config.save(CONFIG_PATH) != OK:
		push_warning("DebugErrorHandler: could not persist debug_mode to %s" % CONFIG_PATH)


func _apply_cmdline_overrides() -> void:
	# QA automation: `-- --debug-mode` forces the flag on, `-- --debug-mode=off`
	# forces it off, `-- --no-debug-freeze` keeps logging while never pausing.
	for arg in OS.get_cmdline_user_args():
		if arg == CMDLINE_ENABLE:
			_debug_mode = true
		elif arg == CMDLINE_ENABLE + "=off":
			_debug_mode = false
		elif arg == CMDLINE_NO_FREEZE:
			_no_freeze = true


## ---------- Session log + crash files ----------

func _ensure_log_dir() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(LOG_DIR)):
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR)) != OK:
		push_warning("DebugErrorHandler: could not create %s" % LOG_DIR)


func _rotate_session_log() -> void:
	if not FileAccess.file_exists(SESSION_LOG):
		return
	_ensure_log_dir()
	var from := ProjectSettings.globalize_path(SESSION_LOG)
	var to := ProjectSettings.globalize_path(PREVIOUS_LOG)
	DirAccess.remove_absolute(to)
	if DirAccess.rename_absolute(from, to) != OK:
		push_warning("DebugErrorHandler: could not rotate the session log")


func _log(severity: String, message: String) -> void:
	var line := "[%s][%s] %s" % [ErrorReport.utc_now(), severity, message.strip_edges()]
	_buffer.push(line)
	_append_session_log(line)


func _append_session_log(line: String) -> void:
	if FileAccess.file_exists(SESSION_LOG):
		var probe := FileAccess.open(SESSION_LOG, FileAccess.READ)
		if probe != null and probe.get_length() > MAX_SESSION_LOG_BYTES:
			probe.close()
			_rotate_session_log()
		elif probe != null:
			probe.close()
	var file := FileAccess.open(SESSION_LOG, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(SESSION_LOG, FileAccess.WRITE)
	if file == null:
		push_warning("DebugErrorHandler: could not open the session log for append")
		return
	file.seek(file.get_length())
	file.store_line(line)
	file.close()


func _read_previous_unclean() -> bool:
	if not FileAccess.file_exists(SESSION_STATE):
		return false
	var file := FileAccess.open(SESSION_STATE, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return true
	return not bool((parsed as Dictionary).get("clean_exit", false))


func _write_session_state(clean_exit: bool) -> void:
	_ensure_log_dir()
	var payload := {"clean_exit": clean_exit, "version": str(ProjectSettings.get_setting("application/config/version", "unknown")), "utc": ErrorReport.utc_now()}
	var tmp := SESSION_STATE + ".tmp"
	if not _write_text_file(tmp, JSON.stringify(payload)):
		return
	var tmp_abs := ProjectSettings.globalize_path(tmp)
	var dst_abs := ProjectSettings.globalize_path(SESSION_STATE)
	DirAccess.remove_absolute(dst_abs)
	if DirAccess.rename_absolute(tmp_abs, dst_abs) != OK:
		push_warning("DebugErrorHandler: could not commit the session state file")


func _write_text_file(path: String, contents: String) -> bool:
	_ensure_log_dir()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("DebugErrorHandler: could not open %s for writing" % path)
		return false
	file.store_string(contents)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		push_warning("DebugErrorHandler: failed writing %s (error %d)" % [path, write_error])
		return false
	return true


func _write_crash_file(report: String) -> void:
	var path := "%s/crash_%s.log" % [LOG_DIR, ErrorReport.filename_stamp()]
	if _write_text_file(path, report):
		_prune_files("crash_", ".log", MAX_CRASH_FILES)


func _prune_files(prefix: String, suffix: String, keep: int) -> void:
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir() and entry.begins_with(prefix) and entry.ends_with(suffix):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()
	while names.size() > keep:
		var victim: String = names.pop_front()
		if dir.remove(victim) != OK:
			push_warning("DebugErrorHandler: could not prune old log %s" % victim)


func _read_log_tail(path: String, max_lines: int) -> PackedStringArray:
	var out := PackedStringArray()
	if not FileAccess.file_exists(path):
		return out
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	var all_lines := file.get_as_text().split("\n")
	file.close()
	var start := maxi(all_lines.size() - maxi(max_lines, 1), 0)
	for i in range(start, all_lines.size()):
		if not all_lines[i].strip_edges().is_empty():
			out.append(all_lines[i])
	return out


func get_debug_snapshot() -> Dictionary:
	return {
		"debug_mode": _debug_mode,
		"frozen": _frozen,
		"reports": _reports.size(),
		"pending": _pending.size(),
		"log_lines": _buffer.size(),
		"log_dropped": _buffer.dropped_count(),
		"previous_unclean": _previous_unclean,
	}
