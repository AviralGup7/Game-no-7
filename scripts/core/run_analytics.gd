extends Node
## Autoload: RunAnalytics
## Records local, offline-only run statistics for UI, balancing, debugging and future
## offline achievements. It must NEVER require network access or external accounts.
## GameRoot pushes the full run summary via record_run_end() at finalize time (the
## run_ended signal carries only headline numbers, so nothing is double-captured).
## Persistence delegates to SaveManager (lifetime statistics); this autoload keeps a
## small in-memory session view and exposes query hooks.

var _session_runs: Array[Dictionary] = []


func _ready() -> void:
	EventBus.report_info("RunAnalytics ready (offline only)")


func record_run_end(summary: Dictionary) -> void:
	_session_runs.append(summary.duplicate())
	# Cap in-memory retention to a small window; durable totals live in the save.
	if _session_runs.size() > 64:
		_session_runs.pop_front()


## Aggregate lifetime totals from the save.
func get_lifetime() -> Dictionary:
	return SaveManager.get_save_dict().get("lifetime_statistics", {})


## Aggregate over the current session window (for a post-run summary/dev view).
func get_session_totals() -> Dictionary:
	var runs := 0
	var kills := 0
	var seconds := 0.0
	for run in _session_runs:
		runs += 1
		kills += int(run.get("kills", 0))
		seconds += float(run.get("elapsed_seconds", 0.0))
	return {"session_runs": runs, "session_kills": kills, "session_time_seconds": seconds}


func get_debug_snapshot() -> Dictionary:
	return {
		"session_runs": _session_runs.size(),
		"session_totals": get_session_totals(),
		"lifetime": get_lifetime(),
	}

## Hardened: clamp analytics window.
func _validated_analytics_window(w: float) -> float:
	if not is_finite(w) or w <= 0.0:
		return 60.0
	return clampf(w, 1.0, 3600.0)

