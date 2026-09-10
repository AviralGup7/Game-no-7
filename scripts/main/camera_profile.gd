class_name CameraProfile
extends Resource

## Data-driven third-person camera tuning – MODULAR & IMPROVED.
## One profile per arena / mode / accessory so future arenas, bosses, or accessibility
## modes change the camera without code edits. Validated centrally.
##
## Perfect camera inspiration:
## - Elden Ring / Souls: gentle auto-follow, deadzone, toward-camera suppression
## - Zelda BOTW/OOT: spring-arm sphere-cast, pitch limits, reset, predictive focus
## - God of War 2018 / TLOU / Uncharted: cinematic framing, separate smoothing, FOV boost
## - GDC Fundamentals: preserve control frame, never instant snap

@export var profile_id: StringName = &"default"

# --- Core framing (legacy kept) ---
@export var distance: float = 9.0
@export var height: float = 5.5
@export var field_of_view: float = 62.0
@export var follow_smoothing: float = 6.0
@export var look_height: float = 1.5
@export var pitch_degrees: float = 32.0
@export var collision_radius: float = 0.35
@export var reduced_motion_smoothing: float = 2.0
@export var max_shake_amplitude: float = 1.0

# --- Orbit & Smoothing (modular: CameraOrbitController) ---
@export_group("Orbit & Smoothing")
@export var yaw_smoothing: float = 3.2
@export var pitch_smoothing: float = 3.0
@export var fov_smoothing: float = 5.0
@export var position_smoothing: float = 8.0
@export var distance_smoothing_in: float = 14.0
@export var distance_smoothing_out: float = 2.8
@export var min_pitch_deg: float = 8.0
@export var max_pitch_deg: float = 72.0
@export var min_distance: float = 2.8
@export var max_distance: float = 16.0
@export var orbit_speed_deg: float = 95.0
@export var orbit_input_deadzone: float = 0.12
@export var mouse_orbit_sensitivity: float = 0.22

# --- Framing & Prediction (modular: CameraFocusTracker, CameraFramingController) ---
@export_group("Framing & Prediction")
@export var shoulder_offset: Vector2 = Vector2(0.55, 0.15)
@export var predictive_factor: float = 0.18
@export var look_ahead_distance: float = 1.6
@export var velocity_influence: float = 0.65
@export var focus_height_lerp: float = 4.0
@export var ground_clearance: float = 0.9

# --- Auto Follow (modular: CameraAutoFollowController) ---
@export_group("Auto Follow (Elden Ring / Souls style)")
@export var auto_follow_enabled: bool = true
@export var auto_follow_delay: float = 0.55
@export var auto_follow_speed: float = 1.35
@export var auto_follow_deadzone_deg: float = 28.0
	@export var auto_follow_toward_camera_threshold: float = 0.25
@export var auto_follow_strafe_suppression: float = 0.65
@export var manual_orbit_cooldown: float = 2.0

# --- Collision (modular: CameraCollisionSolver) ---
@export_group("Collision")
@export var use_sphere_cast: bool = true
@export var collision_recovery_delay: float = 0.12
@export var whisker_count: int = 4
@export var whisker_angle_deg: float = 18.0

# --- FOV Dynamics (modular: CameraFovController) ---
@export_group("FOV Dynamics")
@export var fov_speed_boost: float = 3.0
@export var fov_max_boost: float = 6.0
@export var fov_sprint_threshold: float = 5.5

# --- Shake & Polish (modular: CameraShakeController) ---
@export_group("Shake & Polish")
@export var shake_frequency: float = 28.0
@export var shake_decay: float = 1.6

# --- Combat Framing (NEW – modular: CameraFramingController) ---
@export_group("Combat Framing")
@export var combat_framing_enabled: bool = true
@export var combat_enemy_radius: float = 8.0
@export var combat_distance_boost_2: float = 0.4
@export var combat_distance_boost_4: float = 1.2
@export var combat_distance_boost_6: float = 2.5
@export var combat_fov_boost_4: float = 2.0
@export var combat_fov_boost_6: float = 4.0
@export var combat_check_interval: float = 0.25

# --- Mode Blending (NEW – modular: CameraModeController) ---
@export_group("Mode Blending")
@export var mode_blend_duration_explore: float = 0.5
@export var mode_blend_duration_combat: float = 0.8
@export var mode_blend_duration_boss: float = 1.0
@export var mode_blend_duration_locked: float = 0.35
@export var boss_fov_multiplier: float = 1.08
@export var boss_distance_multiplier: float = 1.25
@export var combat_fov_multiplier: float = 1.04
@export var combat_distance_multiplier: float = 1.1
@export var locked_fov_multiplier: float = 0.96
@export var locked_distance_multiplier: float = 0.85

# --- Lock-On (NEW) ---
@export_group("Lock-On")
@export var lock_on_enabled: bool = true
@export var lock_on_max_distance: float = 18.0
@export var lock_on_midpoint_factor: float = 0.5

const MIN_DISTANCE_LEGACY: float = 2.0
const MAX_DISTANCE_LEGACY: float = 30.0


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(profile_id).is_empty():
		problems.append("profile_id is empty")
	if distance < MIN_DISTANCE_LEGACY or distance > MAX_DISTANCE_LEGACY:
		problems.append("distance out of safe range")
	if height < 0.5 or height > 20.0:
		problems.append("height out of safe range")
	if field_of_view < 40.0 or field_of_view > 110.0:
		problems.append("field_of_view out of safe range")
	if follow_smoothing <= 0.0:
		problems.append("follow_smoothing must be > 0")
	if look_height < 0.0:
		problems.append("look_height cannot be negative")
	if pitch_degrees < -89.0 or pitch_degrees > 89.0:
		problems.append("pitch_degrees must be within [-89, 89]")
	if yaw_smoothing <= 0.0:
		problems.append("yaw_smoothing must be > 0")
	if pitch_smoothing <= 0.0:
		problems.append("pitch_smoothing must be > 0")
	if min_distance < 0.5 or max_distance > 40.0 or min_distance >= max_distance:
		problems.append("min/max distance invalid")
	if min_pitch_deg < -10.0 or max_pitch_deg > 85.0 or min_pitch_deg >= max_pitch_deg:
		problems.append("min/max pitch invalid")
	return problems

func _clamp_profile_fields() -> void:
	if not is_finite(field_of_view) or field_of_view <= 0.0:
		field_of_view = 75.0
	field_of_view = clampf(field_of_view, 10.0, 120.0)
	if not is_finite(distance) or distance <= 0.0:
		distance = 10.0
	distance = clampf(distance, 1.0, 50.0)
	if not is_finite(height):
		height = 5.5
	height = clampf(height, 0.5, 20.0)
	if not is_finite(look_height):
		look_height = 1.5
	look_height = clampf(look_height, 0.0, 5.0)
	if not is_finite(pitch_degrees):
		pitch_degrees = 32.0
	pitch_degrees = clampf(pitch_degrees, -80.0, 80.0)

	yaw_smoothing = _sanitize_smoothing(yaw_smoothing, 3.2)
	pitch_smoothing = _sanitize_smoothing(pitch_smoothing, 3.0)
	fov_smoothing = _sanitize_smoothing(fov_smoothing, 5.0)
	position_smoothing = _sanitize_smoothing(position_smoothing, 8.0)
	distance_smoothing_in = _sanitize_smoothing(distance_smoothing_in, 14.0)
	distance_smoothing_out = _sanitize_smoothing(distance_smoothing_out, 2.8)
	focus_height_lerp = _sanitize_smoothing(focus_height_lerp, 4.0)

	min_pitch_deg = clampf(min_pitch_deg, 0.0, 80.0)
	max_pitch_deg = clampf(max_pitch_deg, 5.0, 85.0)
	if min_pitch_deg >= max_pitch_deg:
		min_pitch_deg = 8.0
		max_pitch_deg = 72.0

	min_distance = clampf(min_distance, 1.0, 20.0)
	max_distance = clampf(max_distance, 2.0, 40.0)
	if min_distance >= max_distance:
		min_distance = 2.8
		max_distance = 16.0

	auto_follow_delay = clampf(auto_follow_delay, 0.0, 2.0)
	auto_follow_speed = clampf(auto_follow_speed, 0.1, 5.0)
	auto_follow_deadzone_deg = clampf(auto_follow_deadzone_deg, 0.0, 90.0)
	# Authored as a positive dot product (0.25 = moving toward the lens). A
	# negative leftover from an earlier sign convention would suppress follow
	# on almost every heading; treat it as the documented default.
	if auto_follow_toward_camera_threshold < 0.0 or not is_finite(auto_follow_toward_camera_threshold):
		auto_follow_toward_camera_threshold = 0.25
	else:
		auto_follow_toward_camera_threshold = clampf(auto_follow_toward_camera_threshold, 0.0, 1.0)

	collision_radius = clampf(collision_radius, 0.05, 1.5)
	ground_clearance = clampf(ground_clearance, 0.1, 3.0)

	combat_enemy_radius = clampf(combat_enemy_radius, 2.0, 20.0)
	combat_check_interval = clampf(combat_check_interval, 0.05, 1.0)
	lock_on_max_distance = clampf(lock_on_max_distance, 5.0, 40.0)

func _sanitize_smoothing(v: float, fallback: float) -> float:
	if not is_finite(v) or v <= 0.0:
		return fallback
	return clampf(v, 0.1, 30.0)

func get_clamped_pitch_deg() -> float:
	return clampf(pitch_degrees, min_pitch_deg, max_pitch_deg)

func get_clamped_distance() -> float:
	return clampf(distance, min_distance, max_distance)
