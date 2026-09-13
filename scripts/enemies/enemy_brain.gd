class_name EnemyBrain
extends RefCounted

## The "who this individual is" half of EnemyBase (see docs/ENEMY_AI_RESEARCH.md):
## EnemyPerception (sight / FOV / LOS / hearing / reaction / memory), the rolled
## EnemyPersonality, the deterministic per-run identity (spawn serial, approach
## offset, decision stream), the shared ArenaNavGrid and the monotonic run clock the
## pack module timestamps grief kills against.
##
## Pure RefCounted, no nodes: every method reads the host through its public typed
## API, so the exact same module runs in-game and in the autoload-free headless
## harness. The host keeps the read facade the AI states call (get_perception /
## personality_roll / ...) — states never reach in here directly.

## Approach-offset radius (metres) rolled per spawn so packs fan out instead of
## stacking on one pixel; elites get the wider band so they read as anchors.
const APPROACH_OFFSET_RANGE := Vector2(0.0, 1.6)
const ELITE_APPROACH_OFFSET_RANGE := Vector2(0.55, 2.1)
## Aim quality used before a personality is rolled.
const DEFAULT_AIM_SKILL := 0.55
## Neutral decision-stream value used before the identity is rolled.
const DEFAULT_ROLL := 0.5
## Attack-cadence roll bounds (a swing never lands more than ±40% off the clock).
const COOLDOWN_ROLL_MIN := 0.6
const COOLDOWN_ROLL_MAX := 1.4
## Personality spread used before the identity is rolled.
const DEFAULT_COOLDOWN_SPREAD := 0.5
## Facing length below which the FOV cone falls back to world forward.
const FACING_EPSILON_SQ := 0.001

var perception := EnemyPerception.new()
## Rolled identity; null until set_spawn_serial() runs.
var personality: EnemyPersonality = null

var _decisions_rng: RandomNumberGenerator = null
var _run_seed := 0
var _spawn_serial := 0
var _approach_offset := Vector3.ZERO
var _home_pos := Vector3.ZERO
var _nav_grid: ArenaNavGrid = null
var _run_time := 0.0


## Accumulated physics seconds since spawn (monotonic per run). Ticked before the
## alive/config checks so the clock keeps running for a corpse in the fade window.
func tick(delta: float) -> void:
	_run_time += delta


func get_run_time() -> float:
	return _run_time


func set_run_seed(run_seed: int) -> void:
	_run_seed = run_seed


func get_run_seed() -> int:
	return _run_seed


func get_spawn_serial() -> int:
	return _spawn_serial


func remember_home(host: EnemyBase) -> void:
	_home_pos = host.global_position


func get_home_position() -> Vector3:
	return _home_pos


## Deterministic per-enemy identity: same (run_seed, serial) always rolls the same
## individual, and the approach offset keeps packs from stacking behind the player.
## Re-entrant safe — identical inputs yield identical values.
func set_spawn_serial(host: EnemyBase, serial: int) -> void:
	_spawn_serial = maxi(serial, 0)
	_roll_approach_offset(host)
	personality = EnemyPersonality.roll(_run_seed, _spawn_serial)
	_decisions_rng = RngService.make_generator(_run_seed, RngService.STREAM_AI + _spawn_serial * 13 + 901)
	# Personality scales the reaction time now that the cast is known.
	var config := host.get_config()
	if config != null:
		perception.reaction_base = maxf(config.reaction_time * personality.reaction, 0.0)


## The point this enemy actually tries to stand at: the target position nudged by
## its personal offset.
func get_approach_point(point: Vector3) -> Vector3:
	return point + _approach_offset


## Fresh deterministic 0..1 roll from this enemy's decision stream.
func personality_roll() -> float:
	if _decisions_rng == null:
		return DEFAULT_ROLL
	return _decisions_rng.randf()


## Ranged aim quality (0 sloppy .. 1 precise), from the rolled personality.
func get_aim_skill() -> float:
	return personality.aim_skill if personality != null else DEFAULT_AIM_SKILL


## Cooldown multiplier for this swing ([-jitter,+jitter] scaled by this individual's
## spread). Packs stop sharing one attack clock; melee hits land spread out.
func attack_cooldown_roll(host: EnemyBase) -> float:
	var cfg := host.get_config()
	if cfg == null or cfg.attack_cd_jitter <= 0.0:
		return 1.0
	var n := personality_roll()
	var spread := cfg.attack_cd_jitter * (personality.cd_spread if personality != null else DEFAULT_COOLDOWN_SPREAD)
	return clampf(1.0 + (n * 2.0 - 1.0) * spread, COOLDOWN_ROLL_MIN, COOLDOWN_ROLL_MAX)


## ---------- Perception ----------

## Reset + configure from the archetype config. `detect_range > 0` (legacy) wins over
## `vision_range`; both zero = always aware (original behavior).
func reset_perception(config: EnemyConfig) -> void:
	perception.reset()
	configure_perception(config)


func configure_perception(config: EnemyConfig) -> void:
	var vision := config.vision_range if config.detect_range <= 0.0 else config.detect_range
	var always_aware := vision <= 0.0
	perception.configure(vision, config.vision_fov_degrees, config.hearing_range,
			config.reaction_time, config.memory_time, always_aware)
	var reaction := config.reaction_time * (personality.reaction if personality != null else 1.0)
	perception.reaction_base = maxf(reaction, 0.0)
	_adopt_grid_los()


## Flat facing direction (visual yaw) used for the perception FOV cone.
func flat_forward(host: EnemyBase) -> Vector3:
	var f := -host.global_transform.basis.z
	f.y = 0.0
	if f.length_squared() < FACING_EPSILON_SQ:
		return Vector3.FORWARD
	return f.normalized()


## ---------- Shared arena navigation grid ----------

func set_nav_grid(grid: ArenaNavGrid) -> void:
	_nav_grid = grid
	perception.set_los_check(Callable(grid, &"has_line_of_sight") if grid != null else Callable())


func get_nav_grid() -> ArenaNavGrid:
	return _nav_grid


## Can this enemy currently see `point` (grid line of sight)? True without a grid —
## physics collision still covers the worst case.
func has_line_of_sight_to(host: EnemyBase, point: Vector3) -> bool:
	if _nav_grid == null or not _nav_grid.is_built():
		return true
	return _nav_grid.has_line_of_sight(host.global_position, point)


## Grid LOS follows the grid it was configured with; a null grid leaves the previous
## check alone (configure_perception must not clear a check the host never set).
func _adopt_grid_los() -> void:
	if _nav_grid != null:
		perception.set_los_check(Callable(_nav_grid, &"has_line_of_sight"))


func _roll_approach_offset(host: EnemyBase) -> void:
	if host.get_config() == null:
		return
	var rng := RngService.make_generator(_run_seed, RngService.STREAM_AI + _spawn_serial * 7 + 3)
	var angle := rng.randf_range(-PI, PI)
	var band := ELITE_APPROACH_OFFSET_RANGE if host.is_elite() else APPROACH_OFFSET_RANGE
	var radius := rng.randf_range(band.x, band.y)
	_approach_offset = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
