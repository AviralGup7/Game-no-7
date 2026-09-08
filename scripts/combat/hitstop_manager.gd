class_name HitstopManager
extends Node

## Juice coordinator: hitstop (brief timescale dips on heavy hits), trauma-based
## screen shake (decaying noise consumed by the CameraRig), and slow-mo kill
## flourishes. All effects are time-bounded and self-restoring; reduced-motion
## settings collapse shake to zero. Safe headless: Engine.time_scale writes are
## guarded and restored.

signal shake_started(strength: float)
signal hitstop_started(duration: float, scale: float)

const MAX_TRAUMA := 1.0
const TRAUMA_DECAY_PER_SECOND := 1.6
const MAX_HITSTOP_SECONDS := 0.25
const MIN_TIME_SCALE := 0.05

var _trauma := 0.0
var _hitstop_left := 0.0
var _hitstop_scale := 1.0
var _slowmo_left := 0.0
var _slowmo_scale := 1.0
var _reduced_motion := false
var _noise_time := 0.0
var _noise := FastNoiseLite.new()


func _ready() -> void:
	add_to_group("hitstop_manager")
	_noise.seed = 1234
	_noise.frequency = 28.0
	_noise.fractal_octaves = 2


func set_reduced_motion(reduced: bool) -> void:
	_reduced_motion = reduced
	if reduced:
		_trauma = 0.0


## Add trauma in [0,1] (clamped). CameraRig queries get_shake_offset().
func add_trauma(amount: float) -> void:
	if _reduced_motion or amount <= 0.0:
		return
	var before := _trauma
	_trauma = clampf(_trauma + amount, 0.0, MAX_TRAUMA)
	if before <= 0.0 and _trauma > 0.0:
		shake_started.emit(_trauma)


## Freeze-frame hitstop: timescale drops to `scale` for `duration` real seconds.
func request_hitstop(duration: float, scale: float = 0.05) -> void:
	duration = clampf(duration, 0.0, MAX_HITSTOP_SECONDS)
	if duration <= 0.0:
		return
	_hitstop_left = maxf(_hitstop_left, duration)
	_hitstop_scale = clampf(scale, MIN_TIME_SCALE, 1.0)
	hitstop_started.emit(duration, _hitstop_scale)


## Longer dramatic slow motion (kill flourishes, boss phase changes).
func request_slowmo(duration: float, scale: float = 0.35) -> void:
	if duration <= 0.0:
		return
	_slowmo_left = maxf(_slowmo_left, duration)
	_slowmo_scale = clampf(scale, MIN_TIME_SCALE, 1.0)


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.001)
	_trauma = maxf(_trauma - TRAUMA_DECAY_PER_SECOND * real, 0.0)
	_noise_time += real
	var target_scale := 1.0
	if _hitstop_left > 0.0:
		_hitstop_left -= real
		target_scale = minf(target_scale, _hitstop_scale)
	if _slowmo_left > 0.0:
		_slowmo_left -= real
		target_scale = minf(target_scale, _slowmo_scale)
	if Engine.time_scale != target_scale:
		Engine.time_scale = target_scale


## Current shake offset in local camera space (trauma^2 * noise * strength).
func get_shake_offset(strength: float = 0.35) -> Vector3:
	if _trauma <= 0.0 or _reduced_motion:
		return Vector3.ZERO
	var s := _trauma * _trauma * strength
	return Vector3(
		_noise.get_noise_1d(_noise_time) * s,
		_noise.get_noise_1d(_noise_time + 100.0) * s,
		0.0
	)


## Current shake roll in radians for the camera.
func get_shake_roll(max_roll: float = 0.02) -> float:
	if _trauma <= 0.0 or _reduced_motion:
		return 0.0
	return _noise.get_noise_1d(_noise_time + 200.0) * _trauma * _trauma * max_roll


func current_trauma() -> float:
	return _trauma


func is_frozen() -> bool:
	return _hitstop_left > 0.0 or _slowmo_left > 0.0


func reset_effects() -> void:
	_trauma = 0.0
	_hitstop_left = 0.0
	_slowmo_left = 0.0
	Engine.time_scale = 1.0


func _exit_tree() -> void:
	# Always restore global time_scale when the manager leaves the tree so a
	# stale hitstop/slowmo never freezes the game after a run teardown.
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0


func get_debug_snapshot() -> Dictionary:
	return {
		"trauma": _trauma,
		"hitstop_left": _hitstop_left,
		"slowmo_left": _slowmo_left,
		"time_scale": Engine.time_scale,
	}
