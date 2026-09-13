class_name EnemyMotion
extends RefCounted

## The movement half of EnemyBase: EnemyLocomotion (gravity / knockback decay /
## arena-bound clamp / stall recovery), EnemyNavigator (shared grid flow field, A*
## and the navmesh fallback), the timed movement override that dash charges and boss
## telegraphs/charges/recoveries win with, the dash cooldown gate, and visual facing.
##
## The AI states never touch this module: they write intent through the host's command
## surface (set_desired_move / set_move_override / face_target / try_begin_dash) and
## the host forwards. This module owns the per-frame integration because that is where
## gravity, knockback and the override have to agree on one velocity.

## Steering interval used when the host has no config (headless probes).
const DEFAULT_NAV_INTERVAL := 0.2
## Foot-plant stride in metres for the sand-step FX call.
const FOOT_PLANT_STRIDE := 0.16
## Below this squared length a direction is treated as "no direction" (facing guard).
const FACING_EPSILON := 0.0001

var _locomotion := EnemyLocomotion.new()
var _navigator := EnemyNavigator.new()
var _move_override_dir := Vector3.ZERO
var _move_override_speed := 0.0
var _move_override_time := 0.0
var _dash_cooldown_left := 0.0


## Re-arm the movement state for a (re)spawn: locomotion reset + configuration, clear
## the override and the dash cooldown. The arena clamp half extent survives, exactly
## like the pre-split code (SpawnManager sets it after initialize()).
func configure(config: EnemyConfig) -> void:
	_locomotion.reset()
	_locomotion.configure(config.acceleration, _locomotion.get_bounds(), config.bounds_radius)
	_move_override_time = 0.0
	_dash_cooldown_left = 0.0


func bind_navigator(agent: NavigationAgent3D) -> void:
	_navigator.bind(agent)


func reset_navigator(target: Node3D) -> void:
	_navigator.reset(target)


func set_grid(grid: ArenaNavGrid) -> void:
	_navigator.set_grid(grid)


## Timed decay of the override window and the dash cooldown (one physics step).
func tick(delta: float) -> void:
	if _move_override_time > 0.0:
		_move_override_time = maxf(_move_override_time - delta, 0.0)
	if _dash_cooldown_left > 0.0:
		_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)


## One AI physics step: the override wins over the state's intent, then EnemyLocomotion
## integrates gravity/knockback/steering for this frame.
func step(host: EnemyBase, slow_factor: float, delta: float) -> void:
	var dir := host.desired_dir
	var speed := host.desired_speed
	if _move_override_time > 0.0:
		dir = _move_override_dir
		speed = _move_override_speed
	_locomotion.integrate(host, dir, speed, slow_factor, delta)
	FootPlant.apply(host, FOOT_PLANT_STRIDE, delta)


## Stunned step: no AI, no intent; gravity + knockback decay still run and stall
## detection is off (the enemy is not supposed to be moving).
func freeze(host: EnemyBase, delta: float) -> void:
	_locomotion.integrate(host, Vector3.ZERO, 0.0, 1.0, delta, false)
	FootPlant.apply(host, FOOT_PLANT_STRIDE, delta)


func add_knockback(impulse: Vector3) -> void:
	_locomotion.add_knockback(impulse)


## Set arena-bound half extent; -1 disables the clamp.
func set_bounds(half: float) -> void:
	_locomotion.set_bounds(half)


## Replace the locomotion body's flat velocity (boss charges stamp it directly).
func set_velocity_flat(host: EnemyBase, flat: Vector3) -> void:
	host.velocity.x = flat.x
	host.velocity.z = flat.z


## ---------- Movement override (telegraphs / charges / recoveries) ----------

## While active, the override replaces whatever the AI states request. Pass a
## zero dir + zero speed to root the enemy in place (boss telegraph/recovery).
func set_override(dir: Vector3, speed: float, duration: float) -> void:
	_move_override_dir = dir
	_move_override_speed = maxf(speed, 0.0)
	_move_override_time = maxf(duration, 0.0)


func clear_override() -> void:
	_move_override_time = 0.0


func is_overridden() -> bool:
	return _move_override_time > 0.0


## ---------- Dash command (cooldown-gated entry from Chase) ----------

func try_begin_dash(host: EnemyBase) -> bool:
	var cfg := host.get_config()
	if cfg == null or cfg.dash_trigger_range <= 0.0:
		return false
	if _dash_cooldown_left > 0.0 or not host.is_alive():
		return false
	_dash_cooldown_left = cfg.dash_cooldown
	return true


func is_dash_ready() -> bool:
	return _dash_cooldown_left <= 0.0


## ---------- Facing (visual yaw) ----------

func face_direction(host: EnemyBase, dir: Vector3) -> void:
	if dir.length_squared() < FACING_EPSILON:
		return
	var visual := host.get_visual_root()
	if visual == null:
		return
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < FACING_EPSILON:
		return
	flat = flat.normalized()
	visual.look_at(visual.global_position + flat, Vector3.UP)


func face_target(host: EnemyBase, target: Node3D) -> void:
	if target == null:
		return
	face_direction(host, target.global_position - host.global_position)


## ---------- Navigation-aware steering (see EnemyNavigator) ----------

## Prefers the shared nav grid (line of sight, else flow field around obstacles), then
## the navmesh, then the caller's direct direction.
func direction(host: EnemyBase, fallback: Vector3) -> Vector3:
	var cfg := host.get_config()
	var interval := cfg.navigation_target_update_interval if cfg != null else DEFAULT_NAV_INTERVAL
	return _navigator.direction(host.global_position, host.get_move_target(), fallback, interval)


## Steer toward a fixed world point (investigation / waypoint) through the nav
## grid when wired; direct steering otherwise.
func direction_toward(host: EnemyBase, point: Vector3, fallback: Vector3, delta: float) -> Vector3:
	return _navigator.direction_toward(host.global_position, point, fallback, delta)
