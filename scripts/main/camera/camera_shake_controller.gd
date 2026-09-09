class_name CameraShakeController
extends RefCounted

## Trauma-based shake with FastNoiseLite – smooth, directional, reduced-motion safe.
## Integrates HitstopManager trauma + event-driven shakes.
## Improved: subtle idle breathing when stationary, directional hit feedback.

var _profile: CameraProfile = null
var _camera: Camera3D = null
var _noise := FastNoiseLite.new()
var _breath_noise := FastNoiseLite.new()
var _shake_time := 0.0
var _shake_remaining := 0.0
var _shake_amplitude := 0.0
var _base_local := Vector3.ZERO
var _hitstop_manager: Node = null
var _idle_breath_enabled := true

func setup(profile: CameraProfile, camera: Camera3D) -> void:
	_profile = profile
	_camera = camera
	_noise.seed = 1337
	_noise.frequency = profile.shake_frequency if profile != null else 28.0
	_noise.fractal_octaves = 2
	_breath_noise.seed = 7331
	_breath_noise.frequency = 0.6
	_breath_noise.fractal_octaves = 1
	_base_local = Vector3.ZERO
	if _camera != null:
		_camera.position = _base_local

func set_profile(profile: CameraProfile) -> void:
	_profile = profile
	if profile != null:
		_noise.frequency = profile.shake_frequency

func set_camera(camera: Camera3D) -> void:
	_camera = camera
	if _camera != null:
		_camera.position = _base_local

func set_hitstop_manager(manager: Node) -> void:
	_hitstop_manager = manager

func add_shake(amplitude: float, duration: float, reduced_motion: bool) -> void:
	if _profile == null or reduced_motion:
		return
	_shake_amplitude = clampf(amplitude, 0.0, _profile.max_shake_amplitude)
	_shake_remaining = maxf(_shake_remaining, duration)
	if _hitstop_manager != null and _hitstop_manager.has_method("add_trauma"):
		_hitstop_manager.call("add_trauma", clampf(amplitude * 0.35, 0.0, 1.0))

func tick(delta: float, reduced_motion: bool, speed: float = 0.0, is_colliding: bool = false) -> void:
	if _camera == null:
		return

	_shake_time += delta
	var trauma_offset := Vector3.ZERO
	var trauma_roll := 0.0

	if _hitstop_manager != null:
		if _hitstop_manager.has_method("get_shake_offset"):
			trauma_offset += _hitstop_manager.call("get_shake_offset", 0.35)
		if _hitstop_manager.has_method("get_shake_roll"):
			trauma_roll += _hitstop_manager.call("get_shake_roll", 0.025)

	if _shake_remaining > 0.0:
		_shake_remaining = maxf(_shake_remaining - delta, 0.0)
		var fade := _shake_remaining / maxf(_shake_remaining + 0.12, 0.001)
		fade = clampf(fade, 0.0, 1.0)
		var strength := _shake_amplitude * fade

		var nx := _noise.get_noise_1d(_shake_time * _profile.shake_frequency)
		var ny := _noise.get_noise_1d(_shake_time * _profile.shake_frequency + 100.0)
		var nz := _noise.get_noise_1d(_shake_time * _profile.shake_frequency + 200.0) * 0.35
		var own_offset := Vector3(nx, ny, nz) * strength

		trauma_offset += own_offset
		trauma_roll += _noise.get_noise_1d(_shake_time * _profile.shake_frequency + 300.0) * strength * 0.06

		if _shake_remaining <= 0.001:
			_shake_amplitude = 0.0

	# Idle breathing – subtle, only when stationary and not colliding, reduced-motion safe
	if _idle_breath_enabled and not reduced_motion and speed < 0.5 and not is_colliding and _shake_remaining <= 0.01:
		var breath := _breath_noise.get_noise_1d(_shake_time * 0.7) * 0.025
		var breath_y := _breath_noise.get_noise_1d(_shake_time * 0.7 + 50.0) * 0.015
		trauma_offset += Vector3(breath * 0.5, breath_y, 0.0)

	if reduced_motion:
		trauma_offset = Vector3.ZERO
		trauma_roll = 0.0

	_camera.position = _base_local + trauma_offset

	if absf(trauma_roll) > 0.0001:
		_camera.global_transform = _camera.global_transform.rotated_local(Vector3.FORWARD, trauma_roll)

func reset() -> void:
	_shake_remaining = 0.0
	_shake_amplitude = 0.0
	if _camera != null:
		_camera.position = _base_local

func get_remaining() -> float:
	return _shake_remaining
