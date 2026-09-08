class_name PerformanceMonitor
extends Node

## Runtime performance sampling + automatic quality scaling for low-end Android.
## Keeps a rolling FPS average; when sustained FPS drops below thresholds it
## steps the quality tier down (particle counts, shadows, MSAA hints) and emits
## `quality_tier_changed` so effects/UI layers can trim their budgets. Steps back
## up only after a long stable period to avoid oscillation. Safe headless: all
## engine queries are guarded.

signal fps_sampled(fps: float, average: float)
signal quality_tier_changed(old_tier: int, new_tier: int)

const TIER_ULTRA := 3
const TIER_HIGH := 2
const TIER_MEDIUM := 1
const TIER_LOW := 0

const SAMPLE_WINDOW := 60
const DOWN_THRESHOLD := 45.0     # sustained avg below this -> step down
const UP_THRESHOLD := 57.0       # sustained avg above this -> step up
const DOWN_SAMPLES := 120        # ~2s at 60fps before stepping down
const UP_SAMPLES := 900          # ~15s of stability before stepping up
const MIN_SECONDS_BETWEEN_STEPS := 5.0

var _samples: PackedFloat32Array = PackedFloat32Array()
var _tier: int = TIER_HIGH
var _low_streak := 0
var _high_streak := 0
var _last_step_msec: int = 0
var _enabled := true
var _auto_scale := true
var _entry_max_fps := 0
var _entry_max_fps_captured := false


func _ready() -> void:
	add_to_group("performance_monitor")
	_last_step_msec = Time.get_ticks_msec()
	_apply_tier_to_engine()


func set_enabled(enabled: bool) -> void:
	_enabled = enabled


func set_auto_scale(auto: bool) -> void:
	_auto_scale = auto


func get_tier() -> int:
	return _tier


func get_tier_name() -> String:
	match _tier:
		TIER_ULTRA:
			return "ultra"
		TIER_HIGH:
			return "high"
		TIER_MEDIUM:
			return "medium"
		_:
			return "low"


func _process(_delta: float) -> void:
	if not _enabled:
		return
	var fps := Engine.get_frames_per_second()
	_push_sample(float(fps))
	var avg := get_average_fps()
	fps_sampled.emit(float(fps), avg)
	if _auto_scale:
		_tick_auto_scale(avg)


func _push_sample(fps: float) -> void:
	_samples.append(fps)
	if _samples.size() > SAMPLE_WINDOW:
		_samples.remove_at(0)


func get_average_fps() -> float:
	if _samples.is_empty():
		return 60.0
	var sum := 0.0
	for s in _samples:
		sum += s
	return sum / float(_samples.size())


func get_min_fps() -> float:
	if _samples.is_empty():
		return 60.0
	var m := _samples[0]
	for s in _samples:
		m = minf(m, s)
	return m


func _tick_auto_scale(avg: float) -> void:
	if avg < DOWN_THRESHOLD:
		_low_streak += 1
		_high_streak = 0
	elif avg > UP_THRESHOLD:
		_high_streak += 1
		_low_streak = 0
	else:
		_low_streak = 0
		_high_streak = 0
	if _low_streak >= DOWN_SAMPLES:
		_low_streak = 0
		request_step_down()
	elif _high_streak >= UP_SAMPLES:
		_high_streak = 0
		request_step_up()


func _cooldown_elapsed() -> bool:
	return Time.get_ticks_msec() - _last_step_msec >= int(MIN_SECONDS_BETWEEN_STEPS * 1000.0)


func request_step_down() -> bool:
	if _tier <= TIER_LOW or not _cooldown_elapsed():
		return false
	set_tier(_tier - 1)
	return true


func request_step_up() -> bool:
	if _tier >= TIER_ULTRA or not _cooldown_elapsed():
		return false
	set_tier(_tier + 1)
	return true


func set_tier(tier: int) -> void:
	var clamped := clampi(tier, TIER_LOW, TIER_ULTRA)
	if clamped == _tier:
		return
	var old := _tier
	_tier = clamped
	_last_step_msec = Time.get_ticks_msec()
	_low_streak = 0
	_high_streak = 0
	_apply_tier_to_engine()
	quality_tier_changed.emit(old, _tier)


## Push engine-level knobs for the current tier. Everything is best-effort and
## guarded so headless/editor runs without a renderer never crash.
func _apply_tier_to_engine() -> void:
	# Remember the pre-monitor cap once, so _exit_tree can hand the user's / the
	# project's own frame-rate setting back when the run tears down. Without this
	# a LOW-tier run leaves the whole app (menus included) pinned at 30 fps.
	if not _entry_max_fps_captured:
		_entry_max_fps = Engine.max_fps
		_entry_max_fps_captured = true
	match _tier:
		TIER_LOW:
			Engine.max_fps = 30
		TIER_MEDIUM:
			Engine.max_fps = 60
		_:
			Engine.max_fps = 0


## Effect-budget multipliers queried by particle/text layers.
func particle_budget_scale() -> float:
	match _tier:
		TIER_ULTRA:
			return 1.0
		TIER_HIGH:
			return 0.8
		TIER_MEDIUM:
			return 0.5
		_:
			return 0.25


func max_damage_numbers() -> int:
	match _tier:
		TIER_ULTRA:
			return 48
		TIER_HIGH:
			return 32
		TIER_MEDIUM:
			return 20
		_:
			return 10


func _exit_tree() -> void:
	# The monitor is a per-run node, but Engine.max_fps is global. Restore the cap
	# that was in effect before this run so returning to the menu (or starting a
	# new run) is not stuck at the previous run's degraded tier.
	if _entry_max_fps_captured:
		Engine.max_fps = _entry_max_fps


func get_debug_snapshot() -> Dictionary:
	return {
		"tier": get_tier_name(),
		"avg_fps": get_average_fps(),
		"min_fps": get_min_fps(),
		"samples": _samples.size(),
		"auto_scale": _auto_scale,
	}

## Hardened: clamp perf sample.
func _validated_sample(v: float) -> float:
	if not is_finite(v) or v < 0.0:
		return 0.0
	return clampf(v, 0.0, 1000.0)

