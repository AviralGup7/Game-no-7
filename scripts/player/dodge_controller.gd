extends Node
class_name DodgeController

## Real dodge/dash component (no longer a signal-only placeholder). Owns an explicit
## state machine and the physics integration that produces actual movement and real
## temporary invulnerability while dodging.
##
## Lifecycle (driven by tick(delta), called from the owner's physics loop):
##   READY -> (request) -> ACTIVE (burst + invulnerable) -> RECOVER -> COOLDOWN -> READY
##
## Timers advance only while tick() is called, so the game pausing (or the owner being
## disabled) freezes the dodge exactly like the rest of gameplay. All values are
## exported for tuning; progression can shorten the cooldown through the
## `dodge_cooldown_multiplier` derived stat.

signal dodged_started()
signal dodged_finished()

const PHASE_READY := &"ready"
const PHASE_ACTIVE := &"active"
const PHASE_RECOVER := &"recover"
const PHASE_COOLDOWN := &"cooldown"

@export var stamina_cost: float = 25.0
@export var duration: float = 0.18          # active burst length (fast, snappy)
@export var distance: float = 5.5           # total burst travel in metres
@export var cooldown: float = 0.8           # seconds before a new dodge is allowed
@export var invulnerability_duration: float = 0.3   # i-frames (can exceed active window)
@export var recovery_duration: float = 0.12 # stationary settle after the burst
@export var can_interrupt_attack: bool = true
@export var arena_bounds_half: float = -1.0 # -1 => no clamp (set by the scene owner)

var _body: CharacterBody3D = null
var _health: HealthComponent = null
var _phase: StringName = PHASE_READY
var _dir := Vector3.ZERO
var _speed := 0.0
var _elapsed := 0.0
var _cooldown_remaining := 0.0
var _invuln_granted := false

const GRAVITY := 18.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D


## Called by the owning player each physics step while control is enabled.
func tick(delta: float) -> void:
	if _body == null or delta <= 0.0:
		return
	if _cooldown_remaining > 0.0:
		_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
		if _cooldown_remaining <= 0.0 and _phase == PHASE_COOLDOWN:
			_finish_cycle()

	match _phase:
		PHASE_ACTIVE:
			var fraction := clampf((duration - _elapsed) / delta, 0.0, 1.0)
			_move_burst(delta, fraction)
			_elapsed += delta
			if _elapsed >= duration:
				_enter_recover()
		PHASE_RECOVER:
			_elapsed += delta
			_move_burst(delta)
			if _elapsed >= recovery_duration:
				_enter_cooldown()
		_:
			# READY / COOLDOWN: locomotion is owned entirely by the CharacterController
			# (which applies its own gravity), so the dodge does nothing here except the
			# cooldown accounting above. Never duplicate move_and_slide with the owner.
			pass


func is_ready() -> bool:
	return _phase == PHASE_READY


func is_dodging() -> bool:
	return _phase == PHASE_ACTIVE or _phase == PHASE_RECOVER


func is_in_active_window() -> bool:
	return _phase == PHASE_ACTIVE


func get_phase() -> StringName:
	return _phase


func get_cooldown_remaining() -> float:
	return _cooldown_remaining


func get_dodge_direction() -> Vector3:
	return _dir


## Request a dodge along `direction_world` (a normalized horizontal direction). The
## owner chooses the direction from its current input/facing. Returns true when the
## dodge begins; requests during cooldown/recovery are rejected (no re-fire).
func request(direction_world: Vector3) -> bool:
	if _body == null:
		return false
	if not is_ready():
		return false
	if _cooldown_remaining > 0.0:
		return false
	var dir := Vector3(direction_world.x, 0.0, direction_world.z)
	if dir.length_squared() < 0.0001:
		dir = -_body.global_transform.basis.z
	dir = dir.normalized()
	_dir = dir
	_speed = _burst_speed()
	_elapsed = 0.0
	_phase = PHASE_ACTIVE
	_invuln_granted = false
	_grant_invulnerability()
	dodged_started.emit()
	return true


## Sets the arena clamp half-extent; -1 disables clamping.
func set_bounds(half: float) -> void:
	arena_bounds_half = half


## Grants temporary invulnerability through the generic HealthComponent. Granting is
## done once at burst start so the whole i-frame window can outlive the burst.
func _grant_invulnerability() -> void:
	if _health != null:
		_health.set_invulnerable(maxf(invulnerability_duration, 0.0))
		_invuln_granted = true


func _burst_speed() -> float:
	if duration <= 0.0:
		return 0.0
	return maxf(distance / maxf(duration, 0.001), 0.0)


func _move_burst(delta: float, fraction: float = 1.0) -> void:
	# M3: dash intent requested here, actual movement via CharacterController when wired.
	var speed := _speed * fraction if _phase == PHASE_ACTIVE else 0.0
	var cc := _body.get_node_or_null("CharacterController") as CharacterController if _body != null else null
	if cc != null:
		cc.apply_dash(_dir, speed, delta)
		_clamp_to_bounds()
		return
	var vel := _body.velocity
	if not _body.is_on_floor():
		vel.y -= GRAVITY * delta
	vel.x = _dir.x * speed
	vel.z = _dir.z * speed
	_body.velocity = vel
	_body.move_and_slide()
	_clamp_to_bounds()


func _enter_recover() -> void:
	_phase = PHASE_RECOVER
	_elapsed = maxf(_elapsed - maxf(duration, 0.0), 0.0)
	if _elapsed >= recovery_duration:
		_enter_cooldown()


func _enter_cooldown() -> void:
	_phase = PHASE_COOLDOWN
	_cooldown_remaining = maxf(_effective_cooldown() - maxf(_elapsed - recovery_duration, 0.0), 0.0)
	if _cooldown_remaining <= 0.0:
		_finish_cycle()


func _finish_cycle() -> void:
	_phase = PHASE_READY
	dodged_finished.emit()


func _effective_cooldown() -> float:
	var base := maxf(cooldown, 0.05)
	var owner := _body
	if owner == null or not is_instance_valid(owner):
		return base
	var prog := owner.get_node_or_null("ProgressionComponent") as ProgressionComponent
	if prog != null:
		return maxf(prog.get_stat(&"dodge_cooldown_multiplier", base), 0.05)
	return base


func _clamp_to_bounds() -> void:
	if _body == null or arena_bounds_half < 0.0:
		return
	var limit := maxf(arena_bounds_half - 0.5, 0.0)
	var p := _body.global_position
	var clamped := Vector3(clampf(p.x, -limit, limit), p.y, clampf(p.z, -limit, limit))
	if clamped.x != p.x and _body.velocity.x * p.x > 0.0:
		_body.velocity.x = 0.0
	if clamped.z != p.z and _body.velocity.z * p.z > 0.0:
		_body.velocity.z = 0.0
	if clamped != p:
		_body.global_position = clamped


## Bind the owner's HealthComponent so i-frames are real.
func bind_health(health: HealthComponent) -> void:
	_health = health


func reset() -> void:
	_phase = PHASE_READY
	_dir = Vector3.ZERO
	_speed = 0.0
	_elapsed = 0.0
	_cooldown_remaining = 0.0
	_invuln_granted = false


func get_debug_snapshot() -> Dictionary:
	return {
		"phase": String(_phase),
		"is_dodging": is_dodging(),
		"cooldown_remaining": _cooldown_remaining,
		"duration": duration,
		"cooldown": cooldown,
		"distance": distance,
	}

